package llm

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/llm/data"
	"github.com/mayswind/ezbookkeeping/pkg/settings"
)

type fakeLargeLanguageModelProvider struct {
	content string
	failing bool
	calls   int
}

func (p *fakeLargeLanguageModelProvider) GetJsonResponse(c core.Context, uid int64, currentLLMConfig *settings.LLMConfig, request *data.LargeLanguageModelRequest) (*data.LargeLanguageModelTextualResponse, error) {
	p.calls++

	if p.failing {
		return nil, errs.ErrFailedToRequestRemoteApi
	}

	return &data.LargeLanguageModelTextualResponse{
		Content: p.content,
	}, nil
}

func newTestContainer(rotateModels bool, providers ...*fakeLargeLanguageModelProvider) (*LargeLanguageModelProviderContainer, *settings.Config) {
	models := make([]*receiptImageRecognitionModelEntry, 0, len(providers))

	for i := 0; i < len(providers); i++ {
		models = append(models, &receiptImageRecognitionModelEntry{
			config:   &settings.LLMConfig{LLMProvider: settings.OpenAICompatibleLLMProvider},
			provider: providers[i],
			label:    "test-model-" + string(rune('1'+i)),
		})
	}

	llmConfig := &settings.LLMConfig{
		LLMProvider:                                 settings.OpenAICompatibleLLMProvider,
		RotateModels:                                rotateModels,
		LargeLanguageModelAPIRequestTimeout:         60000,
		LargeLanguageModelAPIRequestTimeoutPerModel: 30000,
	}

	container := &LargeLanguageModelProviderContainer{
		receiptImageRecognitionModels: models,
	}

	if len(models) > 0 {
		container.receiptImageRecognitionCurrentProvider = models[0].provider
	}

	return container, &settings.Config{ReceiptImageRecognitionLLMConfig: llmConfig}
}

func TestGetJsonResponseFallsBackToNextModel(t *testing.T) {
	first := &fakeLargeLanguageModelProvider{failing: true}
	second := &fakeLargeLanguageModelProvider{content: "{\"type\":\"expense\"}"}
	container, config := newTestContainer(false, first, second)

	response, err := container.GetJsonResponseByReceiptImageRecognitionModel(core.NewNullContext(), 1, config, &data.LargeLanguageModelRequest{})

	assert.Nil(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, "{\"type\":\"expense\"}", response.Content)
	assert.Equal(t, 1, first.calls)
	assert.Equal(t, 1, second.calls)
}

func TestGetJsonResponseReturnsErrorWhenAllModelsFail(t *testing.T) {
	first := &fakeLargeLanguageModelProvider{failing: true}
	second := &fakeLargeLanguageModelProvider{failing: true}
	container, config := newTestContainer(false, first, second)

	response, err := container.GetJsonResponseByReceiptImageRecognitionModel(core.NewNullContext(), 1, config, &data.LargeLanguageModelRequest{})

	assert.Nil(t, response)
	assert.ErrorIs(t, err, errs.ErrFailedToRequestRemoteApi)
	assert.Equal(t, 1, first.calls)
	assert.Equal(t, 1, second.calls)
}

func TestGetJsonResponseFailsOverOnEmptyContent(t *testing.T) {
	first := &fakeLargeLanguageModelProvider{content: "   "}
	second := &fakeLargeLanguageModelProvider{content: "{\"type\":\"income\"}"}
	container, config := newTestContainer(false, first, second)

	response, err := container.GetJsonResponseByReceiptImageRecognitionModel(core.NewNullContext(), 1, config, &data.LargeLanguageModelRequest{})

	assert.Nil(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, "{\"type\":\"income\"}", response.Content)
	assert.Equal(t, 1, second.calls)
}

func TestGetJsonResponseRotatesStartingModel(t *testing.T) {
	first := &fakeLargeLanguageModelProvider{content: "first"}
	second := &fakeLargeLanguageModelProvider{content: "second"}
	container, config := newTestContainer(true, first, second)

	response, err := container.GetJsonResponseByReceiptImageRecognitionModel(core.NewNullContext(), 1, config, &data.LargeLanguageModelRequest{})
	assert.Nil(t, err)
	assert.Equal(t, "first", response.Content)

	response, err = container.GetJsonResponseByReceiptImageRecognitionModel(core.NewNullContext(), 1, config, &data.LargeLanguageModelRequest{})
	assert.Nil(t, err)
	assert.Equal(t, "second", response.Content)
}

