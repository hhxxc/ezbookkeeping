package services

import (
	"strings"
	"time"

	"xorm.io/xorm"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/log"
	"github.com/mayswind/ezbookkeeping/pkg/models"
	"github.com/mayswind/ezbookkeeping/pkg/utils"
	"github.com/mayswind/ezbookkeeping/pkg/uuid"
)

// CreateInstallmentPlan saves a new installment plan and generates all its period
// transactions in one database transaction. Amounts are split evenly from the total
// amount with the remainder going to the last period; period dates are one month apart
// (day clipped to the last day of the target month).
// Returns the saved plan and the count of periods whose transaction time has passed.
func (s *TransactionService) CreateInstallmentPlan(c core.Context, uid int64, req *models.TransactionInstallmentCreateRequest) (*models.TransactionInstallmentPlan, int32, error) {
	if uid <= 0 {
		return nil, 0, errs.ErrUserIdInvalid
	}

	transactionDbType, err := req.Type.ToTransactionDbType()

	if err != nil {
		return nil, 0, errs.ErrTransactionTypeInvalid
	}

	if transactionDbType != models.TRANSACTION_DB_TYPE_EXPENSE && transactionDbType != models.TRANSACTION_DB_TYPE_INCOME {
		return nil, 0, errs.ErrTransactionTypeInvalid
	}

	if req.TotalPeriods < models.MinimumTotalPeriodsOfInstallmentPlan || req.TotalPeriods > models.MaximumTotalPeriodsOfInstallmentPlan {
		return nil, 0, errs.ErrIncompleteOrIncorrectSubmission
	}

	tagIds, err := utils.StringArrayToInt64Array(req.TagIds)

	if err != nil {
		return nil, 0, errs.ErrTransactionTagIdInvalid
	}

	if len(tagIds) > models.MaximumTagsCountOfTransaction {
		return nil, 0, errs.ErrTransactionHasTooManyTags
	}

	tagIds = utils.ToUniqueInt64Slice(tagIds)

	now := time.Now().Unix()
	periodAmount := req.SourceAmount / int64(req.TotalPeriods)
	lastPeriodAmount := req.SourceAmount - periodAmount*int64(req.TotalPeriods-1)

	plan := &models.TransactionInstallmentPlan{
		Uid:                  uid,
		Name:                 req.Name,
		Type:                 transactionDbType,
		CategoryId:           req.CategoryId,
		AccountId:            req.SourceAccountId,
		TagIds:               strings.Join(utils.Int64ArrayToStringArray(tagIds), ","),
		TotalPeriods:         req.TotalPeriods,
		PeriodAmount:         periodAmount,
		LastPeriodAmount:     lastPeriodAmount,
		StartTransactionTime: req.Time,
		TimezoneUtcOffset:    req.UtcOffset,
		HideAmount:           req.HideAmount,
		Comment:              req.Comment,
		CreatedUnixTime:      now,
		UpdatedUnixTime:      now,
	}

	needTransactionUuidCount := int(req.TotalPeriods)
	needTagIndexUuidCount := len(tagIds) * int(req.TotalPeriods)

	transactionUuids := s.GenerateUuids(uuid.UUID_TYPE_TRANSACTION, uint16(needTransactionUuidCount))

	if len(transactionUuids) < needTransactionUuidCount {
		return nil, 0, errs.ErrSystemIsBusy
	}

	tagIndexUuids := s.GenerateUuids(uuid.UUID_TYPE_TAG_INDEX, uint16(needTagIndexUuidCount))

	if len(tagIndexUuids) < needTagIndexUuidCount {
		return nil, 0, errs.ErrSystemIsBusy
	}

	transactions := make([]*models.Transaction, 0, req.TotalPeriods)

	for i := int32(0); i < req.TotalPeriods; i++ {
		periodUnixTime := utils.AddMonthsToUnixTime(req.Time, int(i), req.UtcOffset)
		amount := periodAmount

		if i == req.TotalPeriods-1 {
			amount = lastPeriodAmount
		}

		transaction := &models.Transaction{
			Uid:               uid,
			Type:              transactionDbType,
			CategoryId:        req.CategoryId,
			TransactionTime:   utils.GetMinTransactionTimeFromUnixTime(periodUnixTime),
			TimezoneUtcOffset: req.UtcOffset,
			AccountId:         req.SourceAccountId,
			Amount:            amount,
			HideAmount:        req.HideAmount,
			Comment:           req.Comment,
		}

		transactions = append(transactions, transaction)
	}

	paidPeriods := int32(0)
	userDataDb := s.UserDataDB(uid)

	err = userDataDb.DoTransaction(c, func(sess *xorm.Session) error {
		// Insert the plan first to get the auto-increment plan id
		_, err := sess.Insert(plan)

		if err != nil {
			log.Errorf(c, "[transactions.CreateInstallmentPlan] failed to insert installment plan for user \"uid:%d\", because %s", uid, err.Error())
			return err
		}

		transactionUuidIndex := 0
		tagIndexUuidIndex := 0

		for i := 0; i < len(transactions); i++ {
			transaction := transactions[i]
			transaction.TransactionId = transactionUuids[transactionUuidIndex]
			transactionUuidIndex++
			transaction.InstallmentPlanId = plan.InstallmentPlanId
			transaction.InstallmentIndex = int32(i)
			transaction.InstallmentCount = req.TotalPeriods

			transactionTagIndexes := make([]*models.TransactionTagIndex, len(tagIds))

			for j := 0; j < len(tagIds); j++ {
				transactionTagIndexes[j] = &models.TransactionTagIndex{
					TagIndexId:      tagIndexUuids[tagIndexUuidIndex],
					Uid:             uid,
					Deleted:         false,
					TagId:           tagIds[j],
					TransactionId:   transaction.TransactionId,
					CreatedUnixTime: now,
					UpdatedUnixTime: now,
				}
				tagIndexUuidIndex++
			}

			pictureUpdateModel := &models.TransactionPictureInfo{
				TransactionId:   transaction.TransactionId,
				UpdatedUnixTime: now,
			}

			err = s.doCreateTransaction(c, userDataDb, sess, transaction, transactionTagIndexes, tagIds, nil, pictureUpdateModel)

			if err != nil {
				log.Errorf(c, "[transactions.CreateInstallmentPlan] failed to create period transaction \"index:%d\" of installment plan \"id:%d\" for user \"uid:%d\", because %s", i, plan.InstallmentPlanId, uid, err.Error())
				return err
			}

			if utils.GetUnixTimeFromTransactionTime(transaction.TransactionTime) <= now {
				paidPeriods++
			}
		}

		return nil
	})

	if err != nil {
		return nil, 0, err
	}

	log.Infof(c, "[transactions.CreateInstallmentPlan] user \"uid:%d\" has created installment plan \"id:%d\" with \"%d\" transactions successfully", uid, plan.InstallmentPlanId, len(transactions))

	return plan, paidPeriods, nil
}

