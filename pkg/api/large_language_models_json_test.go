package api

import (
	"testing"

	"github.com/mayswind/ezbookkeeping/pkg/models"
)

func TestExtractJsonPayload(t *testing.T) {
	testCases := []struct {
		name     string
		content  string
		expected string
	}{
		{"plain array", `[{"amount":"1.00"}]`, `[{"amount":"1.00"}]`},
		{"plain object", `{"amount":"1.00"}`, `{"amount":"1.00"}`},
		{"empty array", `[]`, `[]`},
		{"fenced with language", "```json\n[{\"amount\":\"1.00\"}]\n```", `[{"amount":"1.00"}]`},
		{"fenced without language", "```\n[{\"amount\":\"1.00\"}]\n```", `[{"amount":"1.00"}]`},
		{"leading and trailing text", `Here is the result: [{"amount":"1.00"}] hope it helps`, `[{"amount":"1.00"}]`},
		{"leading text before object", `Result: {"amount":"1.00"} done`, `{"amount":"1.00"}`},
		{"surrounding whitespace", "\n  [{\"amount\":\"1.00\"}]  \n", `[{"amount":"1.00"}]`},
		{"no json at all", `no idea`, `no idea`},
		{"unterminated array", `[{"amount":"1.00"`, `[{"amount":"1.00"`},
	}

	for _, testCase := range testCases {
		actual := extractJsonPayload(testCase.content)

		if actual != testCase.expected {
			t.Errorf("%s: expected %q, but got %q", testCase.name, testCase.expected, actual)
		}
	}
}

