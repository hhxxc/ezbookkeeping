package llm

import (
	"net/url"
	"strings"
	"sync/atomic"
	"time"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/llm/data"
	"github.com/mayswind/ezbookkeeping/pkg/llm/provider"
	"github.com/mayswind/ezbookkeeping/pkg/llm/provider/anthropic"
	"github.com/mayswind/ezbookkeeping/pkg/llm/provider/googleai"
	"github.com/mayswind/ezbookkeeping/pkg/llm/provider/lmstudio"
	"github.com/mayswind/ezbookkeeping/pkg/llm/provider/ollama"
	"github.com/mayswind/ezbookkeeping/pkg/llm/provider/openai"
	"github.com/mayswind/ezbookkeeping/pkg/log"
	"github.com/mayswind/ezbookkeeping/pkg/settings"
)

const (
	// the number of consecutive failures after which a model is temporarily skipped
	receiptImageRecognitionModelCooldownAfterFailures uint32 = 2

	// how long a failed model is skipped, the duration is doubled for every further failure (up to 8 times)
	receiptImageRecognitionModelCooldownDuration time.Duration = 60 * time.Second

	// the maximum multiplier of the cooldown duration
	receiptImageRecognitionModelMaxCooldownMultiplier uint32 = 8

	// do not start another attempt when less than this duration is left in the whole request budget
	receiptImageRecognitionMinRemainingTime time.Duration = 5 * time.Second
)

// receiptImageRecognitionModelEntry contains one configured receipt image recognition model
//
// NOTE: the atomic counters use the sync/atomic value types (instead of bare uint32/int64 fields updated through
// the atomic package functions) on purpose: the value types always keep their required 64-bit alignment, while a
// plain int64 field inside a struct can be misaligned on 32-bit ARM and make an atomic access panic with
// "unaligned 64-bit atomic operation".
type receiptImageRecognitionModelEntry struct {
	config   *settings.LLMConfig
	provider provider.LargeLanguageModelProvider
	label    string

	consecutiveFailures    atomic.Uint32
	cooldownUntilUnixMilli atomic.Int64
}

func (e *receiptImageRecognitionModelEntry) isInCooldown(now time.Time) bool {
	return e.cooldownUntilUnixMilli.Load() > now.UnixMilli()
}

func (e *receiptImageRecognitionModelEntry) remainingCooldown(now time.Time) time.Duration {
	cooldownUntil := e.cooldownUntilUnixMilli.Load()

	if cooldownUntil <= now.UnixMilli() {
		return 0
	}

	return time.Duration(cooldownUntil-now.UnixMilli()) * time.Millisecond
}

func (e *receiptImageRecognitionModelEntry) recordSuccess() {
	e.consecutiveFailures.Store(0)
	e.cooldownUntilUnixMilli.Store(0)
}

func (e *receiptImageRecognitionModelEntry) recordFailure(now time.Time) time.Duration {
	failures := e.consecutiveFailures.Add(1)

	if failures < receiptImageRecognitionModelCooldownAfterFailures {
		return 0
	}

	multiplier := failures - receiptImageRecognitionModelCooldownAfterFailures

	if multiplier > 3 {
		multiplier = 3
	}

	cooldown := receiptImageRecognitionModelCooldownDuration * time.Duration(1<<multiplier)

	if cooldown > receiptImageRecognitionModelCooldownDuration*time.Duration(receiptImageRecognitionModelMaxCooldownMultiplier) {
		cooldown = receiptImageRecognitionModelCooldownDuration * time.Duration(receiptImageRecognitionModelMaxCooldownMultiplier)
	}

	e.cooldownUntilUnixMilli.Store(now.Add(cooldown).UnixMilli())

	return cooldown
}

// LargeLanguageModelProviderContainer contains all configured large language model providers
type LargeLanguageModelProviderContainer struct {
	// the rotation counter must stay the first field so that it is always 64-bit aligned
	receiptImageRecognitionRotation        atomic.Uint64
	receiptImageRecognitionCurrentProvider provider.LargeLanguageModelProvider
	receiptImageRecognitionModels          []*receiptImageRecognitionModelEntry
}

// Initialize a large language model provider container singleton instance
var (
	Container = &LargeLanguageModelProviderContainer{}
)

