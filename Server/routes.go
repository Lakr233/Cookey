package main

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const maxRequestTTL = 30 * time.Minute

type notificationSender interface {
	SendNotificationWithToken(request *StoredRequest, serverURL string, token string, environment string, blocker *APNTokenBlocker, sourceIP string)
}

// Routes holds the HTTP handler dependencies.
type Routes struct {
	storage     *Storage
	config      ServerConfig
	apnsClient  notificationSender
	apnBlocker  *APNTokenBlocker
	pushLimiter *APNPushRateLimiter
}

// Register sets up all HTTP routes on the given mux.
func (rt *Routes) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /jump", rt.handleJump)
	mux.HandleFunc("GET /health", rt.handleHealth)
	mux.HandleFunc("POST /v1/requests", rt.handleCreateRequest)
	mux.HandleFunc("GET /v1/pair/{pair_key}", rt.handleResolvePairKey)
	mux.HandleFunc("GET /v1/requests/{rid}", rt.handleGetRequest)
	mux.HandleFunc("GET /v1/requests/{rid}/seed-session", rt.handleGetSeedSession)
	mux.HandleFunc("POST /v1/requests/{rid}/session", rt.handleUploadSession)
	mux.HandleFunc("POST /v1/requests/{rid}/seed-session", rt.handleUploadSeedSession)
	mux.HandleFunc("GET /v1/requests/{rid}/ws", rt.handleWebSocket)
}

// GET /health
func (rt *Routes) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

// GET /jump — serve a small HTML page that opens the cookey:// deep link.
func (rt *Routes) handleJump(w http.ResponseWriter, r *http.Request) {
	code := strings.TrimSpace(r.URL.Query().Get("code"))
	if code == "" {
		writeText(w, http.StatusBadRequest, "Missing code parameter")
		return
	}

	pairKey := strings.ToUpper(strings.ReplaceAll(code, "-", ""))
	if pairKey == "" {
		writeText(w, http.StatusBadRequest, "Invalid code parameter")
		return
	}

	stored := rt.storage.GetRequestByPairKey(pairKey)
	if stored == nil {
		writeText(w, http.StatusNotFound, "Pair key not found")
		return
	}

	if stored.ExpiresAt.Before(time.Now()) {
		rt.storage.UpdateStatus(stored.RID, StatusExpired)
		writeText(w, http.StatusGone, "Request expired")
		return
	}

	writeJumpHTML(w, buildJumpDeepLink(pairKey, rt.config.PublicURL))
}

func buildJumpDeepLink(pairKey string, publicURL string) string {
	target := url.URL{Scheme: "cookey", Host: pairKey}
	const defaultHost = "api.cookey.sh"
	if publicHost := extractHost(publicURL); publicHost != "" && publicHost != defaultHost {
		query := url.Values{}
		query.Set("host", publicHost)
		target.RawQuery = query.Encode()
	}

	return target.String()
}

func writeJumpHTML(w http.ResponseWriter, deepLink string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)

	escapedLink := strings.NewReplacer(
		"&", "&amp;",
		`"`, "&quot;",
		"<", "&lt;",
		">", "&gt;",
	).Replace(deepLink)
	quotedScriptLinkBytes, _ := json.Marshal(deepLink)
	quotedScriptLink := string(quotedScriptLinkBytes)

	io.WriteString(w, "<!doctype html>\n")
	io.WriteString(w, `<html lang="en"><head><meta charset="utf-8">`)
	io.WriteString(w, `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">`)
	io.WriteString(w, `<title>Opening Cookey…</title>`)
	io.WriteString(w, `<style>`)
	io.WriteString(w, `:root{color-scheme:light dark;--bg:#fff;--surface:#f5f5f5;--border:rgba(0,0,0,.1);--ink:#171717;--muted:#737373;--accent:#22c55e;--accent-rgb:34,197,94;--btn-bg:#171717;--btn-fg:#fff}@media(prefers-color-scheme:dark){:root{--bg:#0a0a0a;--surface:#111;--border:rgba(255,255,255,.08);--ink:#f0f0f0;--muted:#888;--accent:#4ade80;--accent-rgb:74,222,128;--btn-bg:#f0f0f0;--btn-fg:#0a0a0a}}body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;background:var(--bg);color:var(--ink);font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;-webkit-font-smoothing:antialiased}main{width:100%;max-width:420px;padding:28px;border:1px solid var(--border);border-radius:20px;background:var(--surface);text-align:center}h1{margin:0 0 12px;font-size:28px;line-height:1.1}p{margin:0;color:var(--muted)}a{display:inline-flex;align-items:center;justify-content:center;margin-top:20px;padding:12px 18px;border-radius:10px;background:var(--btn-bg);color:var(--btn-fg);text-decoration:none;font-weight:600}.muted{margin-top:14px;font-size:14px}.dot{width:10px;height:10px;margin:0 auto 18px;border-radius:999px;background:var(--accent);box-shadow:0 0 0 0 rgba(var(--accent-rgb),.45);animation:pulse 1.6s infinite}@keyframes pulse{0%{transform:scale(.96);box-shadow:0 0 0 0 rgba(var(--accent-rgb),.45)}70%{transform:scale(1);box-shadow:0 0 0 18px rgba(var(--accent-rgb),0)}100%{transform:scale(.96);box-shadow:0 0 0 0 rgba(var(--accent-rgb),0)}}</style>`)
	io.WriteString(w, `</head><body><main><div class="dot"></div><h1>Opening Cookey…</h1><p id="status">If Cookey does not open automatically, tap the button below.</p>`)
	io.WriteString(w, `<a id="open-link" href="`)
	io.WriteString(w, escapedLink)
	io.WriteString(w, `">Open Cookey</a><p class="muted">You can return to this tab after opening the app.</p>`)
	io.WriteString(w, `<script>const target=`)
	io.WriteString(w, quotedScriptLink)
	io.WriteString(w, `;const status=document.getElementById("status");const open=()=>{window.location.href=target;};window.setTimeout(open,120);document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="hidden"){status.textContent="Cookey opened. You can come back here after finishing in the app.";}});</script>`)
	io.WriteString(w, `</main></body></html>`)
}

