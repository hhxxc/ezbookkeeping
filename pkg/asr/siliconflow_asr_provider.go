package asr

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"time"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/log"
)

const siliconFlowASREndpoint = "https://api.siliconflow.cn/v1/audio/transcriptions"

// SiliconFlowASRProvider represents the SiliconFlow automatic speech recognition provider,
// it directly calls the SiliconFlow audio transcription API (SenseVoiceSmall),
// and does NOT go through the LLM provider system (ASR and chat LLM are two different services)
type SiliconFlowASRProvider struct {
	apiKey     string
	modelId    string
	httpClient *http.Client
}

// TranscriptionResponse represents the response of SiliconFlow audio transcription api
type TranscriptionResponse struct {
	Text string `json:"text"`
}

// Create a SiliconFlow automatic speech recognition provider instance
func NewSiliconFlowASRProvider(apiKey string, modelId string, requestTimeout time.Duration) *SiliconFlowASRProvider {
	return &SiliconFlowASRProvider{
		apiKey:  apiKey,
		modelId: modelId,
		httpClient: &http.Client{
			Timeout: requestTimeout,
		},
	}
}

// Transcribe converts the given audio data into text via SiliconFlow audio transcription api
func (p *SiliconFlowASRProvider) Transcribe(c *core.WebContext, audioData []byte, contentType string) (string, error) {
	bodyBuffer := &bytes.Buffer{}
	writer := multipart.NewWriter(bodyBuffer)

	fileWriter, err := writer.CreateFormFile("file", "audio")

	if err != nil {
		return "", errs.ErrOperationFailed
	}

	if _, err = fileWriter.Write(audioData); err != nil {
		return "", errs.ErrOperationFailed
	}

	if err = writer.WriteField("model", p.modelId); err != nil {
		return "", errs.ErrOperationFailed
	}

	if err = writer.Close(); err != nil {
		return "", errs.ErrOperationFailed
	}

	request, err := http.NewRequest(http.MethodPost, siliconFlowASREndpoint, bodyBuffer)

	if err != nil {
		return "", errs.ErrOperationFailed
	}

	request.Header.Set("Content-Type", writer.FormDataContentType())
	request.Header.Set("Authorization", "Bearer "+p.apiKey)

	log.Debugf(c, "[asr.SiliconFlowASRProvider.Transcribe] sending audio (%d bytes, %s) to speech recognition api", len(audioData), contentType)

	response, err := p.httpClient.Do(request)

	if err != nil {
		log.Errorf(c, "[asr.SiliconFlowASRProvider.Transcribe] failed to request speech recognition api, because %s", err.Error())
		return "", errs.ErrASRRequestFailed
	}

	defer response.Body.Close()

	responseBody, err := io.ReadAll(response.Body)

	if err != nil {
		log.Errorf(c, "[asr.SiliconFlowASRProvider.Transcribe] failed to read speech recognition api response, because %s", err.Error())
		return "", errs.ErrASRRequestFailed
	}

	if response.StatusCode != http.StatusOK {
		log.Errorf(c, "[asr.SiliconFlowASRProvider.Transcribe] speech recognition api returned status \"%d\": %s", response.StatusCode, string(responseBody))
		return "", errs.ErrASRRequestFailed
	}

	var transcriptionResponse TranscriptionResponse

	if err = json.Unmarshal(responseBody, &transcriptionResponse); err != nil {
		log.Errorf(c, "[asr.SiliconFlowASRProvider.Transcribe] failed to unmarshal speech recognition api response \"%s\", because %s", string(responseBody), err.Error())
		return "", errs.ErrASRRequestFailed
	}

	if transcriptionResponse.Text == "" {
		log.Errorf(c, "[asr.SiliconFlowASRProvider.Transcribe] speech recognition api returned empty text")
		return "", errs.ErrNoTransactionText
	}

	log.Debugf(c, "[asr.SiliconFlowASRProvider.Transcribe] transcribed text: %s", fmt.Sprintf("%.100s", transcriptionResponse.Text))

	return transcriptionResponse.Text, nil
}
