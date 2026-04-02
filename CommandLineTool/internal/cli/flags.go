package cli

import (
	"flag"
	"io"
	"strings"
)

func parseInterspersedFlags(fs *flag.FlagSet, args []string, valueFlags ...string) ([]string, error) {
	fs.SetOutput(io.Discard)

	valueFlagSet := make(map[string]struct{}, len(valueFlags))
	for _, name := range valueFlags {
		valueFlagSet[name] = struct{}{}
	}

	flagArgs := make([]string, 0, len(args))
	positionals := make([]string, 0, len(args))

	for index := 0; index < len(args); index++ {
		token := args[index]
		if token == "--" {
			positionals = append(positionals, args[index+1:]...)
			break
		}

		if !strings.HasPrefix(token, "-") || token == "-" {
			positionals = append(positionals, token)
			continue
		}

		flagArgs = append(flagArgs, token)
		name := trimFlagName(token)
		if name == "" {
			continue
		}
		if _, ok := valueFlagSet[name]; !ok || strings.Contains(token, "=") {
			continue
		}
		if index+1 >= len(args) || looksLikeFlag(args[index+1]) {
			return nil, cliError{message: "missing value for --" + name}
		}

		flagArgs = append(flagArgs, args[index+1])
		index++
	}

	if err := fs.Parse(flagArgs); err != nil {
		return nil, cliError{message: strings.TrimSpace(err.Error())}
	}

	return positionals, nil
}

func trimFlagName(token string) string {
	name := strings.TrimLeft(token, "-")
	if name == "" {
		return ""
	}
	if index := strings.Index(name, "="); index >= 0 {
		return name[:index]
	}
	return name
}

func looksLikeFlag(token string) bool {
	return strings.HasPrefix(token, "-") && token != "-"
}
