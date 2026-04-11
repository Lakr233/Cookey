package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// ISO8601Time wraps time.Time to marshal as ISO 8601 without fractional seconds,
// matching Swift's .iso8601 date encoding strategy.
type ISO8601Time struct {
	time.Time
}

func (t ISO8601Time) MarshalJSON() ([]byte, error) {
	if t.IsZero() {
		return []byte(`""`), nil
	}
	return json.Marshal(t.UTC().Format(time.RFC3339))
}

func (t *ISO8601Time) UnmarshalJSON(data []byte) error {
	var raw string
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
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

func nowISO8601() ISO8601Time {
	return ISO8601Time{time.Now().UTC()}
}

// RequestStatus represents the state of a login request.
type RequestStatus string

const (
	StatusPending   RequestStatus = "pending"
	StatusReady     RequestStatus = "ready"
	StatusExpired   RequestStatus = "expired"
	StatusDelivered RequestStatus = "delivered"
)

// LoginRequest is the payload from CLI to create a pending request.
// Fields ordered alphabetically by JSON tag to match Swift's sortedKeys.
type LoginRequest struct {
	APNEnvironment    string      `json:"apn_environment,omitempty"`
	APNToken          string      `json:"apn_token,omitempty"`
	CLIPublicKey      string      `json:"cli_public_key"`
	DeviceFingerprint string      `json:"device_fingerprint"`
	DeviceID          string      `json:"device_id"`
	ExpiresAt         ISO8601Time `json:"expires_at"`
	FCMToken          string      `json:"fcm_token,omitempty"`
	RequestType       string      `json:"request_type,omitempty"`
	RequestProof      string      `json:"request_proof"`
	RequestSecret     string      `json:"request_secret,omitempty"`
	RID               string      `json:"rid"`
	TargetURL         string      `json:"target_url"`
}

// StoredRequest is the in-memory representation with metadata.
type StoredRequest struct {
	RID                  string            `json:"-"`
	TargetURL            string            `json:"-"`
	CLIPublicKey         string            `json:"-"`
	DeviceID             string            `json:"-"`
	DeviceFingerprint    string            `json:"-"`
	APNEnvironment       string            `json:"-"`
	APNToken             string            `json:"-"`
	FCMToken             string            `json:"-"`
	CreatedAt            time.Time         `json:"-"`
	ExpiresAt            time.Time         `json:"-"`
	RequestType          string            `json:"-"`
	RequestProof         string            `json:"-"`
	RequestSecret        string            `json:"-"`
	PairKey              string            `json:"-"`
	Status               RequestStatus     `json:"-"`
	EncryptedSession     *EncryptedSession `json:"-"`
	EncryptedSeedSession *EncryptedSession `json:"-"`
}

// RequestStatusResponse is the JSON response for request queries.
// Fields ordered alphabetically by JSON tag to match Swift's sortedKeys.
type RequestStatusResponse struct {
	CreatedAt   ISO8601Time   `json:"created_at"`
	ExpiresAt   ISO8601Time   `json:"expires_at"`
	PairKey     string        `json:"pair_key,omitempty"`
	RequestType string        `json:"request_type,omitempty"`
	RID         string        `json:"rid"`
	Status      RequestStatus `json:"status"`
	TargetURL   string        `json:"target_url"`
}

func NewRequestStatusResponse(r *StoredRequest) RequestStatusResponse {
	return RequestStatusResponse{
		CreatedAt:   ISO8601Time{r.CreatedAt},
		ExpiresAt:   ISO8601Time{r.ExpiresAt},
		PairKey:     r.PairKey,
		RequestType: r.RequestType,
		RID:         r.RID,
		Status:      r.Status,
		TargetURL:   r.TargetURL,
	}
}

// PairKeyResponse is the JSON response for pair key resolution.
// Fields ordered alphabetically by JSON tag.
type PairKeyResponse struct {
	CLIPublicKey  string      `json:"cli_public_key"`
	DeviceID      string      `json:"device_id"`
	ExpiresAt     ISO8601Time `json:"expires_at"`
	RID           string      `json:"rid"`
	RequestProof  string      `json:"request_proof"`
	RequestSecret string      `json:"request_secret"`
	RequestType   string      `json:"request_type"`
	ServerURL     string      `json:"server_url"`
	TargetURL     string      `json:"target_url"`
}

const (
	RequestTypeLogin   = "login"
	RequestTypeRefresh = "refresh"
)

func NormalizeRequestType(requestType string) string {
	switch strings.ToLower(strings.TrimSpace(requestType)) {
	case "", RequestTypeLogin:
		return RequestTypeLogin
	case RequestTypeRefresh:
		return RequestTypeRefresh
	default:
		return ""
	}
}

// Valid encryption algorithms (case-insensitive match, matching Swift's SessionEncryptionAlgorithm).
const AlgorithmX25519XSalsa20Poly1305 = "x25519-xsalsa20poly1305"

// IsValidAlgorithm checks if an algorithm string is recognized.
func IsValidAlgorithm(alg string) bool {
	return strings.EqualFold(alg, AlgorithmX25519XSalsa20Poly1305)
}

// EncryptedSession is the encrypted payload uploaded by mobile.
// Fields ordered alphabetically by JSON tag.
type EncryptedSession struct {
	Algorithm          string      `json:"algorithm"`
	CapturedAt         ISO8601Time `json:"captured_at"`
	Ciphertext         string      `json:"ciphertext"`
	EphemeralPublicKey string      `json:"ephemeral_public_key"`
	Nonce              string      `json:"nonce"`
	RequestSignature   string      `json:"request_signature,omitempty"`
	Version            int         `json:"version"`
}

// WebSocketMessage is the typed envelope sent over WebSocket.
type WebSocketMessage struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
}

// StatusPayload is the payload for "status" WebSocket messages.
// Fields ordered alphabetically by JSON tag.
type StatusPayload struct {
	Status    RequestStatus `json:"status"`
	Timestamp ISO8601Time   `json:"timestamp"`
}

// SessionPayload is the payload for "session" WebSocket messages.
// Fields ordered alphabetically by JSON tag.
type SessionPayload struct {
	DeliveredAt      ISO8601Time      `json:"delivered_at"`
	EncryptedSession EncryptedSession `json:"encrypted_session"`
}

// ErrorPayload is the payload for "error" WebSocket messages.
// Fields ordered alphabetically by JSON tag.
type ErrorPayload struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// ServerConfig holds the server configuration.
type ServerConfig struct {
	Host                 string
	Port                 int
	DefaultTTL           time.Duration
	MaxPayloadSize       int
	PublicURL            string
	DisablePushRateLimit bool
	APNSConfiguration    *APNSConfiguration
	FCMConfiguration     *FCMConfiguration
}

// APNSConfiguration holds APNs push notification settings.
type APNSConfiguration struct {
	TeamID         string
	KeyID          string
	BundleID       string
	PrivateKeyPath string
}

// FCMConfiguration holds Firebase Cloud Messaging settings.
type FCMConfiguration struct {
	ServiceAccountKeyPath string
	ProjectID             string
}

// encodeJSON marshals a value to JSON with sorted keys via struct field order.
func encodeJSON(v interface{}) ([]byte, error) {
	return json.Marshal(v)
}
