package main

import (
	"bytes"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"sync"
	"time"
)

// FCMClient handles Firebase Cloud Messaging via HTTP v1 API.
type FCMClient struct {
	config     FCMConfiguration
	httpClient *http.Client
	privateKey *rsa.PrivateKey
	sa         *serviceAccountKey

	mu          sync.Mutex
	cachedToken string
	cachedAt    time.Time
}

// NewFCMClient creates a new FCM client.
func NewFCMClient(config FCMConfiguration) *FCMClient {
	return &FCMClient{
		config:     config,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}
}

// SendNotification sends an FCM push notification to the given token.
func (c *FCMClient) SendNotification(request *StoredRequest, serverURL string, token string, blocker *APNTokenBlocker, sourceIP string) {
	if c == nil {
		return
	}
	if err := c.sendNotification(request, serverURL, token, blocker, sourceIP); err != nil {
		log.Printf("FCM push failed: %v", err)
	}
}

func (c *FCMClient) sendNotification(request *StoredRequest, serverURL string, token string, blocker *APNTokenBlocker, sourceIP string) error {
	if token == "" {
		return nil
	}
	if blocker != nil && blocker.IsBlocked(token) {
		return nil
	}

	accessToken, err := c.getAccessToken()
	if err != nil {
		return fmt.Errorf("get access token: %w", err)
	}

	title := "Login Request"
	body := "Tap to approve the login request"
	if request.RequestType == RequestTypeRefresh {
		title = "Session Refresh Request"
		body = fmt.Sprintf("Tap to approve the refresh request for %s", request.TargetURL)
	}

	payload := fcmV1Request{
		Message: fcmMessage{
			Token: token,
			Notification: &fcmNotification{
				Title: title,
				Body:  body,
			},
			Data: map[string]string{
				"pair_key":     request.PairKey,
				"server_url":   serverURL,
				"request_type": request.RequestType,
				"target_url":   request.TargetURL,
			},
			Android: &fcmAndroid{
				Priority: "high",
			},
		},
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}

	apiURL := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", c.config.ProjectID)
	req, err := http.NewRequest("POST", apiURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+accessToken)

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
		return fmt.Errorf("FCM HTTP %d: %s", resp.StatusCode, string(respBody))
	}

	if blocker != nil {
		blocker.RecordSuccess(token, sourceIP)
	}

	return nil
}

// getAccessToken returns a cached or freshly generated OAuth2 access token
// using the service account's private key (JWT Bearer flow).
func (c *FCMClient) getAccessToken() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()
	if c.cachedToken != "" && now.Sub(c.cachedAt) < 50*time.Minute {
		return c.cachedToken, nil
	}

	key, sa, err := c.loadServiceAccount()
	if err != nil {
		return "", err
	}

	// Build JWT for Google OAuth2 token exchange (RS256)
	headerPart, err := encodeJWTPart(map[string]string{"alg": "RS256", "typ": "JWT"})
	if err != nil {
		return "", err
	}
	claimsPart, err := encodeJWTPart(map[string]interface{}{
		"iss":   sa.ClientEmail,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   sa.TokenURI,
		"iat":   now.Unix(),
		"exp":   now.Add(60 * time.Minute).Unix(),
	})
	if err != nil {
		return "", err
	}

	signingInput := headerPart + "." + claimsPart
	hash := sha256.Sum256([]byte(signingInput))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, hash[:])
	if err != nil {
		return "", fmt.Errorf("sign JWT: %w", err)
	}

	jwt := signingInput + "." + base64URLEncode(sig)

	// Exchange JWT for access token via Google OAuth2
	tokenURI := sa.TokenURI
	if tokenURI == "" {
		tokenURI = "https://oauth2.googleapis.com/token"
	}

	resp, err := c.httpClient.PostForm(tokenURI, url.Values{
		"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"},
		"assertion":  {jwt},
	})
	if err != nil {
		return "", fmt.Errorf("token exchange: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		respBody, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("token exchange HTTP %d: %s", resp.StatusCode, string(respBody))
	}

	var tokenResp struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&tokenResp); err != nil {
		return "", fmt.Errorf("decode token response: %w", err)
	}

	c.cachedToken = tokenResp.AccessToken
	c.cachedAt = now
	return tokenResp.AccessToken, nil
}

func (c *FCMClient) loadServiceAccount() (*rsa.PrivateKey, *serviceAccountKey, error) {
	if c.privateKey != nil && c.sa != nil {
		return c.privateKey, c.sa, nil
	}

	data, err := os.ReadFile(c.config.ServiceAccountKeyPath)
	if err != nil {
		return nil, nil, fmt.Errorf("read service account: %w", err)
	}

	var sa serviceAccountKey
	if err := json.Unmarshal(data, &sa); err != nil {
		return nil, nil, fmt.Errorf("parse service account: %w", err)
	}

	block, _ := pem.Decode([]byte(sa.PrivateKey))
	if block == nil {
		return nil, nil, fmt.Errorf("no PEM block in private key")
	}

	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, nil, fmt.Errorf("parse private key: %w", err)
	}

	rsaKey, ok := key.(*rsa.PrivateKey)
	if !ok {
		return nil, nil, fmt.Errorf("private key is not RSA")
	}

	c.privateKey = rsaKey
	c.sa = &sa
	return rsaKey, &sa, nil
}

// FCM HTTP v1 API types
type fcmV1Request struct {
	Message fcmMessage `json:"message"`
}

type fcmMessage struct {
	Token        string            `json:"token"`
	Notification *fcmNotification  `json:"notification,omitempty"`
	Data         map[string]string `json:"data,omitempty"`
	Android      *fcmAndroid       `json:"android,omitempty"`
}

type fcmNotification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

type fcmAndroid struct {
	Priority string `json:"priority,omitempty"`
}

type serviceAccountKey struct {
	Type         string `json:"type"`
	ProjectID    string `json:"project_id"`
	PrivateKeyID string `json:"private_key_id"`
	PrivateKey   string `json:"private_key"`
	ClientEmail  string `json:"client_email"`
	TokenURI     string `json:"token_uri"`
}
