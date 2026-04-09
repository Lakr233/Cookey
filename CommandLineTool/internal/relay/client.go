package relay

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gorilla/websocket"

	"cookey/internal/models"
)

var (
	ErrInvalidResponse = errors.New("relay server returned an invalid response")
	ErrExpired         = errors.New("request expired before a session arrived")
	ErrMissing         = errors.New("request was not found")
	ErrTimeout         = errors.New("timed out while waiting for session")
	ErrWSDisconnected  = errors.New("WebSocket connection lost")
)

type HTTPStatusError struct {
	Code int
	Body string
}

func (e HTTPStatusError) Error() string {
	return fmt.Sprintf("relay server responded with HTTP %d: %s", e.Code, e.Body)
}

type Client struct {
	baseURL    *url.URL
	httpClient *http.Client
}

const registerRetryLimit = 3

func NewClient(rawBaseURL string) (*Client, error) {
	parsed, err := parseRelayBaseURL(rawBaseURL)
	if err != nil {
		return nil, err
	}

	return &Client{
		baseURL: parsed,
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
	}, nil
}

func CanonicalBaseURL(rawBaseURL string) (string, error) {
	parsed, err := parseRelayBaseURL(rawBaseURL)
	if err != nil {
		return "", err
	}
	return parsed.String(), nil
}

func (c *Client) Register(manifest models.LoginManifest) (string, error) {
	body, err := json.Marshal(models.RelayRegisterRequest{
		APNEnvironment:    manifest.APNEnvironment,
		APNToken:          manifest.APNToken,
		FCMToken:          manifest.FCMToken,
		RID:               manifest.RID,
		TargetURL:         manifest.TargetURL,
		CLIPublicKey:      manifest.CLIPublicKey,
		DeviceID:          manifest.DeviceID,
		DeviceFingerprint: manifest.DeviceFingerprint,
		ExpiresAt:         manifest.ExpiresAt,
		RequestType:       manifest.RequestType,
		RequestProof:      manifest.RequestProof,
		RequestSecret:     manifest.RequestSecret,
	})
	if err != nil {
		return "", err
	}

	var lastErr error
	for attempt := 0; attempt < registerRetryLimit; attempt++ {
		request, err := http.NewRequestWithContext(context.Background(), http.MethodPost, c.url("v1/requests").String(), bytes.NewReader(body))
		if err != nil {
			return "", err
		}
		request.Header.Set("Content-Type", "application/json")

		responseBody, statusCode, err := c.do(request, 15*time.Second)
		if err != nil {
			return "", err
		}

		if statusCode < 200 || statusCode >= 300 {
			lastErr = HTTPStatusError{Code: statusCode, Body: responseBody}
			if shouldRetryRegister(lastErr) {
				continue
			}
			return "", lastErr
		}

		var response models.RelayStatusResponse
		if err := json.Unmarshal([]byte(responseBody), &response); err != nil {
			return "", fmt.Errorf("relay server returned an invalid response: %w", err)
		}
		if response.PairKey != nil && *response.PairKey != "" {
			return *response.PairKey, nil
		}
		return "", ErrInvalidResponse
	}
	if lastErr != nil {
		return "", lastErr
	}
	return "", ErrInvalidResponse
}

func (c *Client) UploadSeedSession(rid string, envelope models.EncryptedSessionEnvelope) error {
	body, err := json.Marshal(envelope)
	if err != nil {
		return err
	}

	request, err := http.NewRequestWithContext(context.Background(), http.MethodPost, c.url("v1/requests/"+rid+"/seed-session").String(), bytes.NewReader(body))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", "application/json")

	responseBody, statusCode, err := c.do(request, 15*time.Second)
	if err != nil {
		return err
	}

	if statusCode < 200 || statusCode >= 300 {
		return HTTPStatusError{Code: statusCode, Body: responseBody}
	}

	return nil
}

func (c *Client) FetchStatus(rid string) (*models.RelayStatusResponse, error) {
	request, err := http.NewRequestWithContext(context.Background(), http.MethodGet, c.url("v1/requests/"+rid).String(), nil)
	if err != nil {
		return nil, err
	}

	responseBody, statusCode, err := c.do(request, 10*time.Second)
	if err != nil {
		return nil, err
	}

	switch statusCode {
	case http.StatusNotFound:
		return nil, nil
	case http.StatusGone:
		status := "expired"
		return &models.RelayStatusResponse{
			RID:    &rid,
			Status: &status,
		}, nil
	default:
		if statusCode < 200 || statusCode >= 300 {
			return nil, HTTPStatusError{Code: statusCode, Body: responseBody}
		}
	}

	var response models.RelayStatusResponse
	if err := json.Unmarshal([]byte(responseBody), &response); err != nil {
		return nil, err
	}

	return &response, nil
}