// GetAllInstallmentPlansByUid returns all installment plans of user with the paid period count of each plan
func (s *TransactionService) GetAllInstallmentPlansByUid(c core.Context, uid int64) ([]*models.TransactionInstallmentPlan, map[int64]int32, error) {
	if uid <= 0 {
		return nil, nil, errs.ErrUserIdInvalid
	}

	plans := make([]*models.TransactionInstallmentPlan, 0)
	err := s.UserDataDB(uid).NewSession(c).Where("uid=? AND deleted=?", uid, false).Find(&plans)

	if err != nil {
		return nil, nil, err
	}

	paidPeriodsMap := make(map[int64]int32)

	if len(plans) == 0 {
		return plans, paidPeriodsMap, nil
	}

	transactions := make([]*models.Transaction, 0)
	err = s.UserDataDB(uid).NewSession(c).Cols("installment_plan_id", "transaction_time").Where("uid=? AND deleted=? AND installment_plan_id>0", uid, false).Find(&transactions)

	if err != nil {
		return nil, nil, err
	}

	currentUnixTime := time.Now().Unix()

	for i := 0; i < len(transactions); i++ {
		if utils.GetUnixTimeFromTransactionTime(transactions[i].TransactionTime) <= currentUnixTime {
			paidPeriodsMap[transactions[i].InstallmentPlanId]++
		}
	}

	return plans, paidPeriodsMap, nil
}

