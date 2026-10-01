package llm

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/llm/data"
	"github.com/mayswind/ezbookkeeping/pkg/settings"
)

const fakeChatCompletionsResponse = `{"choices":[{"message":{"role":"assistant","content":"{\"type\":\"expense\",\"amount\":\"12.34\"}"}}]}`

func newFakeOpenAICompatibleServer(t *testing.T, handler func(w http.ResponseWriter, r *http.Request)) *httptest.Server {
	t.Helper()

	server := httptest.NewServer(http.HandlerFunc(handler))
	t.Cleanup(server.Close)

	return server
}

func newTestOpenAICompatibleConfig(baseUrl string, modelId string, timeout uint32) *settings.LLMConfig {
	return &settings.LLMConfig{
		LLMProvider:                         settings.OpenAICompatibleLLMProvider,
		OpenAICompatibleBaseURL:             baseUrl,
		OpenAICompatibleAPIKey:              "test-key",
		OpenAICompatibleModelID:             modelId,
		LargeLanguageModelAPIRequestTimeout: timeout,
		LargeLanguageModelAPIProxy:          "none",
	}
}

func newContainerFromConfigs(t *testing.T, llmConfigs ...*settings.LLMConfig) (*LargeLanguageModelProviderContainer, *settings.Config) {
	t.Helper()

	models := make([]*receiptImageRecognitionModelEntry, 0, len(llmConfigs))

	for i := 0; i < len(llmConfigs); i++ {
		llmProvider, err := initializeLargeLanguageModelProvider(llmConfigs[i], false)
		assert.Nil(t, err)

		models = append(models, &receiptImageRecognitionModelEntry{
			config:   llmConfigs[i],
			provider: llmProvider,
			label:    getLargeLanguageModelLabel(llmConfigs[i]),
		})
	}

	container := &LargeLanguageModelProviderContainer{
		receiptImageRecognitionModels: models,
	}

	return container, &settings.Config{ReceiptImageRecognitionLLMConfig: llmConfigs[0]}
}

func TestFailoverBetweenRealHTTPProviders(t *testing.T) {
	var brokenServerCalls int32

	brokenServer := newFakeOpenAICompatibleServer(t, func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&brokenServerCalls, 1)
		w.WriteHeader(http.StatusServiceUnavailable)
	})

	workingServer := newFakeOpenAICompatibleServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(fakeChatCompletionsResponse))
	})

	brokenConfig := newTestOpenAICompatibleConfig(brokenServer.URL+"/v1", "broken-model", 20000)
	workingConfig := newTestOpenAICompatibleConfig(workingServer.URL+"/v1", "working-model", 20000)

	container, config := newContainerFromConfigs(t, brokenConfig, workingConfig)
	config.ReceiptImageRecognitionLLMConfig.RotateModels = false
	config.ReceiptImageRecognitionLLMConfig.LargeLanguageModelAPIRequestTimeout = 60000
	config.ReceiptImageRecognitionLLMConfig.LargeLanguageModelAPIRequestTimeoutPerModel = 20000

	response, err := container.GetJsonResponseByReceiptImageRecognitionModel(core.NewNullContext(), 1, config, &data.LargeLanguageModelRequest{
		UserPrompt:            []byte("fake-image-data"),
		UserPromptType:        data.LARGE_LANGUAGE_MODEL_REQUEST_PROMPT_TYPE_IMAGE_URL,
		UserPromptContentType: "image/png",
	})

	assert.Nil(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, "{\"type\":\"expense\",\"amount\":\"12.34\"}", response.Content)
	assert.Equal(t, int32(1), atomic.LoadInt32(&brokenServerCalls))
}

func TestFailoverSkipsTimedOutProvider(t *testing.T) {
	var slowServerCalls int32

	// the slow model answers with a different payload, so the assertion below proves that the response really came
	// from the second model instead of merely relying on how long the call took
	slowServer := newFakeOpenAICompatibleServer(t, func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&slowServerCalls, 1)

		select {
		case <-time.After(2 * time.Second):
		case <-r.Context().Done():
			return
		}

		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"slow"}}]}`))
	})

	fastServer := newFakeOpenAICompatibleServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"fast"}}]}`))
	})

	slowConfig := newTestOpenAICompatibleConfig(slowServer.URL+"/v1", "slow-model", 200)
	fastConfig := newTestOpenAICompatibleConfig(fastServer.URL+"/v1", "fast-model", 20000)

	container, config := newContainerFromConfigs(t, slowConfig, fastConfig)
	config.ReceiptImageRecognitionLLMConfig.RotateModels = false
	config.ReceiptImageRecognitionLLMConfig.LargeLanguageModelAPIRequestTimeout = 60000
	config.ReceiptImageRecognitionLLMConfig.LargeLanguageModelAPIRequestTimeoutPerModel = 20000

	response, err := container.GetJsonResponseByReceiptImageRecognitionModel(core.NewNullContext(), 1, config, &data.LargeLanguageModelRequest{})

	assert.Nil(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, "fast", response.Content)
	assert.Equal(t, int32(1), atomic.LoadInt32(&slowServerCalls))
}

func TestFailoverKeepsSingleModelBehaviorWhenNoFallbackConfigured(t *testing.T) {
	var receivedModel string

	server := newFakeOpenAICompatibleServer(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		requestBody := make(map[string]any)

		if json.Unmarshal(body, &requestBody) == nil {
			if model, ok := requestBody["model"].(string); ok {
				receivedModel = model
			}
		}

		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(fakeChatCompletionsResponse))
	})

	llmConfig := newTestOpenAICompatibleConfig(server.URL+"/v1", "only-model", 20000)
	container, config := newContainerFromConfigs(t, llmConfig)
	config.ReceiptImageRecognitionLLMConfig.RotateModels = true
	config.ReceiptImageRecognitionLLMConfig.LargeLanguageModelAPIRequestTimeout = 60000
	config.ReceiptImageRecognitionLLMConfig.LargeLanguageModelAPIRequestTimeoutPerModel = 20000

	response, err := container.GetJsonResponseByReceiptImageRecognitionModel(core.NewNullContext(), 1, config, &data.LargeLanguageModelRequest{})

	assert.Nil(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, "only-model", receivedModel)
}
