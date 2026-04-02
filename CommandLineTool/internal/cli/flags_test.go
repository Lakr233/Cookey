package cli

import (
	"flag"
	"testing"
)

func TestParseInterspersedFlagsAllowsFlagsAfterPositionals(t *testing.T) {
	fs := flag.NewFlagSet("test", flag.ContinueOnError)
	watch := fs.Bool("watch", false, "")
	jsonOutput := fs.Bool("json", false, "")

	positionals, err := parseInterspersedFlags(fs, []string{"rid-123", "--watch", "--json"})
	if err != nil {
		t.Fatalf("parseInterspersedFlags() error = %v", err)
	}
	if len(positionals) != 1 || positionals[0] != "rid-123" {
		t.Fatalf("positionals = %v, want [rid-123]", positionals)
	}
	if !*watch || !*jsonOutput {
		t.Fatalf("watch/json = (%t, %t), want both true", *watch, *jsonOutput)
	}
}

func TestParseInterspersedFlagsSupportsValueFlags(t *testing.T) {
	fs := flag.NewFlagSet("test", flag.ContinueOnError)
	server := fs.String("server", "", "")

	positionals, err := parseInterspersedFlags(fs, []string{"https://example.com/login", "--server", "https://api.cookey.sh"}, "server")
	if err != nil {
		t.Fatalf("parseInterspersedFlags() error = %v", err)
	}
	if len(positionals) != 1 || positionals[0] != "https://example.com/login" {
		t.Fatalf("positionals = %v, want target URL", positionals)
	}
	if *server != "https://api.cookey.sh" {
		t.Fatalf("server = %q, want https://api.cookey.sh", *server)
	}
}

func TestParseInterspersedFlagsRejectsMissingValue(t *testing.T) {
	fs := flag.NewFlagSet("test", flag.ContinueOnError)
	fs.String("server", "", "")

	_, err := parseInterspersedFlags(fs, []string{"--server", "--json"}, "server")
	if err == nil {
		t.Fatal("parseInterspersedFlags() error = nil, want error")
	}
}
