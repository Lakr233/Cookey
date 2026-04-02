package daemon

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"syscall"
	"time"

	"cookey/internal/config"
	"cookey/internal/crypto"
	"cookey/internal/models"
	"cookey/internal/relay"
)

var (
	ErrInvalidDaemonPayload = errors.New("invalid daemon launch payload")
	ErrDescriptorTimeout    = errors.New("timed out waiting for daemon descriptor")
	ErrEmptySessionPayload  = errors.New("decrypted session payload was empty")
)

func LaunchDetached(context config.BootstrapContext, manifest models.LoginManifest, timeoutSeconds int) (int32, error) {
	encodedPayload, err := EncodeLaunchPayload(models.DaemonLaunchPayload{
		Manifest:       manifest,
		TimeoutSeconds: timeoutSeconds,
	})
	if err != nil {
		return 0, err
	}

	executablePath, err := os.Executable()
	if err != nil {
		return 0, err
	}

	command := exec.Command(executablePath, "__daemon", encodedPayload)
	command.Stdin = nil
	devNull, err := os.OpenFile("/dev/null", os.O_RDWR, 0)
	if err != nil {
		return 0, err
	}
	defer devNull.Close()
	command.Stdin = devNull
	command.Stdout = devNull
	command.Stderr = devNull
	command.SysProcAttr = &syscall.SysProcAttr{Setsid: true}

	if err := command.Start(); err != nil {
		return 0, err
	}

	if err := waitForDescriptor(manifest.RID, int32(command.Process.Pid), context.Paths); err != nil {
		return 0, err
	}

	return int32(command.Process.Pid), nil
}

func RunInline(context config.BootstrapContext, manifest models.LoginManifest, timeoutSeconds int) {
	descriptor := models.DaemonDescriptor{
		RID:       manifest.RID,
		PID:       int32(os.Getpid()),
		PPID:      int32(os.Getppid()),
		Status:    models.DaemonStateWaiting,
		ServerURL: manifest.ServerURL,
		Transport: models.TransportWS,
		StartedAt: manifest.CreatedAt,
		UpdatedAt: manifest.CreatedAt,
		TargetURL: manifest.TargetURL,
	}

	if err := config.WriteDaemon(descriptor, context.Paths); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(5)
	}

	client, err := relay.NewClient(manifest.ServerURL)
	if err != nil {
		writeDaemonAndExit(descriptor.Updating(models.DaemonStateError, stringPtr("invalid server URL")), context.Paths, 5)
	}

	envelope, err := client.WaitForSession(manifest.RID, timeoutSeconds)
	if err != nil {
		switch {
		case errors.Is(err, relay.ErrExpired):
			writeDaemonAndExit(descriptor.Updating(models.DaemonStateExpired, nil), context.Paths, 3)
		case errors.Is(err, relay.ErrTimeout):
			writeDaemonAndExit(descriptor.Updating(models.DaemonStateExpired, stringPtr("timeout waiting for encrypted session")), context.Paths, 3)
		case errors.Is(err, relay.ErrWSDisconnected):
			writeDaemonAndExit(descriptor.Updating(models.DaemonStateError, stringPtr("WebSocket disconnected — session aborted")), context.Paths, 5)
		default:
			writeDaemonAndExit(descriptor.Updating(models.DaemonStateError, stringPtr(err.Error())), context.Paths, 5)
		}
	}

	receiving := descriptor.Updating(models.DaemonStateReceiving, nil)
	if err := config.WriteDaemon(receiving, context.Paths); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(5)
	}

	session, err := DecodeSession(envelope, manifest.RID, manifest, context.Keypair, context.DeviceFingerprint)
	if err != nil {
		writeDaemonAndExit(receiving.Updating(models.DaemonStateError, stringPtr(err.Error())), context.Paths, 5)
	}
	session = mergeRefreshSessionFromSeed(session, manifest, context.Paths)

	if session.DeviceInfo == nil {
		fmt.Fprintln(os.Stderr, "  Warning: Received session does not include device info.")
		fmt.Fprintln(os.Stderr, "           Push notifications and `cookey request refresh` will not be available for this session.")
	}

	if err := config.WriteSession(session, manifest.RID, context.Paths); err != nil {
		writeDaemonAndExit(receiving.Updating(models.DaemonStateError, stringPtr(err.Error())), context.Paths, 5)
	}

	if err := config.SyncDeviceInfo(context.Paths, manifest.RID, session.DeviceInfo); err != nil {
		fmt.Fprintln(os.Stderr, "  Warning: Failed to update device info for existing sessions.")
		fmt.Fprintln(os.Stderr, "           "+err.Error())
	}

	if err := config.WriteDaemon(receiving.Updating(models.DaemonStateReady, nil), context.Paths); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(5)
	}
}