// InitializeLargeLanguageModelProvider initializes the current large language model provider according to the config
func InitializeLargeLanguageModelProvider(config *settings.Config) error {
	if config.ReceiptImageRecognitionLLMConfig == nil {
		return nil
	}

	llmConfigs := make([]*settings.LLMConfig, 0, 1+len(config.ReceiptImageRecognitionLLMConfig.FallbackModels))

	if config.ReceiptImageRecognitionLLMConfig.LLMProvider != "" {
		llmConfigs = append(llmConfigs, config.ReceiptImageRecognitionLLMConfig)
	}

	llmConfigs = append(llmConfigs, config.ReceiptImageRecognitionLLMConfig.FallbackModels...)

	models := make([]*receiptImageRecognitionModelEntry, 0, len(llmConfigs))

	for i := 0; i < len(llmConfigs); i++ {
		llmConfig := llmConfigs[i]

		if llmConfig == nil || llmConfig.LLMProvider == "" {
			continue
		}

		llmProvider, err := initializeLargeLanguageModelProvider(llmConfig, config.EnableDebugLog)

		if err != nil {
			return err
		}

		if llmProvider == nil {
			continue
		}

		models = append(models, &receiptImageRecognitionModelEntry{
			config:   llmConfig,
			provider: llmProvider,
			label:    getLargeLanguageModelLabel(llmConfig),
		})
	}

	Container.receiptImageRecognitionModels = models

	if len(models) > 0 {
		Container.receiptImageRecognitionCurrentProvider = models[0].provider

		labels := make([]string, 0, len(models))

		for i := 0; i < len(models); i++ {
			labels = append(labels, models[i].label)
		}

		log.BootInfof(core.NewNullContext(), "[llm.InitializeLargeLanguageModelProvider] %d receipt image recognition model(s) loaded: %s", len(models), strings.Join(labels, ", "))
	} else {
		Container.receiptImageRecognitionCurrentProvider = nil
	}

	return nil
}

func initializeLargeLanguageModelProvider(llmConfig *settings.LLMConfig, enableResponseLog bool) (provider.LargeLanguageModelProvider, error) {
	if llmConfig.LLMProvider == settings.OpenAILLMProvider {
		return openai.NewOpenAILargeLanguageModelProvider(llmConfig, enableResponseLog), nil
	} else if llmConfig.LLMProvider == settings.OpenAICompatibleLLMProvider {
		return openai.NewOpenAICompatibleLargeLanguageModelProvider(llmConfig, enableResponseLog), nil
	} else if llmConfig.LLMProvider == settings.AnthropicLLMProvider {
		return anthropic.NewAnthropicLargeLanguageModelProvider(llmConfig, enableResponseLog), nil
	} else if llmConfig.LLMProvider == settings.AnthropicCompatibleLLMProvider {
		return anthropic.NewAnthropicCompatibleLargeLanguageModelProvider(llmConfig, enableResponseLog), nil
	} else if llmConfig.LLMProvider == settings.OpenRouterLLMProvider {
		return openai.NewOpenRouterLargeLanguageModelProvider(llmConfig, enableResponseLog), nil
	} else if llmConfig.LLMProvider == settings.OllamaLLMProvider {
		return ollama.NewOllamaLargeLanguageModelProvider(llmConfig, enableResponseLog), nil
	} else if llmConfig.LLMProvider == settings.LMStudioLLMProvider {
		return lmstudio.NewLMStudioLargeLanguageModelProvider(llmConfig, enableResponseLog), nil
	} else if llmConfig.LLMProvider == settings.GoogleAILLMProvider {
		return googleai.NewGoogleAILargeLanguageModelProvider(llmConfig, enableResponseLog), nil
	} else if llmConfig.LLMProvider == "" {
		return nil, nil
	}

	return nil, errs.ErrInvalidLLMProvider
}

// getLargeLanguageModelLabel returns a human readable model label which never contains any secret
func getLargeLanguageModelLabel(llmConfig *settings.LLMConfig) string {
	modelId := ""
	baseUrl := ""

	switch llmConfig.LLMProvider {
	case settings.OpenAILLMProvider:
		modelId = llmConfig.OpenAIModelID
	case settings.OpenAICompatibleLLMProvider:
		modelId = llmConfig.OpenAICompatibleModelID
		baseUrl = llmConfig.OpenAICompatibleBaseURL
	case settings.AnthropicLLMProvider:
		modelId = llmConfig.AnthropicModelID
	case settings.AnthropicCompatibleLLMProvider:
		modelId = llmConfig.AnthropicCompatibleModelID
		baseUrl = llmConfig.AnthropicCompatibleBaseURL
	case settings.OpenRouterLLMProvider:
		modelId = llmConfig.OpenRouterModelID
	case settings.OllamaLLMProvider:
		modelId = llmConfig.OllamaModelID
		baseUrl = llmConfig.OllamaServerURL
	case settings.LMStudioLLMProvider:
		modelId = llmConfig.LMStudioModelID
		baseUrl = llmConfig.LMStudioServerURL
	case settings.GoogleAILLMProvider:
		modelId = llmConfig.GoogleAIModelID
	}

	if baseUrl == "" {
		return llmConfig.LLMProvider + "/" + modelId
	}

	parsedUrl, err := url.Parse(baseUrl)

	if err != nil || parsedUrl.Host == "" {
		return llmConfig.LLMProvider + "/" + modelId
	}

	return llmConfig.LLMProvider + "/" + modelId + "@" + parsedUrl.Host
}

