package cli

import (
	"fmt"
	"os"
	"strings"
)

const defaultServerURL = "https://api.cookey.sh"

type cliError struct {
	message string
}

func (e cliError) Error() string {
	return e.message
}

func Run(args []string) error {
	if len(args) == 0 {
		printRootUsage()
		return nil
	}

	switch args[0] {
	case "request":
		return runRequest(args[1:])
	case "session":
		return runSession(args[1:])
	case "config":
		return runConfig(args[1:])
	case "login":
		return runLegacyLogin(args[1:])
	case "status":
		warnDeprecatedCommand("cookey status", "cookey request status")
		return runRequestStatus(args[1:])
	case "export":
		warnDeprecatedCommand("cookey export", "cookey session export")
		return runSessionExport(args[1:])
	case "list":
		warnDeprecatedCommand("cookey list", "cookey session list")
		return runSessionList(args[1:])
	case "delete":
		warnDeprecatedCommand("cookey delete", "cookey session delete")
		return runSessionDelete(args[1:])
	case "clean":
		warnDeprecatedCommand("cookey clean", "cookey session clean")
		return runSessionClean(args[1:])
	case "__daemon":
		return handleDaemon(args[1:])
	case "help", "-h", "--help":
		return runHelp(args[1:])
	default:
		return cliError{message: "unknown command: " + args[0]}
	}
}

func runHelp(args []string) error {
	if len(args) == 0 {
		printRootUsage()
		return nil
	}

	switch args[0] {
	case "request":
		printRequestUsage()
	case "session":
		printSessionUsage()
	case "config":
		printConfigUsage()
	default:
		printRootUsage()
	}
	return nil
}

func runRequest(args []string) error {
	if len(args) == 0 {
		printRequestUsage()
		return nil
	}

	switch args[0] {
	case "start":
		return runRequestCapture(args[1:], requestModeStart)
	case "refresh":
		return runRequestCapture(args[1:], requestModeRefresh)
	case "status":
		return runRequestStatus(args[1:])
	case "help", "-h", "--help":
		printRequestUsage()
		return nil
	default:
		return cliError{message: "unknown request command: " + args[0]}
	}
}

func runSession(args []string) error {
	if len(args) == 0 {
		printSessionUsage()
		return nil
	}

	switch args[0] {
	case "export":
		return runSessionExport(args[1:])
	case "list":
		return runSessionList(args[1:])
	case "delete":
		return runSessionDelete(args[1:])
	case "clean":
		return runSessionClean(args[1:])
	case "help", "-h", "--help":
		printSessionUsage()
		return nil
	default:
		return cliError{message: "unknown session command: " + args[0]}
	}
}

func runConfig(args []string) error {
	if len(args) == 0 {
		printConfigUsage()
		return nil
	}

	switch args[0] {
	case "get":
		return runConfigGet(args[1:])
	case "set":
		return runConfigSet(args[1:])
	case "help", "-h", "--help":
		printConfigUsage()
		return nil
	default:
		return cliError{message: "unknown config command: " + args[0]}
	}
}

func runLegacyLogin(args []string) error {
	if hasLongFlag(args, "update") {
		warnDeprecatedCommand("cookey login --update", "cookey request refresh")
		return runRequestCapture(removeLongFlag(args, "update"), requestModeRefresh)
	}

	warnDeprecatedCommand("cookey login", "cookey request start")
	return runRequestCapture(args, requestModeStart)
}

func warnDeprecatedCommand(oldCommand string, newCommand string) {
	fmt.Fprintf(os.Stderr, "warning: `%s` is deprecated; use `%s`\n", oldCommand, newCommand)
}

func hasLongFlag(args []string, name string) bool {
	longForm := "--" + name
	prefix := longForm + "="
	for _, arg := range args {
		if arg == longForm || strings.HasPrefix(arg, prefix) {
			return true
		}
	}
	return false
}

func removeLongFlag(args []string, name string) []string {
	filtered := make([]string, 0, len(args))
	longForm := "--" + name
	prefix := longForm + "="

	for _, arg := range args {
		if arg == longForm || strings.HasPrefix(arg, prefix) {
			continue
		}
		filtered = append(filtered, arg)
	}

	return filtered
}
