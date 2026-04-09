package config

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"syscall"
	"time"

	"cookey/internal/crypto"
	"cookey/internal/fileutil"
	"cookey/internal/models"
)

var ErrActiveRequest = errors.New("request is still active")

type AppPaths struct {
	Root             string
	Keypair          string
	Config           string
	DeviceIdentifier string
	Sessions         string
	Daemons          string
}

func NewAppPaths(homeDirectory string) AppPaths {
	root := filepath.Join(homeDirectory, ".cookey")
	return AppPaths{
		Root:             root,
		Keypair:          filepath.Join(root, "keypair.json"),
		Config:           filepath.Join(root, "config.json"),
		DeviceIdentifier: filepath.Join(root, "device_id"),
		Sessions:         filepath.Join(root, "sessions"),
		Daemons:          filepath.Join(root, "daemons"),
	}
}

func (p AppPaths) SessionPath(rid string) string {
	return filepath.Join(p.Sessions, rid+".json")
}

func (p AppPaths) DaemonPath(rid string) string {
	return filepath.Join(p.Daemons, rid+".json")
}

type BootstrapContext struct {
	Paths             AppPaths
	Keypair           models.KeypairFile
	Config            models.AppConfig
	DeviceIdentifier  string
	DeviceFingerprint string
}

func Bootstrap() (BootstrapContext, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return BootstrapContext{}, err
	}

	paths := NewAppPaths(homeDir)
	for _, dir := range []string{paths.Root, paths.Sessions, paths.Daemons} {
		if err := ensureDirectory(dir, 0o700); err != nil {
			return BootstrapContext{}, err
		}
	}

	config, err := LoadConfig(paths.Config)
	if err != nil {
		return BootstrapContext{}, err
	}

	if err := CleanupStaleDaemons(paths); err != nil {
		return BootstrapContext{}, err
	}

	return BootstrapContext{
		Paths:  paths,
		Config: config,
	}, nil
}

func BootstrapWithIdentity() (BootstrapContext, error) {
	context, err := Bootstrap()
	if err != nil {
		return BootstrapContext{}, err
	}

	keypair, err := crypto.LoadOrCreate(context.Paths.Keypair)
	if err != nil {
		return BootstrapContext{}, err
	}

	deviceID, err := LoadOrCreateDeviceID(context.Paths.DeviceIdentifier)
	if err != nil {
		return BootstrapContext{}, err
	}

	fingerprint, err := DeviceFingerprint(keypair)
	if err != nil {
		return BootstrapContext{}, err
	}

	context.Keypair = keypair
	context.DeviceIdentifier = deviceID
	context.DeviceFingerprint = fingerprint
	return context, nil
}

func LoadConfig(path string) (models.AppConfig, error) {
	if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) {
		return models.AppConfig{}, nil
	}

	return ReadJSON[models.AppConfig](path)
}

func ReadJSON[T any](path string) (T, error) {
	var value T

	data, err := os.ReadFile(path)
	if err != nil {
		return value, err
	}

	decoder := json.NewDecoder(strings.NewReader(string(data)))
	if err := decoder.Decode(&value); err != nil {
		return value, err
	}

	return value, nil
}

func WriteJSON(path string, value any, permissions os.FileMode) error {
	data, err := marshalPrettyJSON(value)
	if err != nil {
		return err
	}

	return fileutil.WriteFileAtomically(path, data, permissions)
}

