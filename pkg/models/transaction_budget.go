package models

// TransactionBudget represents a monthly budget of a user
// 每用户每月一行：总预算 + 分类预算（JSON：categoryId → 金额分）
type TransactionBudget struct {
	BudgetId        int64  `xorm:"PK"`
	Uid             int64  `xorm:"INDEX(IDX_budget_uid_deleted_year_month) NOT NULL"`
	Deleted         bool   `xorm:"INDEX(IDX_budget_uid_deleted_year_month) NOT NULL"`
	Year            int32  `xorm:"INDEX(IDX_budget_uid_deleted_year_month) NOT NULL"`
	Month           int32  `xorm:"INDEX(IDX_budget_uid_deleted_year_month) NOT NULL"`
	TotalAmount     int64  `xorm:"NOT NULL DEFAULT 0"`
	CategoryBudgets string `xorm:"TEXT"`
	CreatedUnixTime int64
	UpdatedUnixTime int64
	DeletedUnixTime int64
}

// BudgetCategoryAmount represents one category's budget amount (cents) in save/get requests
type BudgetCategoryAmount struct {
	CategoryId int64 `json:"categoryId,string"`
	Amount     int64 `json:"amount"`
}

// TransactionBudgetGetRequest represents all parameters of budget getting request
type TransactionBudgetGetRequest struct {
	Year  int32 `form:"year" binding:"required,min=2000,max=2999"`
	Month int32 `form:"month" binding:"required,min=1,max=12"`
}

// TransactionBudgetGetResponse represents a response of budget getting request
type TransactionBudgetGetResponse struct {
	Year            int32                   `json:"year"`
	Month           int32                   `json:"month"`
	TotalAmount     int64                   `json:"totalAmount"`
	CategoryBudgets []BudgetCategoryAmount  `json:"categoryBudgets"`
}

// TransactionBudgetSaveRequest represents all parameters of budget saving request
type TransactionBudgetSaveRequest struct {
	Year            int32                  `json:"year" binding:"required,min=2000,max=2999"`
	Month           int32                  `json:"month" binding:"required,min=1,max=12"`
	TotalAmount     int64                  `json:"totalAmount" binding:"min=0"`
	CategoryBudgets []BudgetCategoryAmount `json:"categoryBudgets"`
}
