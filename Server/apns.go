package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// APNSClient handles Apple Push Notification Service communication.
type APNSClient struct {
	config     APNSConfiguration
	httpClient *http.Client
	signingKey *ecdsa.PrivateKey

	mu          sync.Mutex
	cachedToken string
	cachedAt    time.Time
}

// NewAPNSClient creates a new APNs client.
func NewAPNSClient(config APNSConfiguration) *APNSClient {
	return &APNSClient{
		config:     config,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}
}

func (c *APNSClient) SendNotificationWithToken(request *StoredRequest, serverURL string, token string, environment string, blocker *APNTokenBlocker, sourceIP string) {
	if c == nil {
		return
	}
	if err := c.sendNotification(request, serverURL, token, environment, blocker, sourceIP); err != nil {
		log.Printf("APNs push failed: %v", err)
	}
}

func (c *APNSClient) sendNotification(request *StoredRequest, serverURL string, token string, environment string, blocker *APNTokenBlocker, sourceIP string) error {
	if token == "" || environment == "" {
		return nil
	}
	if blocker != nil && blocker.IsBlocked(token) {
		return nil
	}

	// Route sandbox vs production
	baseURL := "https://api.push.apple.com"
	if strings.EqualFold(environment, "sandbox") {
		baseURL = "https://api.sandbox.push.apple.com"
	}
	url := fmt.Sprintf("%s/3/device/%s", baseURL, token)

	titleLocKey := "apn_login_title"
	locKey := "apn_login_body"
	if request.RequestType == RequestTypeRefresh {
		titleLocKey = "apn_refresh_title"
		locKey = "apn_refresh_body"
	}

	payload := apnsNotificationPayload{
		APS: apsPayload{
			Alert: apsAlert{
				TitleLocKey: titleLocKey,
				LocKey:      locKey,
				LocArgs:     []string{request.TargetURL},
			},
			Sound: "default",
		},
		DeviceID:    request.DeviceID,
		Pubkey:      request.CLIPublicKey,
		RequestType: request.RequestType,
		RID:         request.RID,
		ServerURL:   serverURL,
		TargetURL:   request.TargetURL,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}

	authToken, err := c.jwtToken()
	if err != nil {
		return fmt.Errorf("generate JWT: %w", err)
	}

	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	req.Header.Set("apns-topic", c.config.BundleID)
	req.Header.Set("authorization", "bearer "+authToken)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		respBody, _ := io.ReadAll(resp.Body)
		if blocker != nil {
			blocker.RecordFailure(token, sourceIP)
		}
		return fmt.Errorf("APNs HTTP %d: %s", resp.StatusCode, string(respBody))
	}

	if blocker != nil {
		blocker.RecordSuccess(token, sourceIP)
	}

	return nil
}

func (c *APNSClient) jwtToken() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()
	if c.cachedToken != "" && now.Sub(c.cachedAt) < 50*time.Minute {
		return c.cachedToken, nil
	}

	key, err := c.loadSigningKey()
	if err != nil {
		return "", err
	}

	header := jwtHeader{Alg: "ES256", Kid: c.config.KeyID}
	payload := jwtPayload{Iss: c.config.TeamID, Iat: int(now.Unix())}

	headerPart, err := encodeJWTPart(header)
	if err != nil {
		return "", err
	}
	payloadPart, err := encodeJWTPart(payload)
	if err != nil {
		return "", err
	}

	signingInput := headerPart + "." + payloadPart

	// Sign with ECDSA — JWT ES256 requires raw r||s (IEEE P1363) format
	hash := sha256.Sum256([]byte(signingInput))
	r, s, err := ecdsa.Sign(rand.Reader, key, hash[:])
	if err != nil {
		return "", fmt.Errorf("sign JWT: %w", err)
	}

	// Encode as raw r||s (32 bytes each for P-256)
	curveBits := key.Curve.Params().BitSize
	keyBytes := (curveBits + 7) / 8
	rBytes := r.Bytes()
	sBytes := s.Bytes()
	sig := make([]byte, 2*keyBytes)
	copy(sig[keyBytes-len(rBytes):keyBytes], rBytes)
	copy(sig[2*keyBytes-len(sBytes):], sBytes)

	token := signingInput + "." + base64URLEncode(sig)
	c.cachedToken = token
	c.cachedAt = now
	return token, nil
}

func (c *APNSClient) loadSigningKey() (*ecdsa.PrivateKey, error) {
	if c.signingKey != nil {
		return c.signingKey, nil
	}

	data, err := os.ReadFile(c.config.PrivateKeyPath)
	if err != nil {
		return nil, fmt.Errorf("read key file: %w", err)
	}

	block, _ := pem.Decode(data)
	if block == nil {
		return nil, fmt.Errorf("no PEM block found in key file")
	}

	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		// Try EC private key format
		ecKey, ecErr := x509.ParseECPrivateKey(block.Bytes)
		if ecErr != nil {
			return nil, fmt.Errorf("parse key: %w (also tried EC: %v)", err, ecErr)
		}
		c.signingKey = ecKey
		return ecKey, nil
	}

	ecKey, ok := key.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("key is not ECDSA")
	}
	c.signingKey = ecKey
	return ecKey, nil
}

func isPermanentTokenError(statusCode int, reason string) bool {
	if statusCode != 400 && statusCode != 410 {
		return false
	}
	switch reason {
	case "BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered":
		return true
	}
	return false
}

func encodeJWTPart(v interface{}) (string, error) {
	data, err := json.Marshal(v)
	if err != nil {
		return "", err
	}
	return base64URLEncode(data), nil
}

func base64URLEncode(data []byte) string {
	s := base64.StdEncoding.EncodeToString(data)
	s = strings.ReplaceAll(s, "+", "-")
	s = strings.ReplaceAll(s, "/", "_")
	s = strings.TrimRight(s, "=")
	return s
}

// APNs payload types — fields ordered alphabetically by JSON tag
type apnsNotificationPayload struct {
	APS         apsPayload `json:"aps"`
	DeviceID    string     `json:"device_id"`
	Pubkey      string     `json:"pubkey"`
	RequestType string     `json:"request_type,omitempty"`
	RID         string     `json:"rid"`
	ServerURL   string     `json:"server_url"`
	TargetURL   string     `json:"target_url"`
}

type apsPayload struct {
	Alert apsAlert `json:"alert"`
	Sound string   `json:"sound"`
}

type apsAlert struct {
	LocArgs     []string `json:"loc-args,omitempty"`
	LocKey      string   `json:"loc-key"`
	TitleLocKey string   `json:"title-loc-key"`
}

type apnsErrorResponse struct {
	Reason string `json:"reason"`
}

type jwtHeader struct {
	Alg string `json:"alg"`
	Kid string `json:"kid"`
}

type jwtPayload struct {
	Iat int    `json:"iat"`
	Iss string `json:"iss"`
}
