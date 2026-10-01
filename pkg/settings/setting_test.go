package settings

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/mayswind/ezbookkeeping/pkg/errs"
)

func TestParseFallbackLLMModelsEmpty(t *testing.T) {
	primary := &LLMConfig{
		LLMProvider:             OpenAICompatibleLLMProvider,
		OpenAICompatibleBaseURL: "https://api.siliconflow.cn/v1",
		OpenAICompatibleModelID: "Qwen/Qwen3-VL-8B-Instruct",
	}

	fallbackModels, err := parseFallbackLLMModels("", primary)
	assert.Nil(t, err)
	assert.Empty(t, fallbackModels)

	fallbackModels, err = parseFallbackLLMModels("   ", primary)
	assert.Nil(t, err)
	assert.Empty(t, fallbackModels)
}

func TestParseFallbackLLMModelsInheritsPrimaryConfig(t *testing.T) {
	primary := &LLMConfig{
		LLMProvider:                         OpenAICompatibleLLMProvider,
		OpenAICompatibleBaseURL:             "https://api.siliconflow.cn/v1",
		OpenAICompatibleAPIKey:              "primary-key",
		OpenAICompatibleAPIKeyFile:          "/volume2/docker/key.txt",
		OpenAICompatibleModelID:             "Qwen/Qwen3-VL-8B-Instruct",
		LargeLanguageModelAPIRequestTimeout: 60000,
		LargeLanguageModelAPIProxy:          "system",
	}

	fallbackModels, err := parseFallbackLLMModels("model=Qwen/Qwen2.5-VL-32B-Instruct; model=Pro/Qwen2-VL-7B-Instruct ", primary)
	assert.Nil(t, err)
	assert.Len(t, fallbackModels, 2)

	assert.Equal(t, OpenAICompatibleLLMProvider, fallbackModels[0].LLMProvider)
	assert.Equal(t, "https://api.siliconflow.cn/v1", fallbackModels[0].OpenAICompatibleBaseURL)
	assert.Equal(t, "primary-key", fallbackModels[0].OpenAICompatibleAPIKey)
	assert.Equal(t, "Qwen/Qwen2.5-VL-32B-Instruct", fallbackModels[0].OpenAICompatibleModelID)
	assert.Equal(t, uint32(60000), fallbackModels[0].LargeLanguageModelAPIRequestTimeout)
	assert.Empty(t, fallbackModels[0].FallbackModels)

	assert.Equal(t, "Pro/Qwen2-VL-7B-Instruct", fallbackModels[1].OpenAICompatibleModelID)
}

func TestParseFallbackLLMModelsOverridesItems(t *testing.T) {
	primary := &LLMConfig{
		LLMProvider:             OpenAICompatibleLLMProvider,
		OpenAICompatibleBaseURL: "https://api.siliconflow.cn/v1",
		OpenAICompatibleAPIKey:  "primary-key",
		OpenAICompatibleModelID: "Qwen/Qwen3-VL-8B-Instruct",
	}

	fallbackModels, err := parseFallbackLLMModels("model=qwen-vl-max-latest,base_url=https://dashscope.aliyuncs.com/compatible-mode/v1,api_key=other-key", primary)
	assert.Nil(t, err)
	assert.Len(t, fallbackModels, 1)
	assert.Equal(t, "https://dashscope.aliyuncs.com/compatible-mode/v1", fallbackModels[0].OpenAICompatibleBaseURL)
	assert.Equal(t, "other-key", fallbackModels[0].OpenAICompatibleAPIKey)
	assert.Equal(t, "qwen-vl-max-latest", fallbackModels[0].OpenAICompatibleModelID)
}

func TestParseFallbackLLMModelsReadsAPIKeyFile(t *testing.T) {
	tempDir := t.TempDir()
	keyFilePath := filepath.Join(tempDir, "key.txt")

	err := os.WriteFile(keyFilePath, []byte("key-from-file\n"), 0600)
	assert.Nil(t, err)

	primary := &LLMConfig{
		LLMProvider:             OpenAICompatibleLLMProvider,
		OpenAICompatibleBaseURL: "https://api.siliconflow.cn/v1",
		OpenAICompatibleModelID: "Qwen/Qwen3-VL-8B-Instruct",
	}

	fallbackModels, err := parseFallbackLLMModels("model=second-model,api_key_file="+keyFilePath, primary)
	assert.Nil(t, err)
	assert.Len(t, fallbackModels, 1)
	assert.Equal(t, "key-from-file", fallbackModels[0].OpenAICompatibleAPIKey)
	assert.Equal(t, keyFilePath, fallbackModels[0].OpenAICompatibleAPIKeyFile)
}

func TestParseFallbackLLMModelsWithAnotherProvider(t *testing.T) {
	primary := &LLMConfig{
		LLMProvider:             OpenAICompatibleLLMProvider,
		OpenAICompatibleBaseURL: "https://api.siliconflow.cn/v1",
		OpenAICompatibleAPIKey:  "primary-key",
		OpenAICompatibleModelID: "Qwen/Qwen3-VL-8B-Instruct",
		AnthropicMaxTokens:      1024,
	}

	fallbackModels, err := parseFallbackLLMModels("provider=anthropic,model=claude-3-5-sonnet,max_tokens=2048,api_key=anthropic-key", primary)
	assert.Nil(t, err)
	assert.Len(t, fallbackModels, 1)
	assert.Equal(t, AnthropicLLMProvider, fallbackModels[0].LLMProvider)
	assert.Equal(t, "claude-3-5-sonnet", fallbackModels[0].AnthropicModelID)
	assert.Equal(t, uint32(2048), fallbackModels[0].AnthropicMaxTokens)
	assert.Equal(t, "anthropic-key", fallbackModels[0].AnthropicAPIKey)
}

func TestParseFallbackLLMModelsInvalid(t *testing.T) {
	primary := &LLMConfig{
		LLMProvider: OpenAICompatibleLLMProvider,
	}

	_, err := parseFallbackLLMModels("openai_compatible", primary)
	assert.ErrorIs(t, err, errs.ErrInvalidLLMFallbackModels)

	_, err = parseFallbackLLMModels("model=abc,unknown_item=1", primary)
	assert.ErrorIs(t, err, errs.ErrInvalidLLMFallbackModels)

	_, err = parseFallbackLLMModels("provider=invalid_provider,model=abc", primary)
	assert.Error(t, err)
}
