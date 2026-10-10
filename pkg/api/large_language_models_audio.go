package api

import (
	"io"
	"strings"
	"time"

	"github.com/mayswind/ezbookkeeping/pkg/asr"
	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/llm"
	"github.com/mayswind/ezbookkeeping/pkg/llm/data"
	"github.com/mayswind/ezbookkeeping/pkg/log"
	"github.com/mayswind/ezbookkeeping/pkg/settings"
	"github.com/mayswind/ezbookkeeping/pkg/templates"
)

const maxTransactionParseAudioFileSize = 2 * 1024 * 1024 // 2MB

// ParseTransactionAudioHandler returns the parsed transaction results from user voice input,
// it first transcribes the uploaded audio via the ASR provider, then reuses the same
// prompt template and parse chain as ParseTransactionTextHandler
func (a *LargeLanguageModelsApi) ParseTransactionAudioHandler(c *core.WebContext) (any, *errs.Error) {
	config := a.CurrentConfig()

	if config.ReceiptImageRecognitionLLMConfig == nil || config.ReceiptImageRecognitionLLMConfig.LLMProvider == "" || !config.TransactionFromAIImageRecognition {
		return nil, errs.ErrLargeLanguageModelProviderNotEnabled
	}

	if !config.TransactionFromVoiceInput || !config.IsASRReady() {
		return nil, errs.ErrASRProviderNotEnabled
	}

	clientTimezone, err := c.GetClientTimezone()

	if err != nil {
		log.Warnf(c, "[large_language_models.ParseTransactionAudioHandler] cannot get client timezone, because %s", err.Error())
		return nil, errs.ErrClientTimezoneOffsetInvalid
	}

	uid := c.GetCurrentUid()
	user, err := a.users.GetUserById(c, uid)

	if err != nil {
		if !errs.IsCustomError(err) {
			log.Warnf(c, "[large_language_models.ParseTransactionAudioHandler] failed to get user for user \"uid:%d\", because %s", uid, err.Error())
		}

		return false, errs.ErrUserNotFound
	}

	if user.FeatureRestriction.Contains(core.USER_FEATURE_RESTRICTION_TYPE_CREATE_TRANSACTION_FROM_AI_IMAGE_RECOGNITION) {
		return false, errs.ErrNotPermittedToPerformThisAction
	}

	form, err := c.MultipartForm()

	if err != nil {
		log.Errorf(c, "[large_language_models.ParseTransactionAudioHandler] failed to get multi-part form data for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.ErrParameterInvalid
	}

	audioFiles := form.File["audio"]

	if len(audioFiles) < 1 {
		log.Warnf(c, "[large_language_models.ParseTransactionAudioHandler] there is no audio in request for user \"uid:%d\"", uid)
		return nil, errs.ErrNoTransactionAudio
	}

	if audioFiles[0].Size < 1 {
		log.Warnf(c, "[large_language_models.ParseTransactionAudioHandler] the size of audio in request is zero for user \"uid:%d\"", uid)
		return nil, errs.ErrTransactionAudioIsEmpty
	}

	if audioFiles[0].Size > maxTransactionParseAudioFileSize {
		log.Warnf(c, "[large_language_models.ParseTransactionAudioHandler] the upload file size \"%d\" exceeds the maximum size \"%d\" of audio for user \"uid:%d\"", audioFiles[0].Size, maxTransactionParseAudioFileSize, uid)
		return nil, errs.ErrExceedMaxTransactionAudioFileSize
	}

	contentType := audioFiles[0].Header.Get("Content-Type")

	if !isSupportedTransactionAudioContentType(contentType) {
		log.Warnf(c, "[large_language_models.ParseTransactionAudioHandler] the content type \"%s\" of audio in request is not supported for user \"uid:%d\"", contentType, uid)
		return nil, errs.ErrAudioTypeNotSupported
	}

	audioFile, err := audioFiles[0].Open()

	if err != nil {
		log.Errorf(c, "[large_language_models.ParseTransactionAudioHandler] failed to get audio file from request for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.ErrOperationFailed
	}

	defer audioFile.Close()

	audioData, err := io.ReadAll(audioFile)

	if err != nil {
		log.Errorf(c, "[large_language_models.ParseTransactionAudioHandler] failed to read audio file from request for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.ErrOperationFailed
	}

	// Step 1: transcribe audio to text via ASR provider
	text, transcribeErr := a.transcribeAudio(c, config, audioData, contentType)

	if transcribeErr != nil {
		return nil, transcribeErr
	}

	// Step 2: reuse the same parse chain as text parsing
	context, parseContextErr := a.getTransactionParseContext(c, uid)

	if parseContextErr != nil {
		return nil, parseContextErr
	}

	systemPrompt, promptErr := a.renderTransactionParseSystemPrompt(c, uid, clientTimezone, templates.SYSTEM_PROMPT_TRANSACTION_TEXT_PARSE, context)

	if promptErr != nil {
		return nil, promptErr
	}

	llmRequest := &data.LargeLanguageModelRequest{
		Stream:         false,
		SystemPrompt:   systemPrompt,
		UserPrompt:     []byte(text),
		UserPromptType: data.LARGE_LANGUAGE_MODEL_REQUEST_PROMPT_TYPE_TEXT,
	}

	llmResponse, err := llm.Container.GetJsonResponseByReceiptImageRecognitionModel(c, c.GetCurrentUid(), config, llmRequest)

	if err != nil {
		log.Errorf(c, "[large_language_models.ParseTransactionAudioHandler] failed to get llm response user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	if llmResponse == nil || len(llmResponse.Content) == 0 || strings.HasPrefix(llmResponse.Content, "{}") {
		return nil, errs.ErrNoTransactionInformationInImage
	}

	return a.parseRecognizedTransactionsContent(c, uid, clientTimezone, llmResponse.Content, context)
}

// transcribeAudio calls the configured ASR provider to convert audio data into text
func (a *LargeLanguageModelsApi) transcribeAudio(c *core.WebContext, config *settings.Config, audioData []byte, contentType string) (string, *errs.Error) {
	requestTimeout := time.Duration(config.ASRConfig.RequestTimeout) * time.Millisecond

	if requestTimeout <= 0 {
		requestTimeout = 30 * time.Second
	}

	var provider asr.ASRProvider

	switch config.ASRConfig.ASRProvider {
	case settings.SiliconFlowASRProvider:
		provider = asr.NewSiliconFlowASRProvider(config.ASRConfig.SiliconFlowAPIKey, config.ASRConfig.ModelID, requestTimeout)
	default:
		return "", errs.ErrASRProviderNotEnabled
	}

	text, err := provider.Transcribe(c, audioData, contentType)

	if err != nil {
		log.Errorf(c, "[large_language_models.transcribeAudio] failed to transcribe audio for user \"uid:%d\", because %s", c.GetCurrentUid(), err.Error())
		return "", errs.Or(err, errs.ErrASRRequestFailed)
	}

	return text, nil
}

// isSupportedTransactionAudioContentType returns whether the given content type is
// a supported audio type (audio/mp4 for iOS Safari, audio/webm for others, etc.)
func isSupportedTransactionAudioContentType(contentType string) bool {
	normalizedContentType := strings.ToLower(strings.TrimSpace(contentType))
	normalizedContentType = strings.TrimSpace(strings.Split(normalizedContentType, ";")[0])

	switch normalizedContentType {
	case "audio/mp4", "audio/aac", "audio/m4a", "audio/x-m4a",
		"audio/webm", "audio/ogg", "audio/wav", "audio/x-wav", "audio/wave",
		"audio/mpeg", "audio/mp3", "application/ogg", "video/mp4":
		return true
	default:
		return strings.HasPrefix(normalizedContentType, "audio/")
	}
}
