package errs

import "net/http"

// Error codes related to large language model features
var (
	ErrLargeLanguageModelProviderNotEnabled = NewNormalError(NormalSubcategoryLargeLanguageModel, 0, http.StatusBadRequest, "llm provider is not enabled")
	ErrNoAIRecognitionImage                 = NewNormalError(NormalSubcategoryLargeLanguageModel, 1, http.StatusBadRequest, "no image for AI recognition")
	ErrAIRecognitionImageIsEmpty            = NewNormalError(NormalSubcategoryLargeLanguageModel, 2, http.StatusBadRequest, "image for AI recognition is empty")
	ErrExceedMaxAIRecognitionImageFileSize  = NewNormalError(NormalSubcategoryLargeLanguageModel, 3, http.StatusBadRequest, "exceed the maximum size of image file for AI recognition")
	ErrNoTransactionInformationInImage      = NewNormalError(NormalSubcategoryLargeLanguageModel, 4, http.StatusBadRequest, "no transaction information detected")
	ErrNoTransactionText                    = NewNormalError(NormalSubcategoryLargeLanguageModel, 5, http.StatusBadRequest, "no text for transaction parsing")
	ErrTransactionTextTooLong               = NewNormalError(NormalSubcategoryLargeLanguageModel, 6, http.StatusBadRequest, "text for transaction parsing is too long")
	ErrASRProviderNotEnabled                = NewNormalError(NormalSubcategoryLargeLanguageModel, 7, http.StatusBadRequest, "speech recognition provider is not enabled")
	ErrNoTransactionAudio                   = NewNormalError(NormalSubcategoryLargeLanguageModel, 8, http.StatusBadRequest, "no audio for transaction parsing")
	ErrTransactionAudioIsEmpty              = NewNormalError(NormalSubcategoryLargeLanguageModel, 9, http.StatusBadRequest, "audio for transaction parsing is empty")
	ErrExceedMaxTransactionAudioFileSize    = NewNormalError(NormalSubcategoryLargeLanguageModel, 10, http.StatusBadRequest, "exceed the maximum size of audio file for transaction parsing")
	ErrAudioTypeNotSupported                = NewNormalError(NormalSubcategoryLargeLanguageModel, 11, http.StatusBadRequest, "audio type is not supported")
	ErrASRRequestFailed                     = NewNormalError(NormalSubcategoryLargeLanguageModel, 12, http.StatusBadRequest, "speech recognition request failed")
)