func extractHost(publicURL string) string {
	parsed, err := url.Parse(publicURL)
	if err != nil || parsed.Host == "" {
		return ""
	}
	return parsed.Host
}

// POST /v1/requests
func (rt *Routes) handleCreateRequest(w http.ResponseWriter, r *http.Request) {
	var req LoginRequest
	if err := decodeBody(r, &req, 10*1024); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid request payload"})
		return
	}
	req.RequestType = NormalizeRequestType(req.RequestType)

	if !rt.isValidCreateRequest(req) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid request payload"})
		return
	}

	if req.ExpiresAt.Time.Before(time.Now()) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid expiration time"})
		return
	}

	maxExpiry := time.Now().Add(maxRequestTTL)
	if req.ExpiresAt.Time.After(maxExpiry) {
		req.ExpiresAt = ISO8601Time{Time: maxExpiry}
	}

	stored, err := rt.storage.Store(req)
	if err != nil {
		if err == ErrPairKeyCollision {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "Pair key collision"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Failed to create request"})
		return
	}

	writeJSON(w, http.StatusCreated, NewRequestStatusResponse(stored))
}

// loadRequestOrFail extracts the rid, loads the request, and checks expiry.
// Returns nil if a response was already written.
func (rt *Routes) loadRequestOrFail(w http.ResponseWriter, r *http.Request) *StoredRequest {
	rid := r.PathValue("rid")
	if rid == "" {
		writeText(w, http.StatusBadRequest, "Missing request ID")
		return nil
	}

	stored := rt.storage.GetRequest(rid)
	if stored == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Request not found"})
		return nil
	}

	if stored.ExpiresAt.Before(time.Now()) {
		rt.storage.UpdateStatus(rid, StatusExpired)
		writeJSON(w, http.StatusGone, map[string]string{"error": "Request expired"})
		return nil
	}

	return stored
}

// GET /v1/requests/{rid}
func (rt *Routes) handleGetRequest(w http.ResponseWriter, r *http.Request) {
	stored := rt.loadRequestOrFail(w, r)
	if stored == nil {
		return
	}

	writeJSON(w, http.StatusOK, NewRequestStatusResponse(stored))
}

// GET /v1/pair/{pair_key}
func (rt *Routes) handleResolvePairKey(w http.ResponseWriter, r *http.Request) {
	pairKey := r.PathValue("pair_key")
	if pairKey == "" {
		writeText(w, http.StatusBadRequest, "Missing pair key")
		return
	}

	stored := rt.storage.GetRequestByPairKey(pairKey)
	if stored == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Pair key not found"})
		return
	}

	if stored.ExpiresAt.Before(time.Now()) {
		rt.storage.UpdateStatus(stored.RID, StatusExpired)
		writeJSON(w, http.StatusGone, map[string]string{"error": "Request expired"})
		return
	}

	writeJSON(w, http.StatusOK, PairKeyResponse{
		CLIPublicKey:  stored.CLIPublicKey,
		DeviceID:      stored.DeviceID,
		ExpiresAt:     ISO8601Time{stored.ExpiresAt},
		RID:           stored.RID,
		RequestProof:  stored.RequestProof,
		RequestSecret: stored.RequestSecret,
		RequestType:   stored.RequestType,
		ServerURL:     rt.config.PublicURL,
		TargetURL:     stored.TargetURL,
	})
}

