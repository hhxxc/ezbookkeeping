package api

import (
	"bytes"
	"encoding/json"
	"io"
	"strings"
	"time"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/llm"
	"github.com/mayswind/ezbookkeeping/pkg/llm/data"
	"github.com/mayswind/ezbookkeeping/pkg/log"
	"github.com/mayswind/ezbookkeeping/pkg/models"
	"github.com/mayswind/ezbookkeeping/pkg/services"
	"github.com/mayswind/ezbookkeeping/pkg/settings"
	"github.com/mayswind/ezbookkeeping/pkg/templates"
	"github.com/mayswind/ezbookkeeping/pkg/utils"
)

// LargeLanguageModelsApi represents large language models api
type LargeLanguageModelsApi struct {
	ApiUsingConfig
	transactionCategories *services.TransactionCategoryService
	transactionTags       *services.TransactionTagService
	accounts              *services.AccountService
	users                 *services.UserService
}

// Initialize a large language models api singleton instance
var (
	LargeLanguageModels = &LargeLanguageModelsApi{
		ApiUsingConfig: ApiUsingConfig{
			container: settings.Container,
		},
		transactionCategories: services.TransactionCategories,
		transactionTags:       services.TransactionTags,
		accounts:              services.Accounts,
		users:                 services.Users,
	}
)

// transactionParseContext contains the user's accounts, categories and tags for parsing transactions from llm responses
type transactionParseContext struct {
	accountMap            map[string]*models.Account
	expenseCategoryMap    map[string]*models.TransactionCategory
	incomeCategoryMap     map[string]*models.TransactionCategory
	transferCategoryMap   map[string]*models.TransactionCategory
	tagMap                map[string]*models.TransactionTag
	expenseCategoryNames  []string
	incomeCategoryNames   []string
	transferCategoryNames []string
	accountNames          []string
	tagNames              []string
}

