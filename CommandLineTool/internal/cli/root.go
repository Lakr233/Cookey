package cli

import "fmt"

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
	case "__daemon":
		return handleDaemon(args[1:])
	case "version", "-v", "--version":
		fmt.Println(Version)
		return nil
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