// WaitForSession connects via WebSocket and waits for the encrypted session.
// If the WebSocket connection drops for any reason, the function returns immediately
// with an error — no reconnect, no fallback.
func (c *Client) WaitForSession(rid string, timeoutSeconds int) (models.EncryptedSessionEnvelope, error) {
	wsURL := c.wsURL("v1/requests/" + rid + "/ws")

	dialer := websocket.Dialer{
		HandshakeTimeout: 10 * time.Second,
	}

	conn, _, err := dialer.Dial(wsURL.String(), nil)
	if err != nil {
		return models.EncryptedSessionEnvelope{}, fmt.Errorf("WebSocket dial failed: %w", err)
	}
	defer conn.Close()

	deadline := time.Now().Add(time.Duration(timeoutSeconds) * time.Second)
	conn.SetReadDeadline(deadline)

	// Send periodic pings to keep the connection alive and detect dead connections.
	done := make(chan struct{})
	defer close(done)
	go func() {
		ticker := time.NewTicker(15 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-done:
				return
			case <-ticker.C:
				if err := conn.WriteMessage(websocket.TextMessage, []byte("ping")); err != nil {
					return
				}
			}
		}
	}()

	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsCloseError(err, websocket.CloseNormalClosure) {
				return models.EncryptedSessionEnvelope{}, fmt.Errorf("%w: %s", ErrWSDisconnected, rid)
			}
			if errors.Is(err, context.DeadlineExceeded) || isTimeoutError(err) {
				return models.EncryptedSessionEnvelope{}, fmt.Errorf("%w: %s", ErrTimeout, rid)
			}
			return models.EncryptedSessionEnvelope{}, fmt.Errorf("%w: %v", ErrWSDisconnected, err)
		}

		// Skip pong responses
		if string(message) == "pong" {
			continue
		}

		var wsMsg wsMessage
		if err := json.Unmarshal(message, &wsMsg); err != nil {
			continue
		}

		switch wsMsg.Type {
		case "session":
			var sessionPayload struct {
				EncryptedSession *models.EncryptedSessionEnvelope `json:"encrypted_session"`
			}
			if err := json.Unmarshal(wsMsg.Payload, &sessionPayload); err != nil {
				return models.EncryptedSessionEnvelope{}, fmt.Errorf("failed to decode session payload: %w", err)
			}
			if sessionPayload.EncryptedSession == nil {
				return models.EncryptedSessionEnvelope{}, ErrInvalidResponse
			}
			return *sessionPayload.EncryptedSession, nil

		case "error":
			var errorPayload struct {
				Code    string `json:"code"`
				Message string `json:"message"`
			}
			if err := json.Unmarshal(wsMsg.Payload, &errorPayload); err == nil {
				switch errorPayload.Code {
				case "expired":
					return models.EncryptedSessionEnvelope{}, fmt.Errorf("%w: %s", ErrExpired, rid)
				case "missing":
					return models.EncryptedSessionEnvelope{}, fmt.Errorf("%w: %s", ErrMissing, rid)
				}
			}
			return models.EncryptedSessionEnvelope{}, fmt.Errorf("server error: %s", string(wsMsg.Payload))

		case "status":
			// Status updates are informational; keep waiting.
			continue

		default:
			continue
		}
	}
}

type wsMessage struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

func (c *Client) wsURL(path string) *url.URL {
	joined := *c.baseURL
	joined.Path = strings.TrimRight(joined.Path, "/") + "/" + strings.TrimLeft(path, "/")

	switch joined.Scheme {
	case "https":
		joined.Scheme = "wss"
	default:
		joined.Scheme = "ws"
	}

	return &joined
}

func isAllowedRelayURL(parsed *url.URL) bool {
	if parsed == nil {
		return false
	}

	switch strings.ToLower(parsed.Scheme) {
	case "https":
		return parsed.Host != ""
	case "http":
		host := parsed.Hostname()
		if strings.EqualFold(host, "localhost") {
			return true
		}
		ip := net.ParseIP(host)
		return ip != nil && ip.IsLoopback()
	default:
		return false
	}
}

func parseRelayBaseURL(rawBaseURL string) (*url.URL, error) {
	parsed, err := url.Parse(rawBaseURL)
	if err != nil {
		return nil, fmt.Errorf("invalid relay server URL: %w", err)
	}
	if !isAllowedRelayURL(parsed) {
		return nil, fmt.Errorf("relay server URL must use https or loopback http")
	}
	if parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || (parsed.Path != "" && parsed.Path != "/") {
		return nil, fmt.Errorf("relay server URL must not include a custom path, query, or fragment")
	}
	parsed.Path = ""
	parsed.RawPath = ""
	parsed.RawQuery = ""
	parsed.Fragment = ""
	return parsed, nil
}

func shouldRetryRegister(err error) bool {
	httpErr, ok := err.(HTTPStatusError)
	if !ok || httpErr.Code != http.StatusConflict {
		return false
	}
	return strings.Contains(strings.ToLower(httpErr.Body), "pair key collision")
}

func (c *Client) url(path string) *url.URL {
	joined := *c.baseURL
	joined.Path = strings.TrimRight(joined.Path, "/") + "/" + strings.TrimLeft(path, "/")
	return &joined
}

func (c *Client) do(request *http.Request, timeout time.Duration) (string, int, error) {
	client := *c.httpClient
	client.Timeout = timeout

	response, err := client.Do(request)
	if err != nil {
		return "", 0, err
	}
	defer response.Body.Close()

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return "", 0, err
	}

	return string(body), response.StatusCode, nil
}

func isTimeoutError(err error) bool {
	if err == nil {
		return false
	}
	return strings.Contains(err.Error(), "i/o timeout") || strings.Contains(err.Error(), "deadline exceeded")
}
