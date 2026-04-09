package models

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

type ISO8601Time struct {
	time.Time
}

func NewISO8601Time(t time.Time) ISO8601Time {
	return ISO8601Time{Time: t.UTC()}
}

func (t ISO8601Time) MarshalJSON() ([]byte, error) {
	if t.Time.IsZero() {
		return []byte(`""`), nil
	}

	return json.Marshal(t.UTC().Format(time.RFC3339))
}

func (t *ISO8601Time) UnmarshalJSON(data []byte) error {
	if bytes.Equal(data, []byte("null")) {
		t.Time = time.Time{}
		return nil
	}

	var raw string
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}

	raw = strings.TrimSpace(raw)
	if raw == "" {
		t.Time = time.Time{}
		return nil
	}

	for _, layout := range []string{time.RFC3339, time.RFC3339Nano} {
		if parsed, err := time.Parse(layout, raw); err == nil {
			t.Time = parsed.UTC()
			return nil
		}
	}

	return fmt.Errorf("invalid ISO8601 time: %q", raw)
}

func (t ISO8601Time) IsZero() bool {
	return t.Time.IsZero()
}

type Transport string

const (
	TransportWS Transport = "ws"
)

type DaemonState string

const (
	DaemonStateWaiting   DaemonState = "waiting"
	DaemonStateReceiving DaemonState = "receiving"
	DaemonStateReady     DaemonState = "ready"
	DaemonStateExpired   DaemonState = "expired"
	DaemonStateError     DaemonState = "error"
)

type CLIStatus string

const (
	CLIStatusWaiting   CLIStatus = "waiting"
	CLIStatusReceiving CLIStatus = "receiving"
	CLIStatusReady     CLIStatus = "ready"
	CLIStatusExpired   CLIStatus = "expired"
	CLIStatusOrphaned  CLIStatus = "orphaned"
	CLIStatusError     CLIStatus = "error"
	CLIStatusMissing   CLIStatus = "missing"
)

type SessionEncryptionAlgorithm string

const (
	SessionEncryptionAlgorithmX25519XSalsa20Poly1305 SessionEncryptionAlgorithm = "x25519-xsalsa20poly1305"
)

type KeypairFile struct {
	Version    int         `json:"version"`
	Algorithm  string      `json:"algorithm"`
	PublicKey  string      `json:"public_key"`
	PrivateKey string      `json:"private_key"`
	CreatedAt  ISO8601Time `json:"created_at"`
}

type AppConfig struct {
	DefaultServer        *string `json:"default_server,omitempty"`
	TimeoutSeconds       *int    `json:"timeout_seconds,omitempty"`
	SessionRetentionDays *int    `json:"session_retention_days,omitempty"`
}

type DeviceInfo struct {
	DeviceID       string `json:"device_id"`
	APNEnvironment string `json:"apn_environment"`
	APNToken       string `json:"apn_token"`
	FCMToken       string `json:"fcm_token,omitempty"`
	PublicKey      string `json:"public_key"`
}

type LoginManifest struct {
	APNEnvironment    string      `json:"apn_environment,omitempty"`
	APNToken          string      `json:"apn_token,omitempty"`
	FCMToken          string      `json:"fcm_token,omitempty"`
	RID               string      `json:"rid"`
	TargetURL         string      `json:"target_url"`
	ServerURL         string      `json:"server_url"`
	CLIPublicKey      string      `json:"cli_public_key"`
	DeviceID          string      `json:"device_id"`
	DeviceFingerprint string      `json:"device_fingerprint"`
	CreatedAt         ISO8601Time `json:"created_at"`
	ExpiresAt         ISO8601Time `json:"expires_at"`
	RequestType       string      `json:"request_type,omitempty"`
	RequestProof      string      `json:"request_proof,omitempty"`
	RequestSecret     string      `json:"request_secret,omitempty"`
}

