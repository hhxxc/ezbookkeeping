package api

import (
	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/log"
	"github.com/mayswind/ezbookkeeping/pkg/models"
	"github.com/mayswind/ezbookkeeping/pkg/services"
)

// TransactionBudgetsApi represents transaction budget api
type TransactionBudgetsApi struct {
	budgets *services.TransactionBudgetService
}

// Initialize a transaction budget api singleton instance
var (
	TransactionBudgets = &TransactionBudgetsApi{
		budgets: services.TransactionBudgets,
	}
)

// GetBudgetHandler returns the budget of specified month for current user
func (a *TransactionBudgetsApi) GetBudgetHandler(c *core.WebContext) (any, *errs.Error) {
	uid := c.GetCurrentUid()

	var req models.TransactionBudgetGetRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		return nil, errs.NewIncompleteOrIncorrectSubmissionError(err)
	}

	budget, err := a.budgets.GetBudget(c, uid, req.Year, req.Month)

	if err != nil {
		log.Errorf(c, "[transaction_budgets.GetBudgetHandler] failed to get budget for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	return buildBudgetResponse(budget), nil
}

// SaveBudgetHandler saves the budget of specified month for current user
func (a *TransactionBudgetsApi) SaveBudgetHandler(c *core.WebContext) (any, *errs.Error) {
	uid := c.GetCurrentUid()

	var req models.TransactionBudgetSaveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return nil, errs.NewIncompleteOrIncorrectSubmissionError(err)
	}

	budget, err := a.budgets.SaveBudget(c, uid, &req)

	if err != nil {
		log.Errorf(c, "[transaction_budgets.SaveBudgetHandler] failed to save budget for user \"uid:%d\", because %s", uid, err.Error())
		return nil, errs.Or(err, errs.ErrOperationFailed)
	}

	return buildBudgetResponse(budget), nil
}

func buildBudgetResponse(budget *models.TransactionBudget) *models.TransactionBudgetGetResponse {
	resp := &models.TransactionBudgetGetResponse{
		Year:            budget.Year,
		Month:           budget.Month,
		TotalAmount:     budget.TotalAmount,
		CategoryBudgets: make([]models.BudgetCategoryAmount, 0),
	}

	categoryBudgets, err := services.TransactionBudgets.ParseCategoryBudgets(budget.CategoryBudgets)

	if err == nil {
		for categoryId, amount := range categoryBudgets {
			resp.CategoryBudgets = append(resp.CategoryBudgets, models.BudgetCategoryAmount{
				CategoryId: categoryId,
				Amount:     amount,
			})
		}
	}

	return resp
}