// GET /v1/requests/{rid}/seed-session
func (rt *Routes) handleGetSeedSession(w http.ResponseWriter, r *http.Request) {
	stored := rt.loadRequestOrFail(w, r)
	if stored == nil {
		return
	}

	seed := rt.storage.GetAndClearSeedSession(stored.RID)
	if seed == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Seed session not found"})
		return
	}

	writeJSON(w, http.StatusOK, seed)
}

// POST /v1/requests/{rid}/session
func (rt *Routes) handleUploadSession(w http.ResponseWriter, r *http.Request) {
	stored := rt.loadRequestOrFail(w, r)
	if stored == nil {
		return
	}

	if stored.Status != StatusPending {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "Session already uploaded"})
		return
	}

	var session EncryptedSession
	if err := decodeBody(r, &session, rt.config.MaxPayloadSize); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid session payload"})
		return
	}

	if !IsValidAlgorithm(session.Algorithm) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid session payload"})
		return
	}
	if strings.TrimSpace(session.RequestSignature) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid session payload"})
		return
	}

	if rt.storage.StoreSession(stored.RID, session) == nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Failed to store session"})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{"status": "uploaded", "rid": stored.RID})
}

// POST /v1/requests/{rid}/seed-session
func (rt *Routes) handleUploadSeedSession(w http.ResponseWriter, r *http.Request) {
	stored := rt.loadRequestOrFail(w, r)
	if stored == nil {
		return
	}

	if stored.RequestType != RequestTypeRefresh {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "Seed session already uploaded"})
		return
	}
	if stored.Status != StatusPending {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "Seed session already uploaded"})
		return
	}
	if stored.EncryptedSeedSession != nil {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "Seed session already uploaded"})
		return
	}

	var seed EncryptedSession
	if err := decodeBody(r, &seed, rt.config.MaxPayloadSize); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid session payload"})
		return
	}

	if !IsValidAlgorithm(seed.Algorithm) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid session payload"})
		return
	}

	if err := rt.storage.StoreSeedSession(stored.RID, &seed); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Failed to store session"})
		return
	}

	if rt.apnsClient != nil && stored.APNToken != "" && stored.APNEnvironment != "" {
		if rt.pushLimiter == nil || rt.pushLimiter.Allow(stored.APNToken) {
			go rt.apnsClient.SendNotificationWithToken(stored, rt.config.PublicURL, stored.APNToken, stored.APNEnvironment, rt.apnBlocker, requestSourceIP(r))
		}
	}

	writeJSON(w, http.StatusCreated, map[string]string{"status": "uploaded", "rid": stored.RID})
}

// decodeBody reads and decodes a JSON body with a size limit.
func decodeBody(r *http.Request, dst interface{}, limit int) error {
	r.Body = http.MaxBytesReader(nil, r.Body, int64(limit))
	data, err := io.ReadAll(r.Body)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, dst)
}

// writeJSON writes a JSON response with the given status code.
func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	data, err := json.Marshal(v)
	if err != nil {
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	w.Write(data)
}

// writeText writes a plain text response with the given status code.
func writeText(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(status)
	w.Write([]byte(body))
}

func (rt *Routes) isValidCreateRequest(req LoginRequest) bool {
	if req.RequestType == "" {
		return false
	}
	if strings.TrimSpace(req.RequestProof) == "" {
		return false
	}
	if (req.APNToken == "") != (req.APNEnvironment == "") {
		return false
	}
	if req.APNEnvironment != "" && !isValidAPNEnvironment(req.APNEnvironment) {
		return false
	}
	return true
}

func isValidAPNEnvironment(environment string) bool {
	switch strings.ToLower(strings.TrimSpace(environment)) {
	case "", "production", "sandbox":
		return true
	default:
		return false
	}
}

func requestSourceIP(r *http.Request) string {
	if forwarded := strings.TrimSpace(strings.Split(r.Header.Get("X-Forwarded-For"), ",")[0]); forwarded != "" {
		return forwarded
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

type APNPushRateLimiter struct {
	mu      sync.Mutex
	entries map[string][]time.Time
}

func NewAPNPushRateLimiter() *APNPushRateLimiter {
	return &APNPushRateLimiter{
		entries: make(map[string][]time.Time),
	}
}

func (l *APNPushRateLimiter) Allow(token string) bool {
	if token == "" {
		return true
	}

	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-5 * time.Minute)
	window := l.entries[token][:0]
	for _, ts := range l.entries[token] {
		if !ts.Before(cutoff) {
			window = append(window, ts)
		}
	}
	if len(window) >= 3 {
		l.entries[token] = window
		return false
	}
	l.entries[token] = append(window, now)
	return true
}

func (l *APNPushRateLimiter) Cleanup() {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-5 * time.Minute)
	for token, timestamps := range l.entries {
		window := timestamps[:0]
		for _, ts := range timestamps {
			if !ts.Before(cutoff) {
				window = append(window, ts)
			}
		}
		if len(window) == 0 {
			delete(l.entries, token)
			continue
		}
		l.entries[token] = window
	}
}