func DecodeSession(
	envelope models.EncryptedSessionEnvelope,
	rid string,
	manifest models.LoginManifest,
	keypair models.KeypairFile,
	deviceFingerprint string,
) (models.SessionFile, error) {
	if err := crypto.VerifyEnvelopeProof(rid, envelope, manifest.RequestSecret); err != nil {
		return models.SessionFile{}, err
	}

	plaintext, err := crypto.DecryptSessionEnvelope(envelope, keypair)
	if err != nil {
		return models.SessionFile{}, err
	}

	session, err := decodeSessionPayload(plaintext)
	if err != nil {
		return models.SessionFile{}, err
	}

	return models.SessionFile{
		Cookies:    session.Cookies,
		Origins:    session.Origins,
		DeviceInfo: session.DeviceInfo,
		Metadata: &models.SessionMetadata{
			RID:               rid,
			ReceivedAt:        models.NewISO8601Time(time.Now()),
			ServerURL:         manifest.ServerURL,
			TargetURL:         manifest.TargetURL,
			DeviceFingerprint: deviceFingerprint,
		},
	}, nil
}

func mergeRefreshSessionFromSeed(session models.SessionFile, manifest models.LoginManifest, paths config.AppPaths) models.SessionFile {
	if manifest.RequestType != "refresh" {
		return session
	}

	previousRID, err := config.LatestSessionForTarget(paths, manifest.TargetURL)
	if err != nil || previousRID == "" {
		return session
	}

	previousSession, err := config.ReadJSON[models.SessionFile](paths.SessionPath(previousRID))
	if err != nil {
		return session
	}

	merged := mergeSessionOverlay(previousSession, session)
	if merged.DeviceInfo != nil {
		return merged
	}

	fallbackDeviceInfo, _, err := config.LatestDeviceInfoForTarget(paths, manifest.TargetURL)
	if err != nil || fallbackDeviceInfo == nil {
		return merged
	}

	merged.DeviceInfo = fallbackDeviceInfo
	return merged
}

func mergeSessionOverlay(previous models.SessionFile, current models.SessionFile) models.SessionFile {
	current.Cookies = mergeCookies(previous.Cookies, current.Cookies)
	current.Origins = mergeOrigins(previous.Origins, current.Origins)
	if current.DeviceInfo == nil && previous.DeviceInfo != nil {
		copied := *previous.DeviceInfo
		current.DeviceInfo = &copied
	}
	return current
}

func mergeCookies(previous []models.BrowserCookie, current []models.BrowserCookie) []models.BrowserCookie {
	if len(previous) == 0 {
		return append([]models.BrowserCookie(nil), current...)
	}

	merged := append([]models.BrowserCookie(nil), previous...)
	indices := make(map[string]int, len(merged))
	for index, cookie := range merged {
		indices[cookieKey(cookie)] = index
	}

	for _, cookie := range current {
		key := cookieKey(cookie)
		if index, ok := indices[key]; ok {
			merged[index] = cookie
			continue
		}

		indices[key] = len(merged)
		merged = append(merged, cookie)
	}

	return merged
}

func mergeOrigins(previous []models.OriginState, current []models.OriginState) []models.OriginState {
	if len(previous) == 0 {
		return cloneOrigins(current)
	}

	merged := cloneOrigins(previous)
	indices := make(map[string]int, len(merged))
	for index, origin := range merged {
		indices[origin.Origin] = index
	}

	for _, origin := range current {
		if index, ok := indices[origin.Origin]; ok {
			merged[index].LocalStorage = mergeOriginStorage(merged[index].LocalStorage, origin.LocalStorage)
			continue
		}

		indices[origin.Origin] = len(merged)
		merged = append(merged, cloneOrigin(origin))
	}

	return merged
}

func mergeOriginStorage(previous []models.OriginStorageItem, current []models.OriginStorageItem) []models.OriginStorageItem {
	if len(previous) == 0 {
		return append([]models.OriginStorageItem(nil), current...)
	}

	merged := append([]models.OriginStorageItem(nil), previous...)
	indices := make(map[string]int, len(merged))
	for index, item := range merged {
		indices[item.Name] = index
	}

	for _, item := range current {
		if index, ok := indices[item.Name]; ok {
			merged[index] = item
			continue
		}

		indices[item.Name] = len(merged)
		merged = append(merged, item)
	}

	return merged
}