func TestMergeRecognizedSingleOrderResults(t *testing.T) {
	splitOrderWithTotal := []*models.RecognizedReceiptImageResult{
		{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "24.38", AccountName: "微信支付", Description: "猪排", PageType: "single_order", OrderTotal: "31.60", Merchant: "犀牛家猪排", TagNames: []string{"美团", "外卖"}},
		{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "1.62", AccountName: "微信支付", Description: "大酱汤", PageType: "single_order", OrderTotal: "31.60", Merchant: "犀牛家猪排", TagNames: []string{"外卖"}},
		{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "4.60", AccountName: "微信支付", Description: "配送费", PageType: "single_order", OrderTotal: "31.60", Merchant: "犀牛家猪排"},
	}

	splitOrderWithoutTotal := []*models.RecognizedReceiptImageResult{
		{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "24.38", AccountName: "微信支付", Description: "犀牛家猪排"},
		{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "1.62", AccountName: "微信支付", Description: "大酱汤"},
		{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "1.00", AccountName: "微信支付", Description: "打包费"},
		{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "4.60", AccountName: "微信支付", Description: "配送费"},
	}

	testCases := []struct {
		name            string
		results         []*models.RecognizedReceiptImageResult
		wantMerged      bool
		wantCount       int
		wantAmount      string
		wantDescription string
		wantOrderTotal  string
		wantTags        []string
	}{
		{
			name:            "explicit single order total repairs omitted fee",
			results:         splitOrderWithTotal,
			wantMerged:      true,
			wantCount:       1,
			wantAmount:      "31.60",
			wantDescription: "犀牛家猪排",
			wantOrderTotal:  "31.60",
			wantTags:        []string{"美团", "外卖"},
		},
		{
			name:            "fee rows sum together when total is omitted",
			results:         splitOrderWithoutTotal,
			wantMerged:      true,
			wantCount:       1,
			wantAmount:      "31.60",
			wantDescription: "犀牛家猪排",
			wantOrderTotal:  "",
		},
		{
			name: "order list is never merged",
			results: []*models.RecognizedReceiptImageResult{
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "20.00", AccountName: "微信支付", Description: "咖啡", PageType: "order_list"},
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "5.00", AccountName: "微信支付", Description: "配送费", PageType: "order_list"},
			},
			wantMerged: false,
			wantCount:  2,
		},
		{
			name: "different order times stay separate",
			results: []*models.RecognizedReceiptImageResult{
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "20.00", AccountName: "微信支付", Description: "咖啡"},
				{Type: "expense", Time: "2026-11-05 12:00:00", Amount: "5.00", AccountName: "微信支付", Description: "配送费"},
			},
			wantMerged: false,
			wantCount:  2,
		},
		{
			name: "different merchants stay separate",
			results: []*models.RecognizedReceiptImageResult{
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "20.00", AccountName: "微信支付", Description: "咖啡", PageType: "single_order", OrderTotal: "25.00", Merchant: "咖啡店"},
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "5.00", AccountName: "微信支付", Description: "配送费", PageType: "single_order", OrderTotal: "25.00", Merchant: "餐馆"},
			},
			wantMerged: false,
			wantCount:  2,
		},
		{
			name: "conflicting totals stay separate",
			results: []*models.RecognizedReceiptImageResult{
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "20.00", AccountName: "微信支付", Description: "咖啡", PageType: "single_order", OrderTotal: "25.00"},
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "5.00", AccountName: "微信支付", Description: "配送费", PageType: "single_order", OrderTotal: "25.01"},
			},
			wantMerged: false,
			wantCount:  2,
		},
		{
			name: "multiple delivery rows stay separate without explicit marker",
			results: []*models.RecognizedReceiptImageResult{
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "20.00", AccountName: "微信支付", Description: "咖啡"},
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "5.00", AccountName: "微信支付", Description: "配送费"},
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "6.00", AccountName: "微信支付", Description: "配送费"},
			},
			wantMerged: false,
			wantCount:  3,
		},
		{
			name: "fee rows without an item stay separate",
			results: []*models.RecognizedReceiptImageResult{
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "1.00", AccountName: "微信支付", Description: "打包费"},
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "4.60", AccountName: "微信支付", Description: "配送费"},
			},
			wantMerged: false,
			wantCount:  2,
		},
		{
			name: "mixed transaction types stay separate",
			results: []*models.RecognizedReceiptImageResult{
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "20.00", AccountName: "微信支付", Description: "咖啡", PageType: "single_order"},
				{Type: "income", Time: "2026-11-06 12:00:00", Amount: "5.00", AccountName: "微信支付", Description: "配送费", PageType: "single_order"},
			},
			wantMerged: false,
			wantCount:  2,
		},
		{
			name: "single result keeps current behavior",
			results: []*models.RecognizedReceiptImageResult{
				{Type: "expense", Time: "2026-11-06 12:00:00", Amount: "31.60", AccountName: "微信支付", Description: "犀牛家猪排", PageType: "single_order", OrderTotal: "31.60"},
			},
			wantMerged: false,
			wantCount:  1,
		},
	}

	for _, testCase := range testCases {
		actual, merged := mergeRecognizedSingleOrderResults(testCase.results)

		if merged != testCase.wantMerged {
			t.Errorf("%s: expected merged %v, but got %v", testCase.name, testCase.wantMerged, merged)
		}

		if len(actual) != testCase.wantCount {
			t.Errorf("%s: expected %d result(s), but got %d", testCase.name, testCase.wantCount, len(actual))
			continue
		}

		if !testCase.wantMerged {
			continue
		}

		if actual[0].Amount != testCase.wantAmount {
			t.Errorf("%s: expected amount %q, but got %q", testCase.name, testCase.wantAmount, actual[0].Amount)
		}

		if actual[0].Description != testCase.wantDescription {
			t.Errorf("%s: expected description %q, but got %q", testCase.name, testCase.wantDescription, actual[0].Description)
		}

		if actual[0].OrderTotal != testCase.wantOrderTotal {
			t.Errorf("%s: expected order total %q, but got %q", testCase.name, testCase.wantOrderTotal, actual[0].OrderTotal)
		}

		if len(actual[0].TagNames) != len(testCase.wantTags) {
			t.Errorf("%s: expected tags %v, but got %v", testCase.name, testCase.wantTags, actual[0].TagNames)
			continue
		}

		for i, tag := range testCase.wantTags {
			if actual[0].TagNames[i] != tag {
				t.Errorf("%s: expected tags %v, but got %v", testCase.name, testCase.wantTags, actual[0].TagNames)
				break
			}
		}
	}
}
