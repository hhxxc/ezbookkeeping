package api

import (
	"fmt"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/duplicatechecker"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/log"
	"github.com/mayswind/ezbookkeeping/pkg/models"
	"github.com/mayswind/ezbookkeeping/pkg/services"
	"github.com/mayswind/ezbookkeeping/pkg/settings"
	"github.com/mayswind/ezbookkeeping/pkg/utils"
)

// HomeBackgroundApi represents home background api
type HomeBackgroundApi struct {
	ApiUsingConfig
	ApiUsingDuplicateChecker
	pictures *services.TransactionPictureService
}

// Initialize a home background api singleton instance
var (
	HomeBackgrounds = &HomeBackgroundApi{
		ApiUsingConfig: ApiUsingConfig{
			container: settings.Container,
		},
		ApiUsingDuplicateChecker: ApiUsingDuplicateChecker{
			ApiUsingConfig: ApiUsingConfig{
				container: settings.Container,
			},
			container: duplicatechecker.Container,
		},
		pictures: services.TransactionPictures,
	}
)

// HomeBackgroundUploadResponse represents the response of home background upload
type HomeBackgroundUploadResponse struct {
	Url string `json:"url"`
}

// HomeBackgroundUploadHandler saves home background image by request parameters for current user
func (a *HomeBackgroundApi) HomeBackgroundUploadHandler(c *core.WebContext) (any, *errs.Error) {
	uid := c.GetCurrentUid()
	form, err := c.MultipartForm()

	if err != nil {
		log.Errorf(c, "[home_backgrounds.HomeBackgroundUploadHandler] failed to get multi-part form data for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.ErrParameterInvalid
	}

	pictureFiles := form.File["picture"]

	if len(pictureFiles) < 1 {
		log.Warnf(c, "[home_backgrounds.HomeBackgroundUploadHandler] there is no picture in request for user \"uid:%d\"", uid)
		return nil, errs.ErrNoTransactionPicture
	}

	if pictureFiles[0].Size < 1 {
		log.Warnf(c, "[home_backgrounds.HomeBackgroundUploadHandler] the size of picture in request is zero for user \"uid:%d\"", uid)
		return nil, errs.ErrTransactionPictureIsEmpty
	}

	if pictureFiles[0].Size > int64(a.CurrentConfig().MaxTransactionPictureFileSize) {
		log.Warnf(c, "[home_backgrounds.HomeBackgroundUploadHandler] the upload file size \"%d\" exceeds the maximum size \"%d\" for user \"uid:%d\"", pictureFiles[0].Size, a.CurrentConfig().MaxTransactionPictureFileSize, uid)
		return nil, errs.ErrExceedMaxTransactionPictureFileSize
	}

	fileExtension := utils.GetFileNameExtension(pictureFiles[0].Filename)

	if utils.GetImageContentType(fileExtension) == "" {
		log.Warnf(c, "[home_backgrounds.HomeBackgroundUploadHandler] the file extension \"%s\" is not supported for user \"uid:%d\"", fileExtension, uid)
		return nil, errs.ErrImageTypeNotSupported
	}

	pictureFile, err := pictureFiles[0].Open()

	if err != nil {
		log.Errorf(c, "[home_backgrounds.HomeBackgroundUploadHandler] failed to get picture file from request for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.ErrOperationFailed
	}

	pictureInfo := &models.TransactionPictureInfo{
		Uid:              uid,
		TransactionId:    models.TransactionPictureNewPictureTransactionId,
		PictureExtension: fileExtension,
		CreatedIp:        c.ClientIP(),
	}

	clientSessionIds := form.Value["clientSessionId"]
	clientSessionId := ""

	if len(clientSessionIds) > 0 {
		clientSessionId = clientSessionIds[0]
	}

	if a.CurrentConfig().EnableDuplicateSubmissionsCheck && clientSessionId != "" {
		found, remark := a.GetSubmissionRemark(duplicatechecker.DUPLICATE_CHECKER_TYPE_NEW_PICTURE, uid, clientSessionId)

		if found {
			log.Infof(c, "[home_backgrounds.HomeBackgroundUploadHandler] another picture has been uploaded for user \"uid:%d\"", uid)
			pictureId, err := utils.StringToInt64(remark)

			if err == nil {
				pictureInfo, err = a.pictures.GetPictureInfoByPictureId(c, uid, pictureId)

				if err != nil {
					log.Errorf(c, "[home_backgrounds.HomeBackgroundUploadHandler] failed to get existed picture \"id:%d\" for user \"uid:%d\", because %s", pictureId, uid, err.Error())
					return nil, errs.Or(err, errs.ErrOperationFailed)
				}

				relativePath := fmt.Sprintf("pictures/%d.%s", pictureInfo.PictureId, pictureInfo.PictureExtension)
				return &HomeBackgroundUploadResponse{Url: relativePath}, nil
			}
		}
	}

	err = a.pictures.UploadPicture(c, pictureInfo, pictureFile)

	if err != nil {
		log.Errorf(c, "[home_backgrounds.HomeBackgroundUploadHandler] failed to upload picture for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	a.SetSubmissionRemarkIfEnable(duplicatechecker.DUPLICATE_CHECKER_TYPE_NEW_PICTURE, uid, clientSessionId, utils.Int64ToString(pictureInfo.PictureId))

	relativePath := fmt.Sprintf("pictures/%d.%s", pictureInfo.PictureId, pictureInfo.PictureExtension)

	return &HomeBackgroundUploadResponse{Url: relativePath}, nil
}