func LoadOrCreateDeviceID(path string) (string, error) {
	if data, err := os.ReadFile(path); err == nil {
		value := strings.TrimSpace(string(data))
		if value != "" {
			return value, nil
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}

	identifier, err := randomUUIDv4()
	if err != nil {
		return "", err
	}

	if err := fileutil.WriteFileAtomically(path, []byte(identifier), 0o600); err != nil {
		return "", err
	}

	return identifier, nil
}

func DeviceFingerprint(keypair models.KeypairFile) (string, error) {
	hostname, err := os.Hostname()
	if err != nil || hostname == "" {
		hostname = "unknown-host"
	}

	osVersion := currentOSVersionString()
	arch := currentArchitecture()
	machineID := machineIdentifier()

	input := strings.Join([]string{
		keypair.PublicKey,
		hostname,
		osVersion,
		arch,
		machineID,
	}, "|")

	sum := sha256.Sum256([]byte(input))
	return base64.RawURLEncoding.EncodeToString(sum[:]), nil
}

func CleanupStaleDaemons(paths AppPaths) error {
	files, err := jsonFiles(paths.Daemons)
	if err != nil {
		return err
	}

	for _, file := range files {
		descriptor, err := ReadJSON[models.DaemonDescriptor](file)
		if err != nil {
			continue
		}

		if descriptor.Status != models.DaemonStateWaiting && descriptor.Status != models.DaemonStateReceiving {
			continue
		}

		sessionExists := fileExists(paths.SessionPath(descriptor.RID))
		if sessionExists || IsProcessAlive(descriptor.PID) {
			continue
		}

		message := "stale daemon descriptor; process is not alive"
		updated := descriptor.Updating(models.DaemonStateError, &message)
		if err := WriteDaemon(updated, paths); err != nil {
			return err
		}
	}

	return nil
}

func LatestDaemon(paths AppPaths) (*models.DaemonDescriptor, error) {
	file, err := latestJSONFile(paths.Daemons)
	if err != nil || file == "" {
		return nil, err
	}

	descriptor, err := ReadJSON[models.DaemonDescriptor](file)
	if err != nil {
		return nil, nil
	}

	return &descriptor, nil
}

func LatestSessionRID(paths AppPaths) (string, error) {
	file, err := latestJSONFile(paths.Sessions)
	if err != nil || file == "" {
		return "", err
	}

	return strings.TrimSuffix(filepath.Base(file), filepath.Ext(file)), nil
}

func LatestSessionForTarget(paths AppPaths, targetURL string) (string, error) {
	files, err := jsonFiles(paths.Sessions)
	if err != nil {
		return "", err
	}

	var latestFile string
	var latestTime time.Time
	for _, file := range files {
		session, err := ReadJSON[models.SessionFile](file)
		if err != nil || session.Metadata == nil || session.Metadata.TargetURL != targetURL {
			continue
		}

		modifiedAt := modificationTime(file)
		if latestFile == "" || latestTime.Before(modifiedAt) {
			latestFile = file
			latestTime = modifiedAt
		}
	}

	if latestFile == "" {
		return "", nil
	}

	return strings.TrimSuffix(filepath.Base(latestFile), filepath.Ext(latestFile)), nil
}

func LatestDeviceInfoForTarget(paths AppPaths, targetURL string) (*models.DeviceInfo, string, error) {
	files, err := jsonFiles(paths.Sessions)
	if err != nil {
		return nil, "", err
	}

	var latestDeviceInfo *models.DeviceInfo
	var latestRID string
	var latestTime time.Time
	for _, file := range files {
		session, err := ReadJSON[models.SessionFile](file)
		if err != nil || session.Metadata == nil || session.Metadata.TargetURL != targetURL || session.DeviceInfo == nil {
			continue
		}

		modifiedAt := modificationTime(file)
		if latestDeviceInfo == nil || latestTime.Before(modifiedAt) {
			copied := *session.DeviceInfo
			latestDeviceInfo = &copied
			latestRID = strings.TrimSuffix(filepath.Base(file), filepath.Ext(file))
			latestTime = modifiedAt
		}
	}

	return latestDeviceInfo, latestRID, nil
}

func LatestRID(paths AppPaths) (string, error) {
	sessionFile, err := latestJSONFile(paths.Sessions)
	if err != nil {
		return "", err
	}

	daemonFile, err := latestJSONFile(paths.Daemons)
	if err != nil {
		return "", err
	}

	candidates := make([]string, 0, 2)
	if sessionFile != "" {
		candidates = append(candidates, sessionFile)
	}
	if daemonFile != "" {
		candidates = append(candidates, daemonFile)
	}
	if len(candidates) == 0 {
		return "", nil
	}

	sort.Slice(candidates, func(i, j int) bool {
		return modificationTime(candidates[i]).Before(modificationTime(candidates[j]))
	})

	latest := candidates[len(candidates)-1]
	return strings.TrimSuffix(filepath.Base(latest), filepath.Ext(latest)), nil
}

func ListLocalRIDs(paths AppPaths) ([]string, error) {
	sessionFiles, err := jsonFiles(paths.Sessions)
	if err != nil {
		return nil, err
	}

	daemonFiles, err := jsonFiles(paths.Daemons)
	if err != nil {
		return nil, err
	}

	latestByRID := make(map[string]time.Time, len(sessionFiles)+len(daemonFiles))
	for _, file := range append(sessionFiles, daemonFiles...) {
		rid := strings.TrimSuffix(filepath.Base(file), filepath.Ext(file))
		modifiedAt := modificationTime(file)
		if current, ok := latestByRID[rid]; !ok || current.Before(modifiedAt) {
			latestByRID[rid] = modifiedAt
		}
	}

	rids := make([]string, 0, len(latestByRID))
	for rid := range latestByRID {
		rids = append(rids, rid)
	}

	sort.Slice(rids, func(i, j int) bool {
		left := latestByRID[rids[i]]
		right := latestByRID[rids[j]]
		if left.Equal(right) {
			return rids[i] < rids[j]
		}
		return right.Before(left)
	})

	return rids, nil
}

func StatusSnapshot(rid string, context BootstrapContext) models.StatusSnapshot {
	sessionPath := context.Paths.SessionPath(rid)
	if fileExists(sessionPath) {
		var pid *int32
		var targetURL *string
		var serverURL *string
		var errorMessage *string

		if descriptor, err := ReadJSON[models.DaemonDescriptor](context.Paths.DaemonPath(rid)); err == nil {
			pid = &descriptor.PID
			targetURL = &descriptor.TargetURL
			serverURL = &descriptor.ServerURL
			errorMessage = descriptor.ErrorMessage
		}

		updatedAt := models.NewISO8601Time(modificationTime(sessionPath))
		return models.StatusSnapshot{
			RID:          rid,
			Status:       models.CLIStatusReady,
			PID:          pid,
			TargetURL:    targetURL,
			SessionPath:  &sessionPath,
			UpdatedAt:    &updatedAt,
			ServerURL:    serverURL,
			ErrorMessage: errorMessage,
		}
	}

	daemonPath := context.Paths.DaemonPath(rid)
	if !fileExists(daemonPath) {
		return models.StatusSnapshot{RID: rid, Status: models.CLIStatusMissing}
	}

	descriptor, err := ReadJSON[models.DaemonDescriptor](daemonPath)
	if err != nil {
		return models.StatusSnapshot{RID: rid, Status: models.CLIStatusMissing}
	}

	status := cliStatusFromDaemon(descriptor)
	return models.StatusSnapshot{
		RID:          rid,
		Status:       status,
		PID:          &descriptor.PID,
		TargetURL:    &descriptor.TargetURL,
		UpdatedAt:    &descriptor.UpdatedAt,
		ServerURL:    &descriptor.ServerURL,
		ErrorMessage: descriptor.ErrorMessage,
	}
}

func IsProcessAlive(pid int32) bool {
	if pid <= 0 {
		return false
	}

	err := syscall.Kill(int(pid), 0)
	return err == nil || errors.Is(err, syscall.EPERM)
}

func WriteSession(session models.SessionFile, rid string, paths AppPaths) error {
	return WriteJSON(paths.SessionPath(rid), session, 0o600)
}

func DeleteLocalRID(paths AppPaths, rid string) (bool, bool, error) {
	sessionPath := paths.SessionPath(rid)
	daemonPath := paths.DaemonPath(rid)

	if descriptor, err := ReadJSON[models.DaemonDescriptor](daemonPath); err == nil {
		isActive := descriptor.Status == models.DaemonStateWaiting || descriptor.Status == models.DaemonStateReceiving
		if isActive && IsProcessAlive(descriptor.PID) {
			return false, false, ErrActiveRequest
		}
	}

	sessionDeleted, err := removeIfExists(sessionPath)
	if err != nil {
		return false, false, err
	}

	daemonDeleted, err := removeIfExists(daemonPath)
	if err != nil {
		return sessionDeleted, false, err
	}

	if !sessionDeleted && !daemonDeleted {
		return false, false, os.ErrNotExist
	}

	return sessionDeleted, daemonDeleted, nil
}

func SyncDeviceInfo(paths AppPaths, currentRID string, deviceInfo *models.DeviceInfo) error {
	if deviceInfo == nil || strings.TrimSpace(deviceInfo.DeviceID) == "" {
		return nil
	}

	files, err := jsonFiles(paths.Sessions)
	if err != nil {
		return err
	}

	currentPath := paths.SessionPath(currentRID)
	for _, file := range files {
		if file == currentPath {
			continue
		}

		session, err := ReadJSON[models.SessionFile](file)
		if err != nil || session.DeviceInfo == nil {
			continue
		}

		if session.DeviceInfo.DeviceID != deviceInfo.DeviceID {
			continue
		}

		if session.DeviceInfo.APNEnvironment == deviceInfo.APNEnvironment &&
			session.DeviceInfo.APNToken == deviceInfo.APNToken &&
			session.DeviceInfo.FCMToken == deviceInfo.FCMToken &&
			session.DeviceInfo.PublicKey == deviceInfo.PublicKey {
			continue
		}

		session.DeviceInfo = &models.DeviceInfo{
			DeviceID:       deviceInfo.DeviceID,
			APNEnvironment: deviceInfo.APNEnvironment,
			APNToken:       deviceInfo.APNToken,
			FCMToken:       deviceInfo.FCMToken,
			PublicKey:      deviceInfo.PublicKey,
		}

		if err := WriteJSON(file, session, 0o600); err != nil {
			return err
		}
	}

	return nil
}

func WriteDaemon(descriptor models.DaemonDescriptor, paths AppPaths) error {
	return WriteJSON(paths.DaemonPath(descriptor.RID), descriptor, 0o600)
}

func ensureDirectory(path string, permissions os.FileMode) error {
	if err := os.MkdirAll(path, permissions); err != nil {
		return err
	}

	return os.Chmod(path, permissions)
}

func marshalPrettyJSON(value any) ([]byte, error) {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(data, '\n'), nil
}

func randomUUIDv4() (string, error) {
	bytes, err := crypto.RandomBytes(16)
	if err != nil {
		return "", err
	}

	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80

	return fmtUUID(bytes), nil
}

func fmtUUID(b []byte) string {
	hex := "0123456789abcdef"
	out := make([]byte, 36)
	positions := []int{8, 13, 18, 23}
	posIndex := 0
	for i, j := 0, 0; i < len(b); i++ {
		if posIndex < len(positions) && j == positions[posIndex] {
			out[j] = '-'
			j++
			posIndex++
		}
		out[j] = hex[b[i]>>4]
		out[j+1] = hex[b[i]&0x0f]
		j += 2
	}
	return string(out)
}

func cliStatusFromDaemon(descriptor models.DaemonDescriptor) models.CLIStatus {
	isActive := descriptor.Status == models.DaemonStateWaiting || descriptor.Status == models.DaemonStateReceiving
	if isActive && !IsProcessAlive(descriptor.PID) {
		return models.CLIStatusOrphaned
	}

	switch descriptor.Status {
	case models.DaemonStateWaiting:
		return models.CLIStatusWaiting
	case models.DaemonStateReceiving:
		return models.CLIStatusReceiving
	case models.DaemonStateReady:
		return models.CLIStatusReady
	case models.DaemonStateExpired:
		return models.CLIStatusExpired
	default:
		return models.CLIStatusError
	}
}

func latestJSONFile(dir string) (string, error) {
	files, err := jsonFiles(dir)
	if err != nil || len(files) == 0 {
		return "", err
	}

	sort.Slice(files, func(i, j int) bool {
		return modificationTime(files[i]).Before(modificationTime(files[j]))
	})

	return files[len(files)-1], nil
}

func jsonFiles(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}

	files := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}
		files = append(files, filepath.Join(dir, entry.Name()))
	}
	return files, nil
}

func modificationTime(path string) time.Time {
	info, err := os.Stat(path)
	if err != nil {
		return time.Time{}
	}
	return info.ModTime()
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func removeIfExists(path string) (bool, error) {
	if err := os.Remove(path); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func currentOSVersionString() string {
	if runtime.GOOS == "darwin" {
		productVersion, errVersion := exec.Command("sw_vers", "-productVersion").Output()
		buildVersion, errBuild := exec.Command("sw_vers", "-buildVersion").Output()
		if errVersion == nil && errBuild == nil {
			return "Version " + strings.TrimSpace(string(productVersion)) + " (Build " + strings.TrimSpace(string(buildVersion)) + ")"
		}
	}

	return runtime.GOOS
}

func machineIdentifier() string {
	for _, candidate := range []string{"/etc/machine-id", "/var/lib/dbus/machine-id"} {
		data, err := os.ReadFile(candidate)
		if err != nil {
			continue
		}

		value := strings.TrimSpace(string(data))
		if value != "" {
			return value
		}
	}

	return ""
}

func currentArchitecture() string {
	switch runtime.GOARCH {
	case "amd64":
		return "x86_64"
	case "arm64":
		return "arm64"
	default:
		return runtime.GOARCH
	}
}
