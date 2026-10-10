package api

import (
	"testing"

	"github.com/mayswind/ezbookkeeping/pkg/models"
)

func newTestAccountMap(names []string) map[string]*models.Account {
	accountMap := make(map[string]*models.Account)

	for i := 0; i < len(names); i++ {
		accountMap[names[i]] = &models.Account{Name: names[i]}
	}

	return accountMap
}

func TestMatchAccountByChannelKeywords(t *testing.T) {
	accountMap := newTestAccountMap([]string{"微信零钱", "支付宝", "招行卡", "现金"})

	testCases := []struct {
		name     string
		expected string // empty means no match
	}{
		{"微信支付", "微信零钱"},
		{"微信", "微信零钱"},
		{"零钱通", "微信零钱"},
		{"WeChat Pay", "微信零钱"},
		{"支付宝", "支付宝"},
		{"余额宝", "支付宝"},
		{"花呗", "支付宝"},
		{"现金", "现金"},
		{"招商银行", ""}, // bank not in any keyword group, ambiguous with 招行卡
		{"京东白条", ""},
	}

	for _, testCase := range testCases {
		account := matchAccountByChannelKeywords(testCase.name, accountMap)

		var actual string
		if account != nil {
			actual = account.Name
		}

		if actual != testCase.expected {
			t.Errorf("matchAccountByChannelKeywords(%q) = %q, expected %q", testCase.name, actual, testCase.expected)
		}
	}
}

func TestMatchAccountByChannelKeywordsAmbiguous(t *testing.T) {
	// two accounts in the wechat channel must not be auto-matched
	accountMap := newTestAccountMap([]string{"微信零钱", "微信银行卡"})
	account := matchAccountByChannelKeywords("微信支付", accountMap)

	if account != nil {
		t.Errorf("expected no match for ambiguous wechat accounts, got %q", account.Name)
	}
}

func TestMatchAccountByCommonSubstring(t *testing.T) {
	accountMap := newTestAccountMap([]string{"招商银行储蓄卡", "工商银行卡"})

	testCases := []struct {
		name     string
		expected string
	}{
		{"招商银行", "招商银行储蓄卡"},
		{"招商银行信用卡还款", "招商银行储蓄卡"},
		{"浦发银行", ""}, // only shares 1 rune (银行) with both, no unique best
	}

	for _, testCase := range testCases {
		account := matchAccountByCommonSubstring(testCase.name, accountMap)

		var actual string
		if account != nil {
			actual = account.Name
		}

		if actual != testCase.expected {
			t.Errorf("matchAccountByCommonSubstring(%q) = %q, expected %q", testCase.name, actual, testCase.expected)
		}
	}
}

func TestLongestCommonSubstringLength(t *testing.T) {
	testCases := []struct {
		a        string
		b        string
		expected int
	}{
		{"", "微信", 0},
		{"微信支付", "微信零钱", 2},
		{"招商银行", "招商银行储蓄卡", 4},
		{"abc", "abd", 2},
		{"支付宝", "微信", 0},
	}

	for _, testCase := range testCases {
		actual := longestCommonSubstringLength(testCase.a, testCase.b)

		if actual != testCase.expected {
			t.Errorf("longestCommonSubstringLength(%q, %q) = %d, expected %d", testCase.a, testCase.b, actual, testCase.expected)
		}
	}
}
