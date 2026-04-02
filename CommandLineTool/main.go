package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"cookey/internal/config"
	"cookey/internal/crypto"
	"cookey/internal/daemon"
	"cookey/internal/models"
	"cookey/internal/qrcode"
	"cookey/internal/relay"
)

type cliError struct {
	message string
}

const defaultServerURL = "https://api.cookey.sh"

func (e cliError) Error() string {
	return e.message
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "error: %s\n", err.Error())
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		printUsage()
		return nil
	}

	command := args[0]
	arguments := args[1:]

	switch command {
	case "login":
		return handleLogin(arguments)
	case "export":
		return handleExport(arguments)
	case "list":
		return handleList(arguments)
	case "delete":
		return handleDelete(arguments)
	case "clean":
		return handleClean(arguments)
	case "status":
		return handleStatus(arguments)
	case "__daemon":
		return handleDaemon(arguments)
	case "help", "--help", "-h":
		printUsage()
		return nil
	default:
		return cliError{message: "Unknown command: " + command}
	}
}

func handleLogin(arguments []string) error {
	if len(arguments) == 0 || strings.HasPrefix(arguments[0], "-") {
		return cliError{message: "Usage: cookey login <target_url> [--server URL] [--timeout 600] [--qr] [--json] [--no-detach] [--update]"}
	}

	targetURL := arguments[0]
	flags, err := parseFlags(arguments[1:])
	if err != nil {
		return err
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	serverURL := firstNonEmpty(flags["server"], stringPtrValue(context.Config.DefaultServer), defaultServerURL)
	timeoutSeconds, err := parsePositiveIntFlag("timeout", flags["timeout"], context.Config.TimeoutSeconds, 600)
	if err != nil {
		return err
	}

	rid, err := crypto.GenerateRequestID()
	if err != nil {
		return err
	}

	createdAt := models.NewISO8601Time(time.Now())
	cliPublicKey, err := crypto.X25519PublicKeyBase64(context.Keypair)
	if err != nil {
		return err
	}
	requestSecret, err := crypto.GenerateRequestSecret()
	if err != nil {
		return err
	}

	manifest := models.LoginManifest{
		RequestType:       "login",
		RID:               rid,
		TargetURL:         targetURL,
		ServerURL:         serverURL,
		CLIPublicKey:      cliPublicKey,
		DeviceID:          context.DeviceIdentifier,
		DeviceFingerprint: context.DeviceFingerprint,
		CreatedAt:         createdAt,
		ExpiresAt:         models.NewISO8601Time(createdAt.Time.Add(time.Duration(timeoutSeconds) * time.Second)),
		RequestSecret:     requestSecret,
	}
	manifest.RequestProof, err = crypto.ComputeRequestProof(manifest, manifest.RequestSecret)
	if err != nil {
		return err
	}

	var seedEnvelope *models.EncryptedSessionEnvelope
	if flags["update"] != "" {
		latestRID, err := config.LatestSessionForTarget(context.Paths, targetURL)
		if err != nil {
			return err
		}
		if latestRID == "" {
			return cliError{message: "No previous session found for this target. Run a normal login first."}
		}

		previousSession, err := config.ReadJSON[models.SessionFile](context.Paths.SessionPath(latestRID))
		if err != nil {
			return err
		}
		deviceInfo := previousSession.DeviceInfo
		if deviceInfo == nil {
			fallbackDeviceInfo, _, err := config.LatestDeviceInfoForTarget(context.Paths, targetURL)
			if err != nil {
				return err
			}
			deviceInfo = fallbackDeviceInfo
		}

		if deviceInfo != nil {
			manifest.RequestType = "refresh"
			manifest.RequestProof, err = crypto.ComputeRequestProof(manifest, manifest.RequestSecret)
			if err != nil {
				return err
			}

			seedPayload, err := encodeJSON(models.SeedSessionPayload{
				Cookies: previousSession.Cookies,
				Origins: previousSession.Origins,
				Request: &models.SeedRequestPayload{
					RID:           manifest.RID,
					ServerURL:     manifest.ServerURL,
					TargetURL:     manifest.TargetURL,
					CLIPublicKey:  manifest.CLIPublicKey,
					DeviceID:      manifest.DeviceID,
					RequestType:   manifest.RequestType,
					ExpiresAt:     manifest.ExpiresAt,
					RequestProof:  manifest.RequestProof,
					RequestSecret: manifest.RequestSecret,
				},
			}, false)
			if err != nil {
				return err
			}

			envelope, err := crypto.EncryptSessionEnvelope(seedPayload, deviceInfo.PublicKey)
			if err != nil {
				return err
			}

			manifest.APNToken = deviceInfo.APNToken
			manifest.APNEnvironment = deviceInfo.APNEnvironment
			seedEnvelope = &envelope
		} else {
			fmt.Println("  Note: Previous session has no device info. Push notification will not be sent.")
			fmt.Println("        The session will still be sent via QR code. Complete a full login to enable push.")
			fmt.Println()
		}
	}

	client, err := relay.NewClient(serverURL)
	if err != nil {
		return cliError{message: "Invalid --server value: " + serverURL}
	}
	pairKey, err := client.Register(manifest)
	if err != nil {
		return err
	}
	if seedEnvelope != nil {
		if err := client.UploadSeedSession(rid, *seedEnvelope); err != nil {
			return err
		}
	}

	deepLink := qrcode.DeepLink(manifest)
	qrLink := deepLink
	if pairKey != "" {
		qrLink = qrcode.PairKeyDeepLink(pairKey, serverURL, manifest.RequestSecret)
	}
	showQR := flags["qr"] != ""
	qrText := ""
	if showQR {
		qrText = qrcode.Render(qrLink)
	}
	jsonOutput := flags["json"] != ""
	noDetach := flags["no-detach"] != ""

	if noDetach {
		output := models.LoginOutput{
			RID:             rid,
			ServerURL:       serverURL,
			TargetURL:       targetURL,
			TimeoutSeconds:  timeoutSeconds,
			DaemonPID:       int32(os.Getpid()),
			DeepLink:        deepLink,
			PairKey:         pairKey,
			PairKeyDeepLink: qrLink,
			QRText:          qrText,
			ShowQR:          showQR,
			Detached:        false,
		}
		if err := emitLoginOutput(output, jsonOutput); err != nil {
			return err
		}
		daemon.RunInline(context, manifest, timeoutSeconds)
		if !jsonOutput {
			fmt.Println("\n  Session completed.")
			snapshot, err := resolveStatus(rid, context)
			if err == nil {
				fmt.Println(renderSnapshot(snapshot))
			}
		}
		return nil
	}

	daemonPID, err := daemon.LaunchDetached(context, manifest, timeoutSeconds)
	if err != nil {
		return err
	}

	output := models.LoginOutput{
		RID:             rid,
		ServerURL:       serverURL,
		TargetURL:       targetURL,
		TimeoutSeconds:  timeoutSeconds,
		DaemonPID:       daemonPID,
		DeepLink:        deepLink,
		PairKey:         pairKey,
		PairKeyDeepLink: qrLink,
		QRText:          qrText,
		ShowQR:          showQR,
		Detached:        true,
	}
	return emitLoginOutput(output, jsonOutput)
}

func handleStatus(arguments []string) error {
	flags, err := parseFlags(arguments)
	if err != nil {
		return err
	}

	jsonOutput := flags["json"] != ""
	watch := flags["watch"] != ""
	latest := flags["latest"] != ""
	ridArgument := firstPositional(arguments)

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	if ridArgument != "" && latest {
		return cliError{message: "Use either [rid] or --latest, not both."}
	}
	if watch && ridArgument == "" && !latest {
		return cliError{message: "cookey status --watch requires a rid or --latest."}
	}

	if ridArgument == "" && !latest {
		summary, err := latestSummary(context)
		if err != nil {
			return err
		}
		return emit(summary, jsonOutput)
	}

	rid := ridArgument
	if rid == "" {
		rid, err = config.LatestRID(context.Paths)
		if err != nil {
			return err
		}
		if rid == "" {
			return cliError{message: "No local requests found."}
		}
	}

	if watch {
		return watchStatus(rid, context, jsonOutput)
	}

	snapshot, err := resolveStatus(rid, context)
	if err != nil {
		return err
	}
	return emit(snapshot, jsonOutput)
}

func handleExport(arguments []string) error {
	flags, err := parseFlags(arguments)
	if err != nil {
		return err
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	rid := firstPositional(arguments)
	if rid == "" {
		rid, err = config.LatestSessionRID(context.Paths)
		if err != nil {
			return err
		}
		if rid == "" {
			return cliError{message: "No local sessions found."}
		}
	}

	sessionPath := context.Paths.SessionPath(rid)
	if _, err := os.Stat(sessionPath); err != nil {
		descriptorPath := context.Paths.DaemonPath(rid)
		if descriptor, descriptorErr := config.ReadJSON[models.DaemonDescriptor](descriptorPath); descriptorErr == nil {
			message := fmt.Sprintf("Session not found for rid: %s (status: %s", rid, descriptor.Status)
			if descriptor.ErrorMessage != nil && *descriptor.ErrorMessage != "" {
				message += ", error: " + *descriptor.ErrorMessage
			}
			message += ")"
			return cliError{message: message}
		}
		return cliError{message: "Session not found for rid: " + rid}
	}

	session, err := config.ReadJSON[models.SessionFile](sessionPath)
	if err != nil {
		return err
	}

	storageState := models.PlaywrightStorageState{
		Cookies: session.Cookies,
		Origins: session.Origins,
	}

	data, err := encodeJSON(storageState, flags["pretty"] != "")
	if err != nil {
		return err
	}

	if outputPath := flags["out"]; outputPath != "" {
		target := outputPath
		if !filepath.IsAbs(target) {
			cwd, err := os.Getwd()
			if err != nil {
				return err
			}
			target = filepath.Join(cwd, target)
		}
		return os.WriteFile(target, data, 0o644)
	}

	if _, err := os.Stdout.Write(data); err != nil {
		return err
	}
	if len(data) == 0 || data[len(data)-1] != '\n' {
		_, _ = os.Stdout.Write([]byte{'\n'})
	}
	return nil
}

func handleList(arguments []string) error {
	flags, err := parseFlags(arguments)
	if err != nil {
		return err
	}
	if positional := firstPositional(arguments); positional != "" {
		return cliError{message: "Usage: cookey list [--json]"}
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	rids, err := config.ListLocalRIDs(context.Paths)
	if err != nil {
		return err
	}

	snapshots := make([]models.StatusSnapshot, 0, len(rids))
	for _, rid := range rids {
		snapshots = append(snapshots, config.StatusSnapshot(rid, context))
	}

	return emit(snapshots, flags["json"] != "")
}

func handleDelete(arguments []string) error {
	flags, err := parseFlags(arguments)
	if err != nil {
		return err
	}

	rid := firstPositional(arguments)
	if rid == "" {
		return cliError{message: "Usage: cookey delete <rid> [--json]"}
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	sessionDeleted, daemonDeleted, err := config.DeleteLocalRID(context.Paths, rid)
	if err != nil {
		switch {
		case errors.Is(err, os.ErrNotExist):
			return cliError{message: "No local request found for rid: " + rid}
		case errors.Is(err, config.ErrActiveRequest):
			return cliError{message: "Request is still active and cannot be deleted: " + rid}
		default:
			return err
		}
	}

	return emit(models.DeleteOutput{
		RID:            rid,
		SessionDeleted: sessionDeleted,
		DaemonDeleted:  daemonDeleted,
	}, flags["json"] != "")
}

func handleClean(arguments []string) error {
	flags, err := parseFlags(arguments)
	if err != nil {
		return err
	}
	if positional := firstPositional(arguments); positional != "" {
		return cliError{message: "Usage: cookey clean [--json]"}
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	rids, err := config.ListLocalRIDs(context.Paths)
	if err != nil {
		return err
	}

	deleted := make([]models.DeleteOutput, 0, len(rids))
	skipped := make([]models.StatusSnapshot, 0)
	for _, rid := range rids {
		sessionDeleted, daemonDeleted, err := config.DeleteLocalRID(context.Paths, rid)
		if err != nil {
			if errors.Is(err, config.ErrActiveRequest) {
				skipped = append(skipped, config.StatusSnapshot(rid, context))
				continue
			}
			return err
		}

		deleted = append(deleted, models.DeleteOutput{
			RID:            rid,
			SessionDeleted: sessionDeleted,
			DaemonDeleted:  daemonDeleted,
		})
	}

	return emit(models.CleanOutput{Deleted: deleted, Skipped: skipped}, flags["json"] != "")
}

func handleDaemon(arguments []string) error {
	if len(arguments) == 0 {
		return cliError{message: "Missing daemon payload."}
	}

	payload, err := daemon.DecodeLaunchPayload(arguments[0])
	if err != nil {
		return err
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	daemon.RunInline(context, payload.Manifest, payload.TimeoutSeconds)
	return nil
}

func latestSummary(context config.BootstrapContext) (models.StatusSummary, error) {
	var summary models.StatusSummary

	latestDaemon, err := config.LatestDaemon(context.Paths)
	if err != nil {
		return summary, err
	}
	if latestDaemon != nil {
		snapshot := config.StatusSnapshot(latestDaemon.RID, context)
		summary.LatestDaemon = &snapshot
	}

	latestSessionRID, err := config.LatestSessionRID(context.Paths)
	if err != nil {
		return summary, err
	}
	if latestSessionRID != "" {
		snapshot := config.StatusSnapshot(latestSessionRID, context)
		summary.LatestSession = &snapshot
	}

	return summary, nil
}

func watchStatus(rid string, context config.BootstrapContext, asJSON bool) error {
	var lastPrinted string

	for {
		snapshot, err := resolveStatus(rid, context)
		if err != nil {
			return err
		}

		rendered, err := render(snapshot, asJSON)
		if err != nil {
			return err
		}

		if rendered != lastPrinted {
			fmt.Println(rendered)
			lastPrinted = rendered
		}

		switch snapshot.Status {
		case models.CLIStatusReady, models.CLIStatusExpired, models.CLIStatusError, models.CLIStatusOrphaned, models.CLIStatusMissing:
			return nil
		default:
			time.Sleep(time.Second)
		}
	}
}

func resolveStatus(rid string, context config.BootstrapContext) (models.StatusSnapshot, error) {
	local := config.StatusSnapshot(rid, context)
	if local.Status != models.CLIStatusMissing {
		return local, nil
	}

	serverURL := firstNonEmpty(stringPtrValue(context.Config.DefaultServer), defaultServerURL)

	client, err := relay.NewClient(serverURL)
	if err != nil {
		return local, nil
	}

	remote, err := client.FetchStatus(rid)
	if err != nil {
		return models.StatusSnapshot{}, err
	}
	if remote == nil {
		return local, nil
	}

	status := models.CLIStatusMissing
	if remote.Status != nil {
		switch strings.ToLower(*remote.Status) {
		case "waiting", "pending":
			status = models.CLIStatusWaiting
		case "receiving":
			status = models.CLIStatusReceiving
		case "ready":
			status = models.CLIStatusReady
		case "expired", "delivered":
			status = models.CLIStatusExpired
		case "error":
			status = models.CLIStatusError
		}
	}

	return models.StatusSnapshot{
		RID:       valueOrDefault(remote.RID, rid),
		Status:    status,
		TargetURL: remote.TargetURL,
		UpdatedAt: remote.ExpiresAt,
		ServerURL: &serverURL,
	}, nil
}

func emitLoginOutput(output models.LoginOutput, asJSON bool) error {
	if asJSON {
		return emit(output, true)
	}

	fmt.Printf("❯ cookey login %s\n\n", output.TargetURL)
	fmt.Printf("  Registered  %s\n", output.RID)
	fmt.Printf("  Target URL  %s\n", output.TargetURL)
	expiresAt := time.Now().Add(time.Duration(output.TimeoutSeconds) * time.Second)
	fmt.Printf("  Expires in  %s (%s)\n\n", formatLoginTimeout(output.TimeoutSeconds), expiresAt.Format("15:04:05"))
	if output.ShowQR && output.QRText != "" {
		fmt.Print(output.QRText)
		if !strings.HasSuffix(output.QRText, "\n") {
			fmt.Println()
		}
	}
	if output.PairKey != "" {
		fmt.Printf("  Pair Key    %s-%s\n", output.PairKey[:4], output.PairKey[4:])
		fmt.Printf("  Deep Link   %s\n", output.PairKeyDeepLink)
	}
	if output.ShowQR {
		fmt.Println("  Scan or enter the pair key in the Cookey app to continue.")
	} else {
		fmt.Println("  Open the Cookey app and enter the pair key to continue.")
	}
	return nil
}

func emit(value any, asJSON bool) error {
	rendered, err := render(value, asJSON)
	if err != nil {
		return err
	}
	fmt.Println(rendered)
	return nil
}

func render(value any, asJSON bool) (string, error) {
	if asJSON {
		data, err := encodeJSON(value, true)
		if err != nil {
			return "", err
		}
		return strings.TrimRight(string(data), "\n"), nil
	}

	switch typed := value.(type) {
	case models.StatusSnapshot:
		return renderSnapshot(typed), nil
	case models.StatusSummary:
		return renderSummary(typed), nil
	case []models.StatusSnapshot:
		return renderSnapshotList(typed), nil
	case models.DeleteOutput:
		return renderDeleteOutput(typed), nil
	case models.CleanOutput:
		return renderCleanOutput(typed), nil
	default:
		return fmt.Sprintf("%v", typed), nil
	}
}

func renderSnapshotList(snapshots []models.StatusSnapshot) string {
	if len(snapshots) == 0 {
		return "No local requests found."
	}

	parts := make([]string, 0, len(snapshots))
	for _, snapshot := range snapshots {
		parts = append(parts, renderSnapshot(snapshot))
	}
	return strings.Join(parts, "\n\n")
}

func renderSnapshot(snapshot models.StatusSnapshot) string {
	lines := []string{
		"rid: " + snapshot.RID,
		"status: " + string(snapshot.Status),
	}

	if snapshot.PID != nil {
		lines = append(lines, fmt.Sprintf("pid: %d", *snapshot.PID))
	}
	if snapshot.TargetURL != nil {
		lines = append(lines, "target_url: "+*snapshot.TargetURL)
	}
	if snapshot.SessionPath != nil {
		lines = append(lines, "session_path: "+*snapshot.SessionPath)
	}
	if snapshot.UpdatedAt != nil {
		lines = append(lines, "updated_at: "+snapshot.UpdatedAt.Time.Format(time.RFC3339))
	}
	if snapshot.ServerURL != nil {
		lines = append(lines, "server_url: "+*snapshot.ServerURL)
	}
	if snapshot.ErrorMessage != nil {
		lines = append(lines, "error: "+*snapshot.ErrorMessage)
	}

	return strings.Join(lines, "\n")
}

func renderSummary(summary models.StatusSummary) string {
	lines := make([]string, 0, 4)
	if summary.LatestDaemon != nil {
		lines = append(lines, "latest_daemon:")
		lines = append(lines, renderSnapshot(*summary.LatestDaemon))
	}
	if summary.LatestSession != nil {
		lines = append(lines, "latest_session:")
		lines = append(lines, renderSnapshot(*summary.LatestSession))
	}
	if len(lines) == 0 {
		return "No local requests found."
	}
	return strings.Join(lines, "\n")
}

func deletedComponents(output models.DeleteOutput) []string {
	var parts []string
	if output.SessionDeleted {
		parts = append(parts, "session")
	}
	if output.DaemonDeleted {
		parts = append(parts, "daemon")
	}
	return parts
}

func renderDeleteOutput(output models.DeleteOutput) string {
	parts := deletedComponents(output)
	if len(parts) == 0 {
		return "rid: " + output.RID + "\ndeleted: none"
	}
	return "rid: " + output.RID + "\ndeleted: " + strings.Join(parts, ", ")
}

func renderCleanOutput(output models.CleanOutput) string {
	if len(output.Deleted) == 0 && len(output.Skipped) == 0 {
		return "No local requests found."
	}

	lines := make([]string, 0, len(output.Deleted)+len(output.Skipped)+2)
	if len(output.Deleted) > 0 {
		lines = append(lines, "deleted:")
		for _, item := range output.Deleted {
			parts := deletedComponents(item)
			lines = append(lines, "  "+item.RID+" ("+strings.Join(parts, ", ")+")")
		}
	}
	if len(output.Skipped) > 0 {
		lines = append(lines, "skipped_active:")
		for _, snapshot := range output.Skipped {
			lines = append(lines, "  "+snapshot.RID+" (status: "+string(snapshot.Status)+")")
		}
	}
	return strings.Join(lines, "\n")
}

func parseFlags(arguments []string) (map[string]string, error) {
	flags := map[string]string{}

	for i := 0; i < len(arguments); i++ {
		token := arguments[i]
		if !strings.HasPrefix(token, "--") {
			continue
		}

		flag := strings.TrimPrefix(token, "--")
		switch flag {
		case "json", "no-detach", "latest", "watch", "pretty", "update", "qr":
			flags[flag] = "true"
		case "server", "timeout", "out":
			if i+1 >= len(arguments) {
				return nil, cliError{message: "Missing value for --" + flag}
			}
			flags[flag] = arguments[i+1]
			i++
		default:
			return nil, cliError{message: "Unknown flag: --" + flag}
		}
	}

	return flags, nil
}

func parsePositiveIntFlag(name string, raw string, fallback *int, defaultValue int) (int, error) {
	if raw == "" {
		if fallback != nil {
			return *fallback, nil
		}
		return defaultValue, nil
	}

	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return 0, cliError{message: "Invalid --" + name + " value: " + raw}
	}
	return value, nil
}

func encodeJSON(value any, pretty bool) ([]byte, error) {
	if pretty {
		data, err := json.MarshalIndent(value, "", "  ")
		if err != nil {
			return nil, err
		}
		return append(data, '\n'), nil
	}
	return json.Marshal(value)
}

func firstPositional(arguments []string) string {
	for _, argument := range arguments {
		if !strings.HasPrefix(argument, "-") {
			return argument
		}
	}
	return ""
}

func stringPtrValue(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func valueOrDefault(value *string, fallback string) string {
	if value == nil || *value == "" {
		return fallback
	}
	return *value
}

func printUsage() {
	fmt.Println(`Usage:
  cookey login <target_url> [--server URL] [--timeout 600] [--qr] [--json] [--no-detach] [--update]
  cookey export [rid] [--out FILE] [--pretty]
  cookey status [rid] [--latest] [--watch] [--json]
  cookey list [--json]
  cookey delete <rid> [--json]
  cookey clean [--json]`)
}

func formatLoginTimeout(timeoutSeconds int) string {
	duration := time.Duration(timeoutSeconds) * time.Second
	hours := int(duration / time.Hour)
	duration -= time.Duration(hours) * time.Hour
	minutes := int(duration / time.Minute)
	duration -= time.Duration(minutes) * time.Minute
	seconds := int(duration / time.Second)

	if hours > 0 {
		return fmt.Sprintf("%dh %02dm %02ds", hours, minutes, seconds)
	}
	if minutes > 0 {
		return fmt.Sprintf("%dm %02ds", minutes, seconds)
	}
	return fmt.Sprintf("%ds", seconds)
}
