package cli

import "fmt"

func printRootUsage() {
	fmt.Println(rootUsage())
}

func printRequestUsage() {
	fmt.Println(requestUsage())
}

func printSessionUsage() {
	fmt.Println(sessionUsage())
}

func printConfigUsage() {
	fmt.Println(configUsage())
}

func printRequestCommandUsage(mode requestMode) {
	fmt.Println(requestCommandUsage(mode))
}

func printRequestStatusUsage() {
	fmt.Println(requestStatusUsage())
}

func printSessionExportUsage() {
	fmt.Println(sessionExportUsage())
}

func printSessionListUsage() {
	fmt.Println(sessionListUsage())
}

func printSessionDeleteUsage() {
	fmt.Println(sessionDeleteUsage())
}

func printSessionCleanUsage() {
	fmt.Println(sessionCleanUsage())
}

func printConfigGetUsage() {
	fmt.Println(configGetUsage())
}

func printConfigSetUsage() {
	fmt.Println(configSetUsage())
}

func rootUsage() string {
	return `Usage:
  cookey request start <target_url> [--server URL] [--timeout SECONDS] [--qr] [--json] [--attach]
  cookey request refresh <target_url> [--server URL] [--timeout SECONDS] [--qr] [--json] [--attach]
  cookey request status [rid] [--latest] [--watch] [--json]
  cookey session export [rid] [--latest] [--out FILE] [--pretty]
  cookey session list [--json]
  cookey session delete <rid> [--json]
  cookey session clean [--json]
  cookey config get [key] [--json]
  cookey config set <key> <value> [--json]

Legacy aliases:
  cookey login            -> cookey request start
  cookey status           -> cookey request status
  cookey export           -> cookey session export
  cookey list             -> cookey session list
  cookey delete           -> cookey session delete
  cookey clean            -> cookey session clean`
}

func requestUsage() string {
	return `Usage:
  cookey request start <target_url> [--server URL] [--timeout SECONDS] [--qr] [--json] [--attach]
  cookey request refresh <target_url> [--server URL] [--timeout SECONDS] [--qr] [--json] [--attach]
  cookey request status [rid] [--latest] [--watch] [--json]`
}

func requestCommandUsage(mode requestMode) string {
	command := "start"
	if mode == requestModeRefresh {
		command = "refresh"
	}
	return fmt.Sprintf("Usage:\n  cookey request %s <target_url> [--server URL] [--timeout SECONDS] [--qr] [--json] [--attach]", command)
}

func requestStatusUsage() string {
	return "Usage:\n  cookey request status [rid] [--latest] [--watch] [--json]"
}

func sessionUsage() string {
	return `Usage:
  cookey session export [rid] [--latest] [--out FILE] [--pretty]
  cookey session list [--json]
  cookey session delete <rid> [--json]
  cookey session clean [--json]`
}

func sessionExportUsage() string {
	return "Usage:\n  cookey session export [rid] [--latest] [--out FILE] [--pretty]"
}

func sessionListUsage() string {
	return "Usage:\n  cookey session list [--json]"
}

func sessionDeleteUsage() string {
	return "Usage:\n  cookey session delete <rid> [--json]"
}

func sessionCleanUsage() string {
	return "Usage:\n  cookey session clean [--json]"
}

func configUsage() string {
	return `Usage:
  cookey config get [key] [--json]
  cookey config set <key> <value> [--json]

Keys:
  default-server
  timeout-seconds
  session-retention-days`
}

func configGetUsage() string {
	return "Usage:\n  cookey config get [key] [--json]"
}

func configSetUsage() string {
	return "Usage:\n  cookey config set <key> <value> [--json]"
}
