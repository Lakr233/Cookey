package main

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
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

	stored := rt.storage.Store(req)

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
