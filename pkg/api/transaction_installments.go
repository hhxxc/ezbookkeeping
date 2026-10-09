package api

import (
	"sort"
	"time"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/log"
	"github.com/mayswind/ezbookkeeping/pkg/models"
	"github.com/mayswind/ezbookkeeping/pkg/utils"
)

// InstallmentCreateHandler saves a new installment plan with all its period transactions for current user
func (a *TransactionsApi) InstallmentCreateHandler(c *core.WebContext) (any, *errs.Error) {
	var installmentCreateReq models.TransactionInstallmentCreateRequest
	err := c.ShouldBindJSON(&installmentCreateReq)

	if err != nil {
		log.Warnf(c, "[transactions.InstallmentCreateHandler] parse request failed, because %s", err.Error())
		return nil, errs.NewIncompleteOrIncorrectSubmissionError(err)
	}

	if installmentCreateReq.Type != models.TRANSACTION_TYPE_EXPENSE && installmentCreateReq.Type != models.TRANSACTION_TYPE_INCOME {
		log.Warnf(c, "[transactions.InstallmentCreateHandler] transaction type is invalid")
		return nil, errs.ErrTransactionTypeInvalid
	}

	tagIds, err := utils.StringArrayToInt64Array(installmentCreateReq.TagIds)

	if err != nil {
		log.Warnf(c, "[transactions.InstallmentCreateHandler] parse tag ids failed, because %s", err.Error())
		return nil, errs.ErrTransactionTagIdInvalid
	}

	if len(tagIds) > models.MaximumTagsCountOfTransaction {
		return nil, errs.ErrTransactionHasTooManyTags
	}

	clientTimezone, err := c.GetClientTimezone()

	if err != nil {
		log.Warnf(c, "[transactions.InstallmentCreateHandler] cannot get client timezone, because %s", err.Error())
		return nil, errs.ErrClientTimezoneOffsetInvalid
	}

	uid := c.GetCurrentUid()
	user, err := a.users.GetUserById(c, uid)

	if err != nil {
		if !errs.IsCustomError(err) {
			log.Errorf(c, "[transactions.InstallmentCreateHandler] failed to get user, because %s", err.Error())
		}

		return nil, errs.ErrUserNotFound
	}

	transactionTime := utils.GetMinTransactionTimeFromUnixTime(installmentCreateReq.Time)
	transactionEditable := user.CanEditTransactionByTransactionTime(transactionTime, clientTimezone)

	if !transactionEditable {
		return nil, errs.ErrCannotCreateTransactionWithThisTransactionTime
	}

	plan, paidPeriods, err := a.transactions.CreateInstallmentPlan(c, uid, &installmentCreateReq)

	if err != nil {
		log.Errorf(c, "[transactions.InstallmentCreateHandler] failed to create installment plan for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	return plan.ToTransactionInstallmentPlanInfoResponse(paidPeriods, time.Now().Unix()), nil
}

// InstallmentListHandler returns all installment plans of current user
func (a *TransactionsApi) InstallmentListHandler(c *core.WebContext) (any, *errs.Error) {
	uid := c.GetCurrentUid()
	plans, paidPeriodsMap, err := a.transactions.GetAllInstallmentPlansByUid(c, uid)

	if err != nil {
		log.Errorf(c, "[transactions.InstallmentListHandler] failed to get installment plans for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	now := time.Now().Unix()
	planResps := make([]*models.TransactionInstallmentPlanInfoResponse, 0, len(plans))

	for i := 0; i < len(plans); i++ {
		planResps = append(planResps, plans[i].ToTransactionInstallmentPlanInfoResponse(paidPeriodsMap[plans[i].InstallmentPlanId], now))
	}

	sort.Slice(planResps, func(i, j int) bool {
		return planResps[i].StartTime > planResps[j].StartTime
	})

	return planResps, nil
}

// InstallmentGetHandler returns one specific installment plan with all its period transactions of current user
func (a *TransactionsApi) InstallmentGetHandler(c *core.WebContext) (any, *errs.Error) {
	var installmentGetReq models.TransactionInstallmentGetRequest
	err := c.ShouldBindQuery(&installmentGetReq)

	if err != nil {
		log.Warnf(c, "[transactions.InstallmentGetHandler] parse request failed, because %s", err.Error())
		return nil, errs.NewIncompleteOrIncorrectSubmissionError(err)
	}

	uid := c.GetCurrentUid()
	user, err := a.users.GetUserById(c, uid)

	if err != nil {
		if !errs.IsCustomError(err) {
			log.Errorf(c, "[transactions.InstallmentGetHandler] failed to get user, because %s", err.Error())
		}

		return nil, errs.ErrUserNotFound
	}

	plan, err := a.transactions.GetInstallmentPlanById(c, uid, installmentGetReq.Id)

	if err != nil {
		log.Errorf(c, "[transactions.InstallmentGetHandler] failed to get installment plan \"id:%d\" for user \"uid:%d\", because %s", installmentGetReq.Id, uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	transactions, err := a.transactions.GetInstallmentPlanTransactions(c, uid, plan.InstallmentPlanId)

	if err != nil {
		log.Errorf(c, "[transactions.InstallmentGetHandler] failed to get transactions of installment plan \"id:%d\" for user \"uid:%d\", because %s", plan.InstallmentPlanId, uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	clientTimezone, err := c.GetClientTimezone()

	if err != nil {
		log.Warnf(c, "[transactions.InstallmentGetHandler] cannot get client timezone, because %s", err.Error())
		return nil, errs.ErrClientTimezoneOffsetInvalid
	}

	accountMap, categoryMap, tagMap, allTransactionTagIds, pictureInfoMap, err := a.getTransactionEssentialDataByTransactionIds(c, user, transactions, false, false, false)

	if err != nil {
		log.Errorf(c, "[transactions.InstallmentGetHandler] failed to get transactions essential data for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	transactionResps, err := a.getTransactionResponseListResult(c, user, transactions, accountMap, categoryMap, tagMap, allTransactionTagIds, pictureInfoMap, clientTimezone, false, false, false, false, "")

	if err != nil {
		log.Errorf(c, "[transactions.InstallmentGetHandler] failed to build transaction responses for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	currentUnixTime := time.Now().Unix()
	paidPeriods := int32(0)

	for i := 0; i < len(transactions); i++ {
		if utils.GetUnixTimeFromTransactionTime(transactions[i].TransactionTime) <= currentUnixTime {
			paidPeriods++
		}
	}

	planResp := plan.ToTransactionInstallmentPlanInfoResponse(paidPeriods, currentUnixTime)

	return &models.TransactionInstallmentPlanGetResponse{
		Plan:         planResp,
		Transactions: transactionResps,
	}, nil
}

// InstallmentDeleteHandler deletes an installment plan (optionally with all its period transactions) for current user
func (a *TransactionsApi) InstallmentDeleteHandler(c *core.WebContext) (any, *errs.Error) {
	var installmentDeleteReq models.TransactionInstallmentDeleteRequest
	err := c.ShouldBindJSON(&installmentDeleteReq)

	if err != nil {
		log.Warnf(c, "[transactions.InstallmentDeleteHandler] parse request failed, because %s", err.Error())
		return nil, errs.NewIncompleteOrIncorrectSubmissionError(err)
	}

	uid := c.GetCurrentUid()
	err = a.transactions.DeleteInstallmentPlan(c, uid, installmentDeleteReq.Id, installmentDeleteReq.DeleteTransactions)

	if err != nil {
		log.Errorf(c, "[transactions.InstallmentDeleteHandler] failed to delete installment plan \"id:%d\" for user \"uid:%d\", because %s", installmentDeleteReq.Id, uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	log.Infof(c, "[transactions.InstallmentDeleteHandler] user \"uid:%d\" has deleted installment plan \"id:%d\" successfully", uid, installmentDeleteReq.Id)

	return true, nil
}
