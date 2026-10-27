package api

import "testing"

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