type DaemonDescriptor struct {
	RID          string      `json:"rid"`
	PID          int32       `json:"pid"`
	PPID         int32       `json:"ppid"`
	Status       DaemonState `json:"status"`
	ServerURL    string      `json:"server_url"`
	Transport    Transport   `json:"transport"`
	StartedAt    ISO8601Time `json:"started_at"`
	UpdatedAt    ISO8601Time `json:"updated_at"`
	TargetURL    string      `json:"target_url"`
	ErrorMessage *string     `json:"error_message,omitempty"`
}

func (d DaemonDescriptor) Updating(status DaemonState, errorMessage *string) DaemonDescriptor {
	d.Status = status
	d.UpdatedAt = NewISO8601Time(time.Now())
	d.ErrorMessage = errorMessage
	return d
}

type DaemonLaunchPayload struct {
	Manifest       LoginManifest `json:"manifest"`
	TimeoutSeconds int           `json:"timeoutSeconds"`
}

type RelayRegisterRequest struct {
	APNEnvironment    string      `json:"apn_environment,omitempty"`
	APNToken          string      `json:"apn_token,omitempty"`
	FCMToken          string      `json:"fcm_token,omitempty"`
	RID               string      `json:"rid"`
	TargetURL         string      `json:"target_url"`
	CLIPublicKey      string      `json:"cli_public_key"`
	DeviceID          string      `json:"device_id"`
	DeviceFingerprint string      `json:"device_fingerprint"`
	ExpiresAt         ISO8601Time `json:"expires_at"`
	RequestType       string      `json:"request_type,omitempty"`
	RequestProof      string      `json:"request_proof"`
	RequestSecret     string      `json:"request_secret,omitempty"`
}

type RelayStatusResponse struct {
	RID       *string      `json:"rid,omitempty"`
	Status    *string      `json:"status,omitempty"`
	TargetURL *string      `json:"target_url,omitempty"`
	ExpiresAt *ISO8601Time `json:"expires_at,omitempty"`
	CreatedAt *ISO8601Time `json:"created_at,omitempty"`
	PairKey   *string      `json:"pair_key,omitempty"`
}

type EncryptedSessionEnvelope struct {
	Version            int                        `json:"version"`
	Algorithm          SessionEncryptionAlgorithm `json:"algorithm"`
	EphemeralPublicKey string                     `json:"ephemeral_public_key"`
	Nonce              string                     `json:"nonce"`
	Ciphertext         string                     `json:"ciphertext"`
	CapturedAt         ISO8601Time                `json:"captured_at"`
	RequestSignature   string                     `json:"request_signature,omitempty"`
}

type SeedRequestPayload struct {
	RID           string      `json:"rid"`
	ServerURL     string      `json:"server_url"`
	TargetURL     string      `json:"target_url"`
	CLIPublicKey  string      `json:"cli_public_key"`
	DeviceID      string      `json:"device_id"`
	RequestType   string      `json:"request_type"`
	ExpiresAt     ISO8601Time `json:"expires_at"`
	RequestProof  string      `json:"request_proof"`
	RequestSecret string      `json:"request_secret"`
}

type SeedSessionPayload struct {
	Cookies []BrowserCookie     `json:"cookies"`
	Origins []OriginState       `json:"origins"`
	Request *SeedRequestPayload `json:"_cookey_request,omitempty"`
}

type SessionFile struct {
	Cookies    []BrowserCookie  `json:"cookies"`
	Origins    []OriginState    `json:"origins"`
	DeviceInfo *DeviceInfo      `json:"device_info,omitempty"`
	Metadata   *SessionMetadata `json:"_cookey,omitempty"`
}

type BrowserCookie struct {
	Name     string  `json:"name"`
	Value    string  `json:"value"`
	Domain   string  `json:"domain"`
	Path     string  `json:"path"`
	Expires  float64 `json:"expires"`
	HTTPOnly bool    `json:"httpOnly"`
	Secure   bool    `json:"secure"`
	SameSite string  `json:"sameSite"`
}