func TestGetJsonResponseWithoutRotationAlwaysStartsFromFirstModel(t *testing.T) {
	first := &fakeLargeLanguageModelProvider{content: "first"}
	second := &fakeLargeLanguageModelProvider{content: "second"}
	container, config := newTestContainer(false, first, second)

	for i := 0; i < 3; i++ {
		response, err := container.GetJsonResponseByReceiptImageRecognitionModel(core.NewNullContext(), 1, config, &data.LargeLanguageModelRequest{})
		assert.Nil(t, err)
		assert.Equal(t, "first", response.Content)
	}

	assert.Equal(t, 3, first.calls)
	assert.Equal(t, 0, second.calls)
}

func TestGetJsonResponseUsesSingleConfiguredModelOnly(t *testing.T) {
	only := &fakeLargeLanguageModelProvider{content: "{}"}
	container, config := newTestContainer(true, only)

	response, err := container.GetJsonResponseByReceiptImageRecognitionModel(core.NewNullContext(), 1, config, &data.LargeLanguageModelRequest{})

	assert.Nil(t, err)
	assert.Equal(t, "{}", response.Content)
	assert.Equal(t, 1, only.calls)
}

func TestGetJsonResponseReturnsErrorWhenNoModelConfigured(t *testing.T) {
	container := &LargeLanguageModelProviderContainer{}
	config := &settings.Config{ReceiptImageRecognitionLLMConfig: &settings.LLMConfig{LLMProvider: settings.OpenAICompatibleLLMProvider}}

	response, err := container.GetJsonResponseByReceiptImageRecognitionModel(core.NewNullContext(), 1, config, &data.LargeLanguageModelRequest{})

	assert.Nil(t, response)
	assert.ErrorIs(t, err, errs.ErrInvalidLLMProvider)
}

func TestRecordFailureOpensCircuitBreakerAfterTwoFailures(t *testing.T) {
	entry := &receiptImageRecognitionModelEntry{label: "test-model"}
	now := time.Now()

	assert.Equal(t, time.Duration(0), entry.recordFailure(now))
	assert.False(t, entry.isInCooldown(now))

	cooldown := entry.recordFailure(now)
	assert.Equal(t, receiptImageRecognitionModelCooldownDuration, cooldown)
	assert.True(t, entry.isInCooldown(now))
	assert.True(t, entry.isInCooldown(now.Add(receiptImageRecognitionModelCooldownDuration-time.Second)))
	assert.False(t, entry.isInCooldown(now.Add(receiptImageRecognitionModelCooldownDuration+time.Second)))

	entry.recordSuccess()
	assert.False(t, entry.isInCooldown(now))
}

func TestBuildAttemptOrderSkipsModelsInCooldown(t *testing.T) {
	now := time.Now()
	healthy := &receiptImageRecognitionModelEntry{label: "healthy"}
	unhealthy := &receiptImageRecognitionModelEntry{label: "unhealthy"}
	unhealthy.recordFailure(now)
	unhealthy.recordFailure(now)

	order := buildReceiptImageRecognitionAttemptOrder([]*receiptImageRecognitionModelEntry{unhealthy, healthy}, 0, now)

	assert.Len(t, order, 1)
	assert.Equal(t, "healthy", order[0].label)
}

func TestBuildAttemptOrderStillTriesEarliestModelWhenAllInCooldown(t *testing.T) {
	now := time.Now()
	first := &receiptImageRecognitionModelEntry{label: "first"}
	second := &receiptImageRecognitionModelEntry{label: "second"}

	first.recordFailure(now)
	first.recordFailure(now)

	second.recordFailure(now)
	second.recordFailure(now)

	// make "second" recover earlier
	second.cooldownUntilUnixMilli = now.Add(10 * time.Second).UnixMilli()

	order := buildReceiptImageRecognitionAttemptOrder([]*receiptImageRecognitionModelEntry{first, second}, 0, now)

	assert.Len(t, order, 1)
	assert.Equal(t, "second", order[0].label)
}