// GetJsonResponseByReceiptImageRecognitionModel returns the json response from one of the configured large language
// model providers by receipt image recognition model.
//
// When more than one model is configured, the models are tried in a rotating order until one of them returns a
// usable response, so that a single unavailable upstream model does not break the whole image recognition.
func (l *LargeLanguageModelProviderContainer) GetJsonResponseByReceiptImageRecognitionModel(c core.Context, uid int64, currentConfig *settings.Config, request *data.LargeLanguageModelRequest) (*data.LargeLanguageModelTextualResponse, error) {
	if currentConfig.ReceiptImageRecognitionLLMConfig == nil || len(l.receiptImageRecognitionModels) == 0 {
		return nil, errs.ErrInvalidLLMProvider
	}

	llmConfig := currentConfig.ReceiptImageRecognitionLLMConfig
	models := l.receiptImageRecognitionModels
	total := len(models)

	startIndex := 0

	if llmConfig.RotateModels && total > 1 {
		startIndex = int((l.receiptImageRecognitionRotation.Add(1) - 1) % uint64(total))
	}

	now := time.Now()
	minRemainingTime := time.Duration(llmConfig.LargeLanguageModelAPIRequestTimeoutPerModel) * time.Millisecond / 3

	if minRemainingTime < receiptImageRecognitionMinRemainingTime {
		minRemainingTime = receiptImageRecognitionMinRemainingTime
	}

	order := buildReceiptImageRecognitionAttemptOrder(models, startIndex, now)
	deadline := now.Add(time.Duration(llmConfig.LargeLanguageModelAPIRequestTimeout) * time.Millisecond)

	startTime := now
	attempts := 0
	var lastError error = nil

	for i := 0; i < len(order); i++ {
		if err := c.Err(); err != nil {
			log.Warnf(c, "[llm.GetJsonResponseByReceiptImageRecognitionModel] stop trying further models for user \"uid:%d\", because the request has been canceled", uid)
			break
		}

		if attempts > 0 && time.Until(deadline) < minRemainingTime {
			log.Warnf(c, "[llm.GetJsonResponseByReceiptImageRecognitionModel] stop trying further models for user \"uid:%d\", because only %s is left in the request budget", uid, time.Until(deadline).String())
			break
		}

		entry := order[i]
		attempts++
		attemptStartedAt := time.Now()

		response, err := entry.provider.GetJsonResponse(c, uid, entry.config, request)

		if err == nil && (response == nil || strings.TrimSpace(response.Content) == "") {
			err = errs.ErrFailedToRequestRemoteApi
		}

		if err == nil {
			entry.recordSuccess()
			log.Infof(c, "[llm.GetJsonResponseByReceiptImageRecognitionModel] attempt %d (model \"%s\") succeeded after %s for user \"uid:%d\", total elapsed %s",
				attempts, entry.label, time.Since(attemptStartedAt).String(), uid, time.Since(startTime).String())
			return response, nil
		}

		lastError = err
		cooldown := entry.recordFailure(time.Now())

		log.Warnf(c, "[llm.GetJsonResponseByReceiptImageRecognitionModel] attempt %d (model \"%s\") failed after %s for user \"uid:%d\", because %s",
			attempts, entry.label, time.Since(attemptStartedAt).String(), uid, err.Error())

		if cooldown > 0 {
			log.Warnf(c, "[llm.GetJsonResponseByReceiptImageRecognitionModel] model \"%s\" opened the circuit breaker for %s", entry.label, cooldown.String())
		}
	}

	if lastError == nil {
		lastError = errs.ErrFailedToRequestRemoteApi
	}

	log.Errorf(c, "[llm.GetJsonResponseByReceiptImageRecognitionModel] all %d attempt(s) with %d configured model(s) failed for user \"uid:%d\" after %s, last error: %s",
		attempts, total, uid, time.Since(startTime).String(), lastError.Error())

	return nil, lastError
}

// buildReceiptImageRecognitionAttemptOrder returns the models to try, in order.
//
// Models which recently failed are skipped, unless every model is in cooldown: in that case only the model whose
// cooldown expires first is tried, so that the feature never becomes permanently unavailable while a broken
// upstream can still not make every request wait for all models.
func buildReceiptImageRecognitionAttemptOrder(models []*receiptImageRecognitionModelEntry, startIndex int, now time.Time) []*receiptImageRecognitionModelEntry {
	total := len(models)
	order := make([]*receiptImageRecognitionModelEntry, 0, total)

	for i := 0; i < total; i++ {
		entry := models[(startIndex+i)%total]

		if !entry.isInCooldown(now) {
			order = append(order, entry)
		}
	}

	if len(order) > 0 {
		return order
	}

	var earliest *receiptImageRecognitionModelEntry = nil

	for i := 0; i < total; i++ {
		entry := models[i]

		if earliest == nil || entry.remainingCooldown(now) < earliest.remainingCooldown(now) {
			earliest = entry
		}
	}

	if earliest != nil {
		order = append(order, earliest)
	}

	return order
}
