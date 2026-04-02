package cli

import "testing"

func TestCanonicalConfigKey(t *testing.T) {
	tests := map[string]string{
		"default-server":         "default-server",
		"default_server":         "default-server",
		"server":                 "default-server",
		"timeout":                "timeout-seconds",
		"timeout-seconds":        "timeout-seconds",
		"retention-days":         "session-retention-days",
		"session_retention_days": "session-retention-days",
	}

	for input, want := range tests {
		got, err := canonicalConfigKey(input)
		if err != nil {
			t.Fatalf("canonicalConfigKey(%q) error = %v", input, err)
		}
		if got != want {
			t.Fatalf("canonicalConfigKey(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestParsePositiveInt(t *testing.T) {
	value, err := parsePositiveInt("900", "timeout-seconds")
	if err != nil {
		t.Fatalf("parsePositiveInt() error = %v", err)
	}
	if value != 900 {
		t.Fatalf("parsePositiveInt() = %d, want 900", value)
	}

	if _, err := parsePositiveInt("0", "timeout-seconds"); err == nil {
		t.Fatal("parsePositiveInt(0) error = nil, want error")
	}
}