func cloneOrigins(origins []models.OriginState) []models.OriginState {
	cloned := make([]models.OriginState, len(origins))
	for index, origin := range origins {
		cloned[index] = cloneOrigin(origin)
	}
	return cloned
}

func cloneOrigin(origin models.OriginState) models.OriginState {
	return models.OriginState{
		Origin:       origin.Origin,
		LocalStorage: append([]models.OriginStorageItem(nil), origin.LocalStorage...),
	}
}

func cookieKey(cookie models.BrowserCookie) string {
	return cookie.Name + "\x00" + cookie.Domain + "\x00" + cookie.Path
}

func EncodeLaunchPayload(payload models.DaemonLaunchPayload) (string, error) {
	data, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(data), nil
}

func DecodeLaunchPayload(encoded string) (models.DaemonLaunchPayload, error) {
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return models.DaemonLaunchPayload{}, ErrInvalidDaemonPayload
	}

	var payload models.DaemonLaunchPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		return models.DaemonLaunchPayload{}, err
	}

	return payload, nil
}

func decodeSessionPayload(plaintext []byte) (models.SessionFile, error) {
	session, err := decodeSessionPayloadRecursive(plaintext, 0)
	if err != nil {
		return models.SessionFile{}, fmt.Errorf("invalid decrypted session payload: %w (preview: %s)", err, payloadPreview(plaintext))
	}
	return session, nil
}

func decodeSessionPayloadRecursive(plaintext []byte, depth int) (models.SessionFile, error) {
	if depth > 4 {
		return models.SessionFile{}, errors.New("session payload nesting exceeds supported depth")
	}

	plaintext = bytes.TrimSpace(plaintext)
	if len(plaintext) == 0 {
		return models.SessionFile{}, ErrEmptySessionPayload
	}

	var sessionMap map[string]json.RawMessage
	if err := json.Unmarshal(plaintext, &sessionMap); err == nil {
		_, hasCookies := sessionMap["cookies"]
		_, hasOrigins := sessionMap["origins"]
		if hasCookies || hasOrigins {
			var session models.SessionFile
			if err := json.Unmarshal(plaintext, &session); err != nil {
				return models.SessionFile{}, err
			}
			return session, nil
		}
	}

	var encoded string
	if err := json.Unmarshal(plaintext, &encoded); err == nil {
		return decodeSessionPayloadRecursive([]byte(encoded), depth+1)
	}

	var wrapper struct {
		Session        json.RawMessage `json:"session"`
		Payload        json.RawMessage `json:"payload"`
		StorageState   json.RawMessage `json:"storage_state"`
		StorageStateV1 json.RawMessage `json:"storageState"`
	}
	if err := json.Unmarshal(plaintext, &wrapper); err != nil {
		return models.SessionFile{}, err
	}

	for _, candidate := range []json.RawMessage{
		wrapper.Session,
		wrapper.Payload,
		wrapper.StorageState,
		wrapper.StorageStateV1,
	} {
		if len(bytes.TrimSpace(candidate)) == 0 || bytes.Equal(bytes.TrimSpace(candidate), []byte("null")) {
			continue
		}
		return decodeSessionPayloadRecursive(candidate, depth+1)
	}

	return models.SessionFile{}, errors.New("missing cookies/origins payload")
}

func payloadPreview(plaintext []byte) string {
	trimmed := bytes.TrimSpace(plaintext)
	if len(trimmed) == 0 {
		return `""`
	}
	if len(trimmed) > 160 {
		trimmed = append(trimmed[:160], []byte("...")...)
	}
	return strconv.Quote(string(trimmed))
}

func waitForDescriptor(rid string, expectedPID int32, paths config.AppPaths) error {
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		path := paths.DaemonPath(rid)
		if descriptor, err := config.ReadJSON[models.DaemonDescriptor](path); err == nil && descriptor.PID == expectedPID {
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}

	return fmt.Errorf("%w: %s", ErrDescriptorTimeout, rid)
}

func writeDaemonAndExit(descriptor models.DaemonDescriptor, paths config.AppPaths, code int) {
	_ = config.WriteDaemon(descriptor, paths)
	os.Exit(code)
}

func stringPtr(value string) *string {
	return &value
}