// GetInstallmentPlanById returns an installment plan model according to plan id
func (s *TransactionService) GetInstallmentPlanById(c core.Context, uid int64, planId int64) (*models.TransactionInstallmentPlan, error) {
	plan := &models.TransactionInstallmentPlan{}
	has, err := s.UserDataDB(uid).NewSession(c).ID(planId).Where("uid=? AND deleted=?", uid, false).Get(plan)

	if err != nil {
		return nil, err
	} else if !has {
		return nil, errs.ErrTransactionNotFound
	}

	return plan, nil
}

// GetInstallmentPlanTransactions returns all period transactions of an installment plan ordered by period index
func (s *TransactionService) GetInstallmentPlanTransactions(c core.Context, uid int64, planId int64) ([]*models.Transaction, error) {
	transactions := make([]*models.Transaction, 0)
	err := s.UserDataDB(uid).NewSession(c).Where("uid=? AND deleted=? AND installment_plan_id=?", uid, false, planId).OrderBy("installment_index ASC").Find(&transactions)

	return transactions, err
}

// DeleteInstallmentPlan soft-deletes an installment plan. When deleteTransactions is true,
// all its period transactions (and their tag indexes) are also soft-deleted; otherwise
// the transactions are kept as normal records.
func (s *TransactionService) DeleteInstallmentPlan(c core.Context, uid int64, planId int64, deleteTransactions bool) error {
	if uid <= 0 {
		return errs.ErrUserIdInvalid
	}

	now := time.Now().Unix()

	return s.UserDataDB(uid).DoTransaction(c, func(sess *xorm.Session) error {
		plan := &models.TransactionInstallmentPlan{}
		has, err := sess.ID(planId).Where("uid=? AND deleted=?", uid, false).Get(plan)

		if err != nil {
			return err
		} else if !has {
			return errs.ErrTransactionNotFound
		}

		planUpdateModel := &models.TransactionInstallmentPlan{
			Deleted:         true,
			DeletedUnixTime: now,
			UpdatedUnixTime: now,
		}

		deletedRows, err := sess.ID(plan.InstallmentPlanId).Cols("deleted", "deleted_unix_time", "updated_unix_time").Where("uid=? AND deleted=?", uid, false).Update(planUpdateModel)

		if err != nil {
			return err
		} else if deletedRows < 1 {
			return errs.ErrTransactionNotFound
		}

		if !deleteTransactions {
			return nil
		}

		transactionUpdateModel := &models.Transaction{
			Deleted:         true,
			DeletedUnixTime: now,
		}

		_, err = sess.Cols("deleted", "deleted_unix_time").Where("uid=? AND deleted=? AND installment_plan_id=?", uid, false, planId).Update(transactionUpdateModel)

		if err != nil {
			return err
		}

		transactions := make([]*models.Transaction, 0)
		err = sess.Cols("transaction_id").Where("uid=? AND installment_plan_id=?", uid, planId).Find(&transactions)

		if err != nil {
			return err
		}

		if len(transactions) > 0 {
			transactionIds := make([]int64, 0, len(transactions))

			for i := 0; i < len(transactions); i++ {
				transactionIds = append(transactionIds, transactions[i].TransactionId)
			}

			tagIndexUpdateModel := &models.TransactionTagIndex{
				Deleted:         true,
				DeletedUnixTime: now,
			}

			_, err = sess.Cols("deleted", "deleted_unix_time").Where("uid=? AND deleted=?", uid, false).In("transaction_id", transactionIds).Update(tagIndexUpdateModel)

			if err != nil {
				return err
			}
		}

		return nil
	})
}
