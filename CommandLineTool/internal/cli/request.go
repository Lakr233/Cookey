package cli

import (
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"cookey/internal/config"
	"cookey/internal/crypto"
	"cookey/internal/daemon"
	"cookey/internal/models"
	"cookey/internal/qrcode"
	"cookey/internal/relay"
)

type requestMode string

const (
	requestModeStart   requestMode = "start"
	requestModeRefresh requestMode = "refresh"
)

func runRequestCapture(args []string, mode requestMode) error {
	fs := flag.NewFlagSet("request-capture", flag.ContinueOnError)
	server := fs.String("server", "", "")
	timeout := fs.Int("timeout", 0, "")
	qr := fs.Bool("qr", false, "")
	jsonOutput := fs.Bool("json", false, "")
	attach := fs.Bool("attach", false, "")
	noDetach := fs.Bool("no-detach", false, "")
	help := fs.Bool("help", false, "")

	positionals, err := parseInterspersedFlags(fs, args, "server", "timeout")
	if err != nil {
		return err
	}
	if *help {
		printRequestCommandUsage(mode)
		return nil
	}
	if len(positionals) != 1 {
		return cliError{message: requestCommandUsage(mode)}
	}

	if *noDetach {
		warnDeprecatedCommand("--no-detach", "--attach")
		*attach = true
	}

	targetURL := positionals[0]
	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	serverURL := firstNonEmpty(*server, stringPtrValue(context.Config.DefaultServer), defaultServerURL)
	timeoutSeconds, err := resolvePositiveInt(*timeout, context.Config.TimeoutSeconds, 600, "timeout")
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
		RequestType:       requestType(mode),
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
	if mode == requestModeRefresh {
		seedEnvelope, err = buildSeedEnvelope(context, &manifest, targetURL)
		if err != nil {
			return err
		}
	}

	client, err := relay.NewClient(serverURL)
	if err != nil {
		return cliError{message: "invalid --server value: " + serverURL}
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

	qrText := ""
	if *qr {
		qrText = qrcode.Render(qrLink)
	}

	output := models.LoginOutput{
		RID:             rid,
		ServerURL:       serverURL,
		TargetURL:       targetURL,
		TimeoutSeconds:  timeoutSeconds,
		PairKey:         pairKey,
		PairKeyDeepLink: qrLink,
		DeepLink:        deepLink,
		QRText:          qrText,
		ShowQR:          *qr,
		Detached:        !*attach,
	}

	if *attach {
		output.DaemonPID = int32(os.Getpid())
		if err := emitLoginOutput(output, mode, *jsonOutput); err != nil {
			return err
		}
		daemon.RunInline(context, manifest, timeoutSeconds)
		if !*jsonOutput {
			fmt.Println("\n  Session completed.")
			snapshot, statusErr := resolveStatus(rid, context)
			if statusErr == nil {
				fmt.Println(renderSnapshot(snapshot))
			}
		}
		return nil
	}

	daemonPID, err := daemon.LaunchDetached(context, manifest, timeoutSeconds)
	if err != nil {
		return err
	}
	output.DaemonPID = daemonPID
	return emitLoginOutput(output, mode, *jsonOutput)
}

func runRequestStatus(args []string) error {
	fs := flag.NewFlagSet("request-status", flag.ContinueOnError)
	jsonOutput := fs.Bool("json", false, "")
	watch := fs.Bool("watch", false, "")
	latest := fs.Bool("latest", false, "")
	help := fs.Bool("help", false, "")

	positionals, err := parseInterspersedFlags(fs, args)
	if err != nil {
		return err
	}
	if *help {
		printRequestStatusUsage()
		return nil
	}
	if len(positionals) > 1 {
		return cliError{message: requestStatusUsage()}
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	rid := ""
	if len(positionals) == 1 {
		rid = positionals[0]
	}
	if rid != "" && *latest {
		return cliError{message: "use either [rid] or --latest, not both"}
	}
	if *watch && rid == "" && !*latest {
		return cliError{message: "cookey request status --watch requires a rid or --latest"}
	}

	if rid == "" && !*latest {
		summary, err := latestSummary(context)
		if err != nil {
			return err
		}
		return emit(summary, *jsonOutput)
	}

	if rid == "" {
		rid, err = config.LatestRID(context.Paths)
		if err != nil {
			return err
		}
		if rid == "" {
			return cliError{message: "no local requests found"}
		}
	}

	if *watch {
		return watchStatus(rid, context, *jsonOutput)
	}

	snapshot, err := resolveStatus(rid, context)
	if err != nil {
		return err
	}
	return emit(snapshot, *jsonOutput)
}

func handleDaemon(args []string) error {
	if len(args) == 0 {
		return cliError{message: "missing daemon payload"}
	}

	payload, err := daemon.DecodeLaunchPayload(args[0])
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

func buildSeedEnvelope(context config.BootstrapContext, manifest *models.LoginManifest, targetURL string) (*models.EncryptedSessionEnvelope, error) {
	latestRID, err := config.LatestSessionForTarget(context.Paths, targetURL)
	if err != nil {
		return nil, err
	}
	if latestRID == "" {
		return nil, cliError{message: "no previous session found for this target; run `cookey request start` first"}
	}

	previousSession, err := config.ReadJSON[models.SessionFile](context.Paths.SessionPath(latestRID))
	if err != nil {
		return nil, err
	}

	deviceInfo := previousSession.DeviceInfo
	if deviceInfo == nil {
		fallbackDeviceInfo, _, err := config.LatestDeviceInfoForTarget(context.Paths, targetURL)
		if err != nil {
			return nil, err
		}
		deviceInfo = fallbackDeviceInfo
	}

	if deviceInfo == nil {
		fmt.Println("  Note: Previous session has no device info. Push notification will not be sent.")
		fmt.Println("        The session will still be sent via QR code. Complete a full login to enable push.")
		fmt.Println()
		return nil, nil
	}

	manifest.APNToken = deviceInfo.APNToken
	manifest.APNEnvironment = deviceInfo.APNEnvironment

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
		return nil, err
	}

	envelope, err := crypto.EncryptSessionEnvelope(seedPayload, deviceInfo.PublicKey)
	if err != nil {
		return nil, err
	}
	return &envelope, nil
}

func requestType(mode requestMode) string {
	if mode == requestModeRefresh {
		return "refresh"
	}
	return "login"
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

func resolvePositiveInt(raw int, fallback *int, defaultValue int, name string) (int, error) {
	if raw == 0 {
		if fallback != nil {
			return *fallback, nil
		}
		return defaultValue, nil
	}
	if raw < 0 {
		return 0, cliError{message: "invalid --" + name + " value"}
	}
	return raw, nil
}

func stringPtr(value string) *string {
	return &value
}
