package models

import (
	"strings"

	"github.com/mayswind/ezbookkeeping/pkg/utils"
)

// MinimumTotalPeriodsOfInstallmentPlan represents the minimum total periods of an installment plan
const MinimumTotalPeriodsOfInstallmentPlan = 2

// MaximumTotalPeriodsOfInstallmentPlan represents the maximum total periods of an installment plan
const MaximumTotalPeriodsOfInstallmentPlan = 60

// TransactionInstallmentPlan represents an installment plan stored in database.
// Creating a plan generates all period transactions at once; each transaction
// references the plan by InstallmentPlanId (see models.Transaction).
type TransactionInstallmentPlan struct {
	InstallmentPlanId    int64             `xorm:"PK"`
	Uid                  int64             `xorm:"INDEX(IDX_transaction_installment_plan_uid_deleted) NOT NULL"`
	Deleted              bool              `xorm:"INDEX(IDX_transaction_installment_plan_uid_deleted) NOT NULL"`
	Name                 string            `xorm:"VARCHAR(64) NOT NULL"`
	Type                 TransactionDbType `xorm:"NOT NULL"` // only expense or income
	CategoryId           int64             `xorm:"NOT NULL"`
	AccountId            int64             `xorm:"NOT NULL"`
	TagIds               string            `xorm:"VARCHAR(255) NOT NULL"`
	TotalPeriods         int32             `xorm:"NOT NULL"`
	PeriodAmount         int64             `xorm:"NOT NULL"` // amount of each period except the last one (in cents)
	LastPeriodAmount     int64             `xorm:"NOT NULL"` // amount of the last period (remainder included)
	StartTransactionTime int64             `xorm:"NOT NULL"` // unix time (seconds) of the first period
	TimezoneUtcOffset    int16             `xorm:"NOT NULL"`
	HideAmount           bool              `xorm:"NOT NULL"`
	Comment              string            `xorm:"VARCHAR(255) NOT NULL"`
	CreatedUnixTime      int64
	UpdatedUnixTime      int64
	DeletedUnixTime      int64
}

// TransactionInstallmentCreateRequest represents all parameters of installment plan creation request.
// SourceAmount is the TOTAL amount of all periods; each period amount is computed server-side
// (remainder goes to the last period).
type TransactionInstallmentCreateRequest struct {
	Name            string          `json:"name" binding:"required,notBlank,max=64"`
	Type            TransactionType `json:"type" binding:"required"`
	CategoryId      int64           `json:"categoryId,string" binding:"required,min=1"`
	Time            int64           `json:"time" binding:"required,min=1"` // unix time (seconds) of the first period
	UtcOffset       int16           `json:"utcOffset" binding:"min=-720,max=840"`
	SourceAccountId int64           `json:"sourceAccountId,string" binding:"required,min=1"`
	SourceAmount    int64           `json:"sourceAmount" binding:"min=1,max=99999999999"`
	TotalPeriods    int32           `json:"totalPeriods" binding:"min=2,max=60"`
	HideAmount      bool            `json:"hideAmount"`
	TagIds          []string        `json:"tagIds"`
	Comment         string          `json:"comment" binding:"max=255"`
}

// TransactionInstallmentGetRequest represents all parameters of installment plan getting request
type TransactionInstallmentGetRequest struct {
	Id int64 `form:"id,string" binding:"required,min=1"`
}

// TransactionInstallmentDeleteRequest represents all parameters of installment plan deleting request
type TransactionInstallmentDeleteRequest struct {
	Id                 int64 `json:"id,string" binding:"required,min=1"`
	DeleteTransactions bool  `json:"deleteTransactions"`
}

// TransactionInstallmentPlanInfoResponse represents a view-object of an installment plan
type TransactionInstallmentPlanInfoResponse struct {
	Id               int64    `json:"id,string"`
	Name             string   `json:"name"`
	Type             TransactionType `json:"type"`
	CategoryId       int64    `json:"categoryId,string"`
	SourceAccountId  int64    `json:"sourceAccountId,string"`
	PeriodAmount     int64    `json:"periodAmount"`
	LastPeriodAmount int64    `json:"lastPeriodAmount"`
	TotalAmount      int64    `json:"totalAmount"`
	TotalPeriods     int32    `json:"totalPeriods"`
	PaidPeriods      int32    `json:"paidPeriods"` // periods whose transaction time has passed
	StartTime        int64    `json:"startTime"`
	EndTime          int64    `json:"endTime"`
	NextTime         int64    `json:"nextTime,omitempty"` // time of the next unpaid period (0 when finished)
	HideAmount       bool     `json:"hideAmount"`
	TagIds           []string `json:"tagIds"`
	Comment          string   `json:"comment"`
}

// TransactionInstallmentPlanGetResponse represents a response of an installment plan with all its period transactions
type TransactionInstallmentPlanGetResponse struct {
	Plan         *TransactionInstallmentPlanInfoResponse `json:"plan"`
	Transactions TransactionInfoResponseSlice            `json:"transactions"`
}

// GetTagIds returns all tag ids of the installment plan
func (p *TransactionInstallmentPlan) GetTagIds() []int64 {
	tagIds := make([]string, 0)

	if p.TagIds != "" {
		tagIds = strings.Split(p.TagIds, ",")
	}

	result, _ := utils.StringArrayToInt64Array(tagIds)

	return result
}

// GetPeriodUnixTime returns the unix time (seconds) of the period at given zero-based index
func (p *TransactionInstallmentPlan) GetPeriodUnixTime(index int32) int64 {
	return utils.AddMonthsToUnixTime(p.StartTransactionTime, int(index), p.TimezoneUtcOffset)
}

// ToTransactionInstallmentPlanInfoResponse returns a view-object according to database model
func (p *TransactionInstallmentPlan) ToTransactionInstallmentPlanInfoResponse(paidPeriods int32, currentUnixTime int64) *TransactionInstallmentPlanInfoResponse {
	var transactionType TransactionType

	if p.Type == TRANSACTION_DB_TYPE_INCOME {
		transactionType = TRANSACTION_TYPE_INCOME
	} else {
		transactionType = TRANSACTION_TYPE_EXPENSE
	}

	endTime := p.GetPeriodUnixTime(p.TotalPeriods - 1)

	nextTime := int64(0)
	if paidPeriods < p.TotalPeriods {
		nextTime = p.GetPeriodUnixTime(paidPeriods)
	}

	return &TransactionInstallmentPlanInfoResponse{
		Id:               p.InstallmentPlanId,
		Name:             p.Name,
		Type:             transactionType,
		CategoryId:       p.CategoryId,
		SourceAccountId:  p.AccountId,
		PeriodAmount:     p.PeriodAmount,
		LastPeriodAmount: p.LastPeriodAmount,
		TotalAmount:      p.PeriodAmount*int64(p.TotalPeriods-1) + p.LastPeriodAmount,
		TotalPeriods:     p.TotalPeriods,
		PaidPeriods:      paidPeriods,
		StartTime:        p.StartTransactionTime,
		EndTime:          endTime,
		NextTime:         nextTime,
		HideAmount:       p.HideAmount,
		TagIds:           utils.Int64ArrayToStringArray(p.GetTagIds()),
		Comment:          p.Comment,
	}
}
