package services

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/mayswind/ezbookkeeping/pkg/models"
)

// 关键词搜索（非数字）：应同时命中备注、分类名（含父分类名命中的子分类）与账户名
func TestBuildTransactionQueryCondition_KeywordSearchesCommentAndCategoryAndAccount(t *testing.T) {
	condition, params := Transactions.buildTransactionQueryCondition(1, 0, 0, models.TRANSACTION_DB_TYPE_EXPENSE, nil, nil, nil, "", "育儿", false)

	assert.Contains(t, condition, "comment LIKE ?")
	assert.Contains(t, condition, "transaction_category")
	assert.Contains(t, condition, "parent_category_id")
	assert.Contains(t, condition, "account WHERE")
	assert.Contains(t, condition, "parent_account_id")
	// uid/deleted/type 3 个 + comment 1 个 + 分类名子查询 5 个 + 账户名子查询 5 个 = 14
	assert.Equal(t, 14, len(params))
	assert.Equal(t, "%%育儿%%", params[3])
}

// 关键词搜索（纯数字）：金额精确命中 + 备注/分类名/账户名模糊命中
func TestBuildTransactionQueryCondition_KeywordAmountSearchIncludesNames(t *testing.T) {
	condition, params := Transactions.buildTransactionQueryCondition(1, 0, 0, models.TRANSACTION_DB_TYPE_EXPENSE, nil, nil, nil, "", "88", false)

	assert.Contains(t, condition, "amount = ?")
	assert.Contains(t, condition, "comment LIKE ?")
	// uid/deleted/type 3 个 + comment 1 + amount 1 + 分类名子查询 5 + 账户名子查询 5 = 15
	assert.Equal(t, 15, len(params))
	// 金额参数紧跟其 comment 参数之后
	amountFound := false
	for i, p := range params {
		if p == int64(8800) {
			amountFound = true
			assert.Equal(t, "%%88%%", params[i-1])
		}
	}
	assert.True(t, amountFound, "amount param should follow its comment param")
}

// 关键词为空：不追加任何 keyword 条件
func TestBuildTransactionQueryCondition_EmptyKeyword(t *testing.T) {
	condition, params := Transactions.buildTransactionQueryCondition(1, 0, 0, models.TRANSACTION_DB_TYPE_EXPENSE, nil, nil, nil, "", "", false)

	assert.NotContains(t, condition, "comment LIKE ?")
	assert.NotContains(t, condition, "transaction_category")
	assert.Equal(t, 3, len(params)) // 仅 uid + deleted + type
}
