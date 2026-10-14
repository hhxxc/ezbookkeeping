package services

import (
	"encoding/json"
	"time"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/datastore"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/log"
	"github.com/mayswind/ezbookkeeping/pkg/models"
	"github.com/mayswind/ezbookkeeping/pkg/uuid"
)

// TransactionBudgetService represents transaction budget service
type TransactionBudgetService struct {
	ServiceUsingDB
	ServiceUsingUuid
}

// Initialize a transaction budget service singleton instance
var (
	TransactionBudgets = &TransactionBudgetService{
		ServiceUsingDB: ServiceUsingDB{
			container: datastore.Container,
		},
		ServiceUsingUuid: ServiceUsingUuid{
			container: uuid.Container,
		},
	}
)

// GetBudget returns the budget of specified month (empty struct if not set)
func (s *TransactionBudgetService) GetBudget(c core.Context, uid int64, year int32, month int32) (*models.TransactionBudget, error) {
	var budgets []*models.TransactionBudget
	err := s.UserDataDB(uid).NewSession(c).
		Where("uid=? AND deleted=? AND year=? AND month=?", uid, false, year, month).
		Find(&budgets)

	if err != nil {
		return nil, err
	}

	if len(budgets) > 0 {
		return budgets[0], nil
	}

	// 未设置过预算：返回空结构（TotalAmount=0）
	return &models.TransactionBudget{Year: year, Month: month}, nil
}

// SaveBudget saves (upsert) the budget of specified month
func (s *TransactionBudgetService) SaveBudget(c core.Context, uid int64, req *models.TransactionBudgetSaveRequest) (*models.TransactionBudget, error) {
	var budgets []*models.TransactionBudget
	err := s.UserDataDB(uid).NewSession(c).
		Where("uid=? AND deleted=? AND year=? AND month=?", uid, false, req.Year, req.Month).
		Find(&budgets)

	if err != nil {
		return nil, err
	}

	categoryBudgetsJson := "{}"
	if len(req.CategoryBudgets) > 0 {
		budgetMap := make(map[int64]int64, len(req.CategoryBudgets))
		for i := range req.CategoryBudgets {
			budgetMap[req.CategoryBudgets[i].CategoryId] = req.CategoryBudgets[i].Amount
		}
		jsonBytes, jsonErr := json.Marshal(budgetMap)
		if jsonErr != nil {
			return nil, errs.ErrOperationFailed
		}
		categoryBudgetsJson = string(jsonBytes)
	}

	var budget *models.TransactionBudget
	nowUnix := time.Now().Unix()

	if len(budgets) > 0 {
		budget = budgets[0]
		budget.TotalAmount = req.TotalAmount
		budget.CategoryBudgets = categoryBudgetsJson
		budget.UpdatedUnixTime = nowUnix
		_, err = s.UserDataDB(uid).NewSession(c).ID(budget.BudgetId).Cols("total_amount", "category_budgets", "updated_unix_time").Update(budget)
	} else {
		budget = &models.TransactionBudget{
			BudgetId:        s.GenerateUuid(uuid.UUID_TYPE_BUDGET),
			Uid:             uid,
			Year:            req.Year,
			Month:           req.Month,
			TotalAmount:     req.TotalAmount,
			CategoryBudgets: categoryBudgetsJson,
			CreatedUnixTime: nowUnix,
			UpdatedUnixTime: nowUnix,
		}
		_, err = s.UserDataDB(uid).NewSession(c).Insert(budget)
	}

	if err != nil {
		log.Errorf(c, "[transaction_budgets.SaveBudget] failed to save budget for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	return budget, nil
}

// ParseCategoryBudgets decodes the stored JSON into a map (categoryId → cents)
func (s *TransactionBudgetService) ParseCategoryBudgets(jsonText string) (map[int64]int64, error) {
	result := make(map[int64]int64)
	if jsonText == "" {
		return result, nil
	}
	err := json.Unmarshal([]byte(jsonText), &result)
	return result, err
}
