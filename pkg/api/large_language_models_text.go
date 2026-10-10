package api

import (
	"strings"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/llm"
	"github.com/mayswind/ezbookkeeping/pkg/llm/data"
	"github.com/mayswind/ezbookkeeping/pkg/log"
	"github.com/mayswind/ezbookkeeping/pkg/templates"
)

const maxTransactionParseTextLength = 1000

// ParseTransactionTextRequest represents the request of parsing transactions from text
type ParseTransactionTextRequest struct {
	Text string `json:"text"`
}

// ParseTransactionTextHandler returns the parsed transaction results from user text
func (a *LargeLanguageModelsApi) ParseTransactionTextHandler(c *core.WebContext) (any, *errs.Error) {
	if a.CurrentConfig().ReceiptImageRecognitionLLMConfig == nil || a.CurrentConfig().ReceiptImageRecognitionLLMConfig.LLMProvider == "" || !a.CurrentConfig().TransactionFromAIImageRecognition {
		return nil, errs.ErrLargeLanguageModelProviderNotEnabled
	}

	clientTimezone, err := c.GetClientTimezone()

	if err != nil {
		log.Warnf(c, "[large_language_models.ParseTransactionTextHandler] cannot get client timezone, because %s", err.Error())
		return nil, errs.ErrClientTimezoneOffsetInvalid
	}

	uid := c.GetCurrentUid()
	user, err := a.users.GetUserById(c, uid)

	if err != nil {
		if !errs.IsCustomError(err) {
			log.Warnf(c, "[large_language_models.ParseTransactionTextHandler] failed to get user for user \"uid:%d\", because %s", uid, err.Error())
		}

		return false, errs.ErrUserNotFound
	}

	if user.FeatureRestriction.Contains(core.USER_FEATURE_RESTRICTION_TYPE_CREATE_TRANSACTION_FROM_AI_IMAGE_RECOGNITION) {
		return false, errs.ErrNotPermittedToPerformThisAction
	}

	var req ParseTransactionTextRequest
	err = c.ShouldBindJSON(&req)

	if err != nil {
		log.Errorf(c, "[large_language_models.ParseTransactionTextHandler] failed to bind request body for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.ErrParameterInvalid
	}

	text := strings.TrimSpace(req.Text)

	if len(text) < 1 {
		log.Warnf(c, "[large_language_models.ParseTransactionTextHandler] there is no text in request for user \"uid:%d\"", uid)
		return nil, errs.ErrNoTransactionText
	}

	if len([]rune(text)) > maxTransactionParseTextLength {
		log.Warnf(c, "[large_language_models.ParseTransactionTextHandler] the text length exceeds the maximum \"%d\" for user \"uid:%d\"", maxTransactionParseTextLength, uid)
		return nil, errs.ErrTransactionTextTooLong
	}

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

	llmResponse, err := llm.Container.GetJsonResponseByReceiptImageRecognitionModel(c, c.GetCurrentUid(), a.CurrentConfig(), llmRequest)

	if err != nil {
		log.Errorf(c, "[large_language_models.ParseTransactionTextHandler] failed to get llm response user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	if llmResponse == nil || len(llmResponse.Content) == 0 || strings.HasPrefix(llmResponse.Content, "{}") {
		return nil, errs.ErrNoTransactionInformationInImage
	}

	return a.parseRecognizedTransactionsContent(c, uid, clientTimezone, llmResponse.Content, context)
}