func (c BrowserCookie) MarshalJSON() ([]byte, error) {
	type alias BrowserCookie
	normalized := alias(c)
	normalized.SameSite = normalizeBrowserCookieSameSite(normalized.SameSite)
	return json.Marshal(normalized)
}

func (c *BrowserCookie) UnmarshalJSON(data []byte) error {
	type alias BrowserCookie
	var decoded alias
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	decoded.SameSite = normalizeBrowserCookieSameSite(decoded.SameSite)
	*c = BrowserCookie(decoded)
	return nil
}

func normalizeBrowserCookieSameSite(raw string) string {
	trimmed := strings.TrimSpace(raw)
	switch strings.ToLower(trimmed) {
	case "lax":
		return "Lax"
	case "strict":
		return "Strict"
	case "none":
		return "None"
	default:
		return trimmed
	}
}

type OriginState struct {
	Origin       string              `json:"origin"`
	LocalStorage []OriginStorageItem `json:"localStorage"`
}

func (o OriginState) MarshalJSON() ([]byte, error) {
	type alias OriginState
	normalized := alias(o)
	if normalized.LocalStorage == nil {
		normalized.LocalStorage = []OriginStorageItem{}
	}
	return json.Marshal(normalized)
}

func (o *OriginState) UnmarshalJSON(data []byte) error {
	type alias OriginState
	var decoded alias
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	if decoded.LocalStorage == nil {
		decoded.LocalStorage = []OriginStorageItem{}
	}
	*o = OriginState(decoded)
	return nil
}

type OriginStorageItem struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

type SessionMetadata struct {
	RID               string      `json:"rid"`
	ReceivedAt        ISO8601Time `json:"received_at"`
	ServerURL         string      `json:"server_url"`
	TargetURL         string      `json:"target_url"`
	DeviceFingerprint string      `json:"device_fingerprint"`
}

type StatusSnapshot struct {
	RID          string       `json:"rid"`
	Status       CLIStatus    `json:"status"`
	PID          *int32       `json:"pid,omitempty"`
	TargetURL    *string      `json:"target_url,omitempty"`
	SessionPath  *string      `json:"session_path,omitempty"`
	UpdatedAt    *ISO8601Time `json:"updated_at,omitempty"`
	ServerURL    *string      `json:"server_url,omitempty"`
	ErrorMessage *string      `json:"error_message,omitempty"`
}

type StatusSummary struct {
	LatestDaemon  *StatusSnapshot `json:"latest_daemon,omitempty"`
	LatestSession *StatusSnapshot `json:"latest_session,omitempty"`
}

type LoginOutput struct {
	RID                     string `json:"rid"`
	ServerURL               string `json:"server_url"`
	TargetURL               string `json:"target_url"`
	TimeoutSeconds          int    `json:"timeout_seconds"`
	DaemonPID               int32  `json:"daemon_pid"`
	PairKey                 string `json:"pair_key"`
	DeepLink                string `json:"deep_link"`
	JumpLink                string `json:"jump_link"`
	QRText                  string `json:"qr_text"`
	ShowQR                  bool   `json:"show_qr,omitempty"`
	Detached                bool   `json:"detached"`
	CLIPublicKeyFingerprint string `json:"cli_public_key_fingerprint,omitempty"`
}

type DeleteOutput struct {
	RID            string `json:"rid"`
	SessionDeleted bool   `json:"session_deleted"`
	DaemonDeleted  bool   `json:"daemon_deleted"`
}

type CleanOutput struct {
	Deleted []DeleteOutput   `json:"deleted"`
	Skipped []StatusSnapshot `json:"skipped,omitempty"`
}

type PlaywrightStorageState struct {
	Cookies []BrowserCookie `json:"cookies"`
	Origins []OriginState   `json:"origins"`
}