func (a *LargeLanguageModelsApi) getTransactionParseContext(c *core.WebContext, uid int64) (*transactionParseContext, *errs.Error) {
	accounts, err := a.accounts.GetAllAccountsByUid(c, uid)

	if err != nil {
		log.Errorf(c, "[large_language_models.getTransactionParseContext] failed to get all accounts for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	context := &transactionParseContext{
		accountMap: a.accounts.GetVisibleAccountNameMapByList(accounts),
	}

	for i := 0; i < len(accounts); i++ {
		if accounts[i].Hidden || accounts[i].Type == models.ACCOUNT_TYPE_MULTI_SUB_ACCOUNTS {
			continue
		}

		context.accountNames = append(context.accountNames, accounts[i].Name)
	}

	categories, err := a.transactionCategories.GetAllCategoriesByUid(c, uid, 0, -1)

	if err != nil {
		log.Errorf(c, "[large_language_models.getTransactionParseContext] failed to get categories for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	context.expenseCategoryMap = make(map[string]*models.TransactionCategory)
	context.incomeCategoryMap = make(map[string]*models.TransactionCategory)
	context.transferCategoryMap = make(map[string]*models.TransactionCategory)

	for i := 0; i < len(categories); i++ {
		category := categories[i]

		if category.Hidden || category.ParentCategoryId == models.LevelOneTransactionCategoryParentId {
			continue
		}

		if category.Type == models.CATEGORY_TYPE_INCOME {
			context.incomeCategoryMap[category.Name] = category
			context.incomeCategoryNames = append(context.incomeCategoryNames, category.Name)
		} else if category.Type == models.CATEGORY_TYPE_EXPENSE {
			context.expenseCategoryMap[category.Name] = category
			context.expenseCategoryNames = append(context.expenseCategoryNames, category.Name)
		} else if category.Type == models.CATEGORY_TYPE_TRANSFER {
			context.transferCategoryMap[category.Name] = category
			context.transferCategoryNames = append(context.transferCategoryNames, category.Name)
		}
	}

	tags, err := a.transactionTags.GetAllTagsByUid(c, uid)

	if err != nil {
		log.Errorf(c, "[large_language_models.getTransactionParseContext] failed to get tags for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	context.tagMap = a.transactionTags.GetVisibleTagNameMapByList(tags)

	for i := 0; i < len(tags); i++ {
		if tags[i].Hidden {
			continue
		}

		context.tagNames = append(context.tagNames, tags[i].Name)
	}

	return context, nil
}

func (a *LargeLanguageModelsApi) renderTransactionParseSystemPrompt(c *core.WebContext, uid int64, clientTimezone *time.Location, templateName templates.KnownTemplate, context *transactionParseContext) (string, *errs.Error) {
	systemPrompt, err := templates.GetTemplate(templateName)

	if err != nil {
		log.Errorf(c, "[large_language_models.renderTransactionParseSystemPrompt] failed to get system prompt template for user \"uid:%d\", because %s", uid, err.Error())
		return "", errs.Or(err, errs.ErrOperationFailed)
	}

	systemPromptParams := map[string]any{
		"CurrentDateTime":          utils.FormatUnixTimeToLongDateTime(time.Now().Unix(), clientTimezone),
		"AllExpenseCategoryNames":  strings.Join(context.expenseCategoryNames, "\n"),
		"AllIncomeCategoryNames":   strings.Join(context.incomeCategoryNames, "\n"),
		"AllTransferCategoryNames": strings.Join(context.transferCategoryNames, "\n"),
		"AllAccountNames":          strings.Join(context.accountNames, "\n"),
		"AllTagNames":              strings.Join(context.tagNames, "\n"),
	}

	var bodyBuffer bytes.Buffer
	err = systemPrompt.Execute(&bodyBuffer, systemPromptParams)

	if err != nil {
		log.Errorf(c, "[large_language_models.renderTransactionParseSystemPrompt] failed to get final system prompt from template for user \"uid:%d\", because %s", uid, err.Error())
		return "", errs.Or(err, errs.ErrOperationFailed)
	}

	return strings.ReplaceAll(bodyBuffer.String(), "\r\n", "\n"), nil
}

// parseRecognizedTransactionsContent parses the llm response content into recognized transaction responses
func (a *LargeLanguageModelsApi) parseRecognizedTransactionsContent(c *core.WebContext, uid int64, clientTimezone *time.Location, content string, context *transactionParseContext) ([]*models.RecognizedReceiptImageResponse, *errs.Error) {
	trimmedContent := strings.TrimSpace(content)

	// Try parsing as array first (new format)
	if strings.HasPrefix(trimmedContent, "[") {
		var results []*models.RecognizedReceiptImageResult

		if err := json.Unmarshal([]byte(trimmedContent), &results); err != nil {
			log.Errorf(c, "[large_language_models.parseRecognizedTransactionsContent] failed to unmarshal recognized results array from llm response \"%s\" for user \"uid:%d\", because %s", content, uid, err.Error())
			return nil, errs.Or(err, errs.ErrOperationFailed)
		}

		if len(results) == 0 {
			return nil, errs.ErrNoTransactionInformationInImage
		}

		responses := make([]*models.RecognizedReceiptImageResponse, 0, len(results))

		for _, result := range results {
			response, parseErr := a.parseRecognizedReceiptImageResponse(c, uid, clientTimezone, result, context.accountMap, context.expenseCategoryMap, context.incomeCategoryMap, context.transferCategoryMap, context.tagMap)

			if parseErr != nil {
				log.Warnf(c, "[large_language_models.parseRecognizedTransactionsContent] failed to parse one of the recognized results for user \"uid:%d\", skipping: %s", uid, parseErr.Error())
				continue
			}

			responses = append(responses, response)
		}

		if len(responses) == 0 {
			return nil, errs.ErrNoTransactionInformationInImage
		}

		return responses, nil
	}

	// Fallback: parse as single object (backward compatibility)
	var result *models.RecognizedReceiptImageResult

	if err := json.Unmarshal([]byte(trimmedContent), &result); err != nil {
		log.Errorf(c, "[large_language_models.parseRecognizedTransactionsContent] failed to unmarshal recognized result from llm response \"%s\" for user \"uid:%d\", because %s", content, uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	response, parseErr := a.parseRecognizedReceiptImageResponse(c, uid, clientTimezone, result, context.accountMap, context.expenseCategoryMap, context.incomeCategoryMap, context.transferCategoryMap, context.tagMap)

	if parseErr != nil {
		return nil, parseErr
	}

	return []*models.RecognizedReceiptImageResponse{response}, nil
}

// RecognizeReceiptImageHandler returns the recognized receipt image result
func (a *LargeLanguageModelsApi) RecognizeReceiptImageHandler(c *core.WebContext) (any, *errs.Error) {
	if a.CurrentConfig().ReceiptImageRecognitionLLMConfig == nil || a.CurrentConfig().ReceiptImageRecognitionLLMConfig.LLMProvider == "" || !a.CurrentConfig().TransactionFromAIImageRecognition {
		return nil, errs.ErrLargeLanguageModelProviderNotEnabled
	}

	clientTimezone, err := c.GetClientTimezone()

	if err != nil {
		log.Warnf(c, "[large_language_models.RecognizeReceiptImageHandler] cannot get client timezone, because %s", err.Error())
		return nil, errs.ErrClientTimezoneOffsetInvalid
	}

	uid := c.GetCurrentUid()
	user, err := a.users.GetUserById(c, uid)

	if err != nil {
		if !errs.IsCustomError(err) {
			log.Warnf(c, "[large_language_models.RecognizeReceiptImageHandler] failed to get user for user \"uid:%d\", because %s", uid, err.Error())
		}

		return false, errs.ErrUserNotFound
	}

	if user.FeatureRestriction.Contains(core.USER_FEATURE_RESTRICTION_TYPE_CREATE_TRANSACTION_FROM_AI_IMAGE_RECOGNITION) {
		return false, errs.ErrNotPermittedToPerformThisAction
	}

	form, err := c.MultipartForm()

	if err != nil {
		log.Errorf(c, "[large_language_models.RecognizeReceiptImageHandler] failed to get multi-part form data for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.ErrParameterInvalid
	}

	imageFiles := form.File["image"]

	if len(imageFiles) < 1 {
		log.Warnf(c, "[large_language_models.RecognizeReceiptImageHandler] there is no image in request for user \"uid:%d\"", uid)
		return nil, errs.ErrNoAIRecognitionImage
	}

	if imageFiles[0].Size < 1 {
		log.Warnf(c, "[large_language_models.RecognizeReceiptImageHandler] the size of image in request is zero for user \"uid:%d\"", uid)
		return nil, errs.ErrAIRecognitionImageIsEmpty
	}

	if imageFiles[0].Size > int64(a.CurrentConfig().MaxAIRecognitionPictureFileSize) {
		log.Warnf(c, "[large_language_models.RecognizeReceiptImageHandler] the upload file size \"%d\" exceeds the maximum size \"%d\" of image for user \"uid:%d\"", imageFiles[0].Size, a.CurrentConfig().MaxAIRecognitionPictureFileSize, uid)
		return nil, errs.ErrExceedMaxAIRecognitionImageFileSize
	}

	fileExtension := utils.GetFileNameExtension(imageFiles[0].Filename)
	contentType := utils.GetImageContentType(fileExtension)

	if contentType == "" {
		log.Warnf(c, "[large_language_models.RecognizeReceiptImageHandler] the file extension \"%s\" of image in request is not supported for user \"uid:%d\"", fileExtension, uid)
		return nil, errs.ErrImageTypeNotSupported
	}

	imageFile, err := imageFiles[0].Open()

	if err != nil {
		log.Errorf(c, "[large_language_models.RecognizeReceiptImageHandler] failed to get image file from request for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.ErrOperationFailed
	}

	defer imageFile.Close()

	imageData, err := io.ReadAll(imageFile)

	if err != nil {
		log.Errorf(c, "[large_language_models.RecognizeReceiptImageHandler] failed to read image file from request for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.ErrOperationFailed
	}

	context, parseContextErr := a.getTransactionParseContext(c, uid)

	if parseContextErr != nil {
		return nil, parseContextErr
	}

	systemPrompt, promptErr := a.renderTransactionParseSystemPrompt(c, uid, clientTimezone, templates.SYSTEM_PROMPT_RECEIPT_IMAGE_RECOGNITION, context)

	if promptErr != nil {
		return nil, promptErr
	}

	llmRequest := &data.LargeLanguageModelRequest{
		Stream:                false,
		SystemPrompt:          systemPrompt,
		UserPrompt:            imageData,
		UserPromptType:        data.LARGE_LANGUAGE_MODEL_REQUEST_PROMPT_TYPE_IMAGE_URL,
		UserPromptContentType: contentType,
	}

	llmResponse, err := llm.Container.GetJsonResponseByReceiptImageRecognitionModel(c, c.GetCurrentUid(), a.CurrentConfig(), llmRequest)

	if err != nil {
		log.Errorf(c, "[large_language_models.RecognizeReceiptImageHandler] failed to get llm response user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	if llmResponse == nil || len(llmResponse.Content) == 0 || strings.HasPrefix(llmResponse.Content, "{}") {
		return nil, errs.ErrNoTransactionInformationInImage
	}

	return a.parseRecognizedTransactionsContent(c, uid, clientTimezone, llmResponse.Content, context)
}

func (a *LargeLanguageModelsApi) parseRecognizedReceiptImageResponse(c *core.WebContext, uid int64, clientTimezone *time.Location, recognizedResult *models.RecognizedReceiptImageResult, accountMap map[string]*models.Account, expenseCategoryMap map[string]*models.TransactionCategory, incomeCategoryMap map[string]*models.TransactionCategory, transferCategoryMap map[string]*models.TransactionCategory, tagMap map[string]*models.TransactionTag) (*models.RecognizedReceiptImageResponse, *errs.Error) {
	recognizedReceiptImageResponse := &models.RecognizedReceiptImageResponse{
		Type: models.TRANSACTION_TYPE_EXPENSE,
	}

	if recognizedResult == nil {
		log.Errorf(c, "[large_language_models.parseRecognizedReceiptImageResponse] recoginzed result is null")
		return nil, errs.ErrNoTransactionInformationInImage
	}

	if recognizedResult.Type == "income" {
		recognizedReceiptImageResponse.Type = models.TRANSACTION_TYPE_INCOME

		if len(recognizedResult.CategoryName) > 0 {
			category, exists := incomeCategoryMap[recognizedResult.CategoryName]

			if exists {
				recognizedReceiptImageResponse.CategoryId = category.CategoryId
			}
		}
	} else if recognizedResult.Type == "expense" {
		recognizedReceiptImageResponse.Type = models.TRANSACTION_TYPE_EXPENSE

		if len(recognizedResult.CategoryName) > 0 {
			category, exists := expenseCategoryMap[recognizedResult.CategoryName]

			if exists {
				recognizedReceiptImageResponse.CategoryId = category.CategoryId
			}
		}
	} else if recognizedResult.Type == "transfer" {
		recognizedReceiptImageResponse.Type = models.TRANSACTION_TYPE_TRANSFER

		if len(recognizedResult.CategoryName) > 0 {
			category, exists := transferCategoryMap[recognizedResult.CategoryName]

			if exists {
				recognizedReceiptImageResponse.CategoryId = category.CategoryId
			}
		}
	} else if len(recognizedResult.Type) == 0 {
		return nil, errs.ErrNoTransactionInformationInImage
	} else {
		log.Errorf(c, "[large_language_models.parseRecognizedReceiptImageResponse] recoginzed transaction type \"%s\" is invalid", recognizedResult.Type)
		return nil, errs.ErrOperationFailed
	}

	if len(recognizedResult.Time) > 0 {
		longDateTime := a.getLongDateTime(recognizedResult.Time)
		timestamp, err := utils.ParseFromLongDateTimeInTimeZone(longDateTime, clientTimezone)

		if err != nil {
			log.Warnf(c, "[large_language_models.parseRecognizedReceiptImageResponse] recoginzed time \"%s\" is invalid", recognizedResult.Time)
		} else {
			recognizedReceiptImageResponse.Time = timestamp.Unix()
		}
	}

	if len(recognizedResult.Amount) > 0 {
		amount, err := utils.ParseAmount(recognizedResult.Amount)

		if err != nil {
			log.Errorf(c, "[large_language_models.parseRecognizedReceiptImageResponse] recoginzed amount \"%s\" is invalid", recognizedResult.Amount)
			return nil, errs.ErrOperationFailed
		}

		recognizedReceiptImageResponse.SourceAmount = amount

		if recognizedReceiptImageResponse.Type == models.TRANSACTION_TYPE_TRANSFER && len(recognizedResult.DestinationAmount) > 0 {
			destinationAmount, err := utils.ParseAmount(recognizedResult.DestinationAmount)

			if err != nil {
				log.Errorf(c, "[large_language_models.parseRecognizedReceiptImageResponse] recoginzed destination amount \"%s\" is invalid", recognizedResult.DestinationAmount)
				return nil, errs.ErrOperationFailed
			}

			recognizedReceiptImageResponse.DestinationAmount = destinationAmount
		}
	}

	if len(recognizedResult.AccountName) > 0 {
		account, exists := accountMap[recognizedResult.AccountName]

		if exists {
			recognizedReceiptImageResponse.SourceAccountId = account.AccountId
		}
	}

	if len(recognizedResult.DestinationAccountName) > 0 {
		account, exists := accountMap[recognizedResult.DestinationAccountName]

		if exists {
			recognizedReceiptImageResponse.DestinationAccountId = account.AccountId
		}
	}

	if len(recognizedResult.TagNames) > 0 {
		tagIds := make([]string, 0, len(recognizedResult.TagNames))
		var nextDisplayOrder int32 = 0
		var maxOrderFetched bool = false

		for i := 0; i < len(recognizedResult.TagNames); i++ {
			tagName := recognizedResult.TagNames[i]
			tag, exists := tagMap[tagName]

			if exists {
				tagIds = append(tagIds, utils.Int64ToString(tag.TagId))
				continue
			}

			if !maxOrderFetched {
				maxOrder, err := a.transactionTags.GetMaxDisplayOrder(c, uid, 0)

				if err != nil {
					log.Warnf(c, "[large_language_models.parseRecognizedReceiptImageResponse] failed to get max display order for user \"uid:%d\", because %s", uid, err.Error())
				} else {
					nextDisplayOrder = maxOrder
				}

				maxOrderFetched = true
			}

			nextDisplayOrder++

			newTag := &models.TransactionTag{
				Uid:          uid,
				Name:         tagName,
				TagGroupId:   0,
				DisplayOrder: nextDisplayOrder,
			}

			err := a.transactionTags.CreateTag(c, newTag)

			if err != nil {
				log.Warnf(c, "[large_language_models.parseRecognizedReceiptImageResponse] failed to auto-create tag \"%s\" for user \"uid:%d\", because %s", tagName, uid, err.Error())
				continue
			}

			tagMap[tagName] = newTag
			tagIds = append(tagIds, utils.Int64ToString(newTag.TagId))
		}

		recognizedReceiptImageResponse.TagIds = tagIds
	}

	if len(recognizedResult.Description) > 0 {
		recognizedReceiptImageResponse.Comment = recognizedResult.Description
	}

	return recognizedReceiptImageResponse, nil
}

func (a *LargeLanguageModelsApi) getLongDateTime(dateTime string) string {
	if utils.IsValidLongDateTimeFormat(dateTime) {
		return dateTime
	}

	if utils.IsValidLongDateTimeWithoutSecondFormat(dateTime) {
		return dateTime + ":00"
	}

	if utils.IsValidLongDateFormat(dateTime) {
		return dateTime + " 00:00:00"
	}

	return dateTime
}
