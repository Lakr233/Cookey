package cli

import (
	"flag"
	"fmt"
	"strings"

	"cookey/internal/config"
	"cookey/internal/models"
	"cookey/internal/relay"
)

type configEntry struct {
	Key   string `json:"key"`
	Value any    `json:"value,omitempty"`
	IsSet bool   `json:"is_set"`
}

type configView struct {
	Entries []configEntry `json:"entries"`
}

type configSetResult struct {
	Key   string `json:"key"`
	Value any    `json:"value"`
}

func runConfigGet(args []string) error {
	fs := flag.NewFlagSet("config-get", flag.ContinueOnError)
	jsonOutput := fs.Bool("json", false, "")
	help := fs.Bool("help", false, "")

	positionals, err := parseInterspersedFlags(fs, args)
	if err != nil {
		return err
	}
	if *help {
		printConfigGetUsage()
		return nil
	}
	if len(positionals) > 1 {
		return cliError{message: configGetUsage()}
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	view, err := buildConfigView(context.Config, positionals)
	if err != nil {
		return err
	}
	return emit(view, *jsonOutput)
}

func runConfigSet(args []string) error {
	fs := flag.NewFlagSet("config-set", flag.ContinueOnError)
	jsonOutput := fs.Bool("json", false, "")
	help := fs.Bool("help", false, "")

	positionals, err := parseInterspersedFlags(fs, args)
	if err != nil {
		return err
	}
	if *help {
		printConfigSetUsage()
		return nil
	}
	if len(positionals) != 2 {
		return cliError{message: configSetUsage()}
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	key, value, err := applyConfigValue(&context.Config, positionals[0], positionals[1])
	if err != nil {
		return err
	}
	if err := config.WriteJSON(context.Paths.Config, context.Config, 0o600); err != nil {
		return err
	}

	return emit(configSetResult{Key: key, Value: value}, *jsonOutput)
}

func buildConfigView(appConfig models.AppConfig, positionals []string) (configView, error) {
	keys := []string{"default-server", "timeout-seconds", "session-retention-days"}
	if len(positionals) == 1 {
		key, err := canonicalConfigKey(positionals[0])
		if err != nil {
			return configView{}, err
		}
		keys = []string{key}
	}

	entries := make([]configEntry, 0, len(keys))
	for _, key := range keys {
		value, isSet := lookupConfigValue(appConfig, key)
		entries = append(entries, configEntry{
			Key:   key,
			Value: value,
			IsSet: isSet,
		})
	}

	return configView{Entries: entries}, nil
}

func applyConfigValue(appConfig *models.AppConfig, rawKey string, rawValue string) (string, any, error) {
	key, err := canonicalConfigKey(rawKey)
	if err != nil {
		return "", nil, err
	}

	switch key {
	case "default-server":
		if _, err := relay.NewClient(rawValue); err != nil {
			return "", nil, cliError{message: "invalid default-server value: " + rawValue}
		}
		appConfig.DefaultServer = stringPtr(rawValue)
		return key, rawValue, nil
	case "timeout-seconds":
		value, err := parsePositiveInt(rawValue, "timeout-seconds")
		if err != nil {
			return "", nil, err
		}
		appConfig.TimeoutSeconds = &value
		return key, value, nil
	case "session-retention-days":
		value, err := parsePositiveInt(rawValue, "session-retention-days")
		if err != nil {
			return "", nil, err
		}
		appConfig.SessionRetentionDays = &value
		return key, value, nil
	default:
		return "", nil, cliError{message: "unsupported config key: " + rawKey}
	}
}

func lookupConfigValue(appConfig models.AppConfig, key string) (any, bool) {
	switch key {
	case "default-server":
		if appConfig.DefaultServer == nil {
			return nil, false
		}
		return *appConfig.DefaultServer, true
	case "timeout-seconds":
		if appConfig.TimeoutSeconds == nil {
			return nil, false
		}
		return *appConfig.TimeoutSeconds, true
	case "session-retention-days":
		if appConfig.SessionRetentionDays == nil {
			return nil, false
		}
		return *appConfig.SessionRetentionDays, true
	default:
		return nil, false
	}
}

func canonicalConfigKey(raw string) (string, error) {
	normalized := strings.ToLower(strings.TrimSpace(raw))
	normalized = strings.ReplaceAll(normalized, "_", "-")

	switch normalized {
	case "default-server", "server":
		return "default-server", nil
	case "timeout-seconds", "timeout":
		return "timeout-seconds", nil
	case "session-retention-days", "retention-days":
		return "session-retention-days", nil
	default:
		return "", cliError{message: fmt.Sprintf("unknown config key: %s", raw)}
	}
}

func parsePositiveInt(raw string, name string) (int, error) {
	var value int
	if _, err := fmt.Sscanf(raw, "%d", &value); err != nil || value <= 0 || fmt.Sprintf("%d", value) != raw {
		return 0, cliError{message: "invalid " + name + " value: " + raw}
	}
	return value, nil
}
