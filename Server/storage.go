package main

import (
	"crypto/rand"
	"fmt"
	"strings"
	"sync"
	"time"
)

const pairKeyAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
const pairKeyLength = 8

// Storage is the in-memory store for requests, APN registrations, and WebSocket waiters.
type Storage struct {
	mu             sync.RWMutex
	requests       map[string]*StoredRequest
	pairKeys       map[string]string                           // pair_key -> rid
	waiters        map[string]map[string]chan WebSocketMessage // rid -> waiterID -> ch
	maxPayloadSize int
}

// NewStorage creates a new Storage instance.
func NewStorage(maxPayloadSize int) *Storage {
	return &Storage{
		requests:       make(map[string]*StoredRequest),
		pairKeys:       make(map[string]string),
		waiters:        make(map[string]map[string]chan WebSocketMessage),
		maxPayloadSize: maxPayloadSize,
	}
}

// Store adds a new pending request.
func (s *Storage) Store(req LoginRequest) *StoredRequest {
	s.mu.Lock()
	defer s.mu.Unlock()

	pairKey := s.generatePairKeyLocked()

	stored := &StoredRequest{
		RID:               req.RID,
		TargetURL:         req.TargetURL,
		CLIPublicKey:      req.CLIPublicKey,
		DeviceID:          req.DeviceID,
		DeviceFingerprint: req.DeviceFingerprint,
		APNEnvironment:    req.APNEnvironment,
		APNToken:          req.APNToken,
		CreatedAt:         time.Now().UTC(),
		ExpiresAt:         req.ExpiresAt.Time,
		RequestType:       NormalizeRequestType(req.RequestType),
		RequestProof:      req.RequestProof,
		RequestSecret:     req.RequestSecret,
		PairKey:           pairKey,
		Status:            StatusPending,
	}
	s.requests[req.RID] = stored
	if pairKey != "" {
		s.pairKeys[pairKey] = req.RID
	}
	return stored
}

// generatePairKeyLocked generates a unique 8-char pair key. Must be called with s.mu held.
func (s *Storage) generatePairKeyLocked() string {
	for attempt := 0; attempt < 10; attempt++ {
		key := randomPairKey()
		if key == "" {
			continue
		}
		if _, exists := s.pairKeys[key]; !exists {
			return key
		}
	}
	return ""
}

func randomPairKey() string {
	b := make([]byte, pairKeyLength)
	if _, err := rand.Read(b); err != nil {
		return ""
	}
	result := make([]byte, pairKeyLength)
	for i := range b {
		result[i] = pairKeyAlphabet[int(b[i])%len(pairKeyAlphabet)]
	}
	return string(result)
}

// copy returns a shallow copy of the request with deep-copied session pointers.
func (r *StoredRequest) copy() *StoredRequest {
	cp := *r
	if r.EncryptedSession != nil {
		es := *r.EncryptedSession
		cp.EncryptedSession = &es
	}
	if r.EncryptedSeedSession != nil {
		seed := *r.EncryptedSeedSession
		cp.EncryptedSeedSession = &seed
	}
	return &cp
}

// GetRequestByPairKey looks up a request by its short pair key.
func (s *Storage) GetRequestByPairKey(pairKey string) *StoredRequest {
	s.mu.RLock()
	defer s.mu.RUnlock()

	normalized := strings.ToUpper(strings.TrimSpace(pairKey))
	rid, ok := s.pairKeys[normalized]
	if !ok {
		return nil
	}
	r := s.requests[rid]
	if r == nil {
		return nil
	}
	return r.copy()
}

// GetRequest retrieves a stored request by ID.
func (s *Storage) GetRequest(rid string) *StoredRequest {
	s.mu.RLock()
	defer s.mu.RUnlock()
	r := s.requests[rid]
	if r == nil {
		return nil
	}
	return r.copy()
}

// UpdateStatus updates a request's status and notifies waiters.
func (s *Storage) UpdateStatus(rid string, status RequestStatus) *StoredRequest {
	s.mu.Lock()
	defer s.mu.Unlock()

	r := s.requests[rid]
	if r == nil {
		return nil
	}
	r.Status = status
	s.notifyWaiters(rid, WebSocketMessage{
		Type:    "status",
		Payload: StatusPayload{Status: status, Timestamp: nowISO8601()},
	})
	return r.copy()
}

// StoreSession stores an encrypted session, validates payload size, and notifies waiters.
// Returns nil if request not found or payload too large.
func (s *Storage) StoreSession(rid string, session EncryptedSession) *StoredRequest {
	s.mu.Lock()
	defer s.mu.Unlock()

	r := s.requests[rid]
	if r == nil {
		return nil
	}

	// Two-stage validation: field-length check
	payloadSize := len(session.Ciphertext) + len(session.EphemeralPublicKey) + len(session.Nonce) + len(session.RequestSignature)
	if payloadSize > s.maxPayloadSize {
		return nil
	}

	r.EncryptedSession = &session
	r.Status = StatusReady

	s.notifyWaiters(rid, WebSocketMessage{
		Type: "session",
		Payload: SessionPayload{
			DeliveredAt:      nowISO8601(),
			EncryptedSession: session,
		},
	})

	cp := *r
	esCopy := session
	cp.EncryptedSession = &esCopy
	return &cp
}

func (s *Storage) StoreSeedSession(rid string, seed *EncryptedSession) error {
	if seed == nil {
		return fmt.Errorf("missing seed session")
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	r := s.requests[rid]
	if r == nil {
		return fmt.Errorf("request not found")
	}

	payloadSize := len(seed.Ciphertext) + len(seed.EphemeralPublicKey) + len(seed.Nonce)
	if payloadSize > s.maxPayloadSize {
		return fmt.Errorf("seed session too large")
	}

	seedCopy := *seed
	r.EncryptedSeedSession = &seedCopy
	return nil
}

func (s *Storage) GetAndClearSeedSession(rid string) *EncryptedSession {
	s.mu.Lock()
	defer s.mu.Unlock()

	r := s.requests[rid]
	if r == nil || r.EncryptedSeedSession == nil {
		return nil
	}

	seed := *r.EncryptedSeedSession
	r.EncryptedSeedSession = nil
	return &seed
}

// MarkDelivered marks a request as delivered and clears the encrypted session.
func (s *Storage) MarkDelivered(rid string) *StoredRequest {
	s.mu.Lock()
	defer s.mu.Unlock()

	r := s.requests[rid]
	if r == nil {
		return nil
	}
	r.Status = StatusDelivered
	r.EncryptedSession = nil
	if r.PairKey != "" {
		delete(s.pairKeys, r.PairKey)
	}
	cp := *r
	return &cp
}

// CleanupExpired removes expired requests and notifies their waiters.
// Matches Swift order: remove from requests map, then notify waiters.
func (s *Storage) CleanupExpired() []string {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	var expired []string

	for rid, r := range s.requests {
		if r.ExpiresAt.Before(now) {
			expired = append(expired, rid)
		}
	}

	for _, rid := range expired {
		// Remove pair key mapping before deleting request
		if r := s.requests[rid]; r != nil && r.PairKey != "" {
			delete(s.pairKeys, r.PairKey)
		}
		// Remove first, then notify (matching Storage.swift:87-88)
		delete(s.requests, rid)
		s.notifyWaiters(rid, WebSocketMessage{
			Type:    "error",
			Payload: ErrorPayload{Code: "expired", Message: "Request has expired"},
		})
	}

	return expired
}

// RegisterWaiter pre-registers a waiter channel for a rid.
// Returns the channel and true if the waiter was registered (no immediate result),
// or sends the immediate result to the channel and returns it with false.
func (s *Storage) RegisterWaiter(rid string, waiterID string) (chan WebSocketMessage, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	ch := make(chan WebSocketMessage, 1)

	// Check for immediate resolution
	if msg := s.immediateMessage(rid); msg != nil {
		ch <- *msg
		return ch, false
	}

	// Register waiter
	if s.waiters[rid] == nil {
		s.waiters[rid] = make(map[string]chan WebSocketMessage)
	}
	s.waiters[rid][waiterID] = ch
	return ch, true
}

// WaitForMessage blocks until a message is available for the given rid.
// Returns immediately if the request is already in a terminal state.
func (s *Storage) WaitForMessage(rid string, waiterID string) WebSocketMessage {
	ch, _ := s.RegisterWaiter(rid, waiterID)
	return <-ch
}

// CancelWait cancels all waiters for a request.
func (s *Storage) CancelWait(rid string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.notifyWaiters(rid, WebSocketMessage{
		Type:    "error",
		Payload: ErrorPayload{Code: "cancelled", Message: "Waiting cancelled"},
	})
}

// RemoveWaiter sends a cancellation message to a specific waiter and removes it.
// This ensures the goroutine blocked on WaitForMessage will unblock.
func (s *Storage) RemoveWaiter(rid string, waiterID string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if w := s.waiters[rid]; w != nil {
		if ch, ok := w[waiterID]; ok {
			select {
			case ch <- WebSocketMessage{
				Type:    "error",
				Payload: ErrorPayload{Code: "cancelled", Message: "Waiting cancelled"},
			}:
			default:
			}
			delete(w, waiterID)
		}
		if len(w) == 0 {
			delete(s.waiters, rid)
		}
	}
}

type APNTokenBlocker struct {
	mu       sync.Mutex
	failures map[string]int
	blocked  map[string]time.Time
	tokenIPs map[string]string
	ipFails  map[string]int
	ipBlock  map[string]time.Time
}

func NewAPNTokenBlocker() *APNTokenBlocker {
	return &APNTokenBlocker{
		failures: make(map[string]int),
		blocked:  make(map[string]time.Time),
		tokenIPs: make(map[string]string),
		ipFails:  make(map[string]int),
		ipBlock:  make(map[string]time.Time),
	}
}

func (b *APNTokenBlocker) IsBlocked(token string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()

	now := time.Now()
	b.clearExpiredLocked(now)

	if token == "" {
		return false
	}
	if until, ok := b.blocked[token]; ok && until.After(now) {
		return true
	}
	if ip := b.tokenIPs[token]; ip != "" {
		if until, ok := b.ipBlock[ip]; ok && until.After(now) {
			return true
		}
	}
	return false
}

func (b *APNTokenBlocker) RecordFailure(token, ip string) {
	b.mu.Lock()
	defer b.mu.Unlock()

	now := time.Now()
	b.clearExpiredLocked(now)

	if token != "" {
		b.tokenIPs[token] = ip
		b.failures[token]++
		if b.failures[token] >= 3 {
			b.blocked[token] = now.Add(5 * time.Minute)
			b.failures[token] = 0
		}
	}

	if ip != "" {
		b.ipFails[ip]++
		if b.ipFails[ip] >= 3 {
			b.ipBlock[ip] = now.Add(5 * time.Minute)
			b.ipFails[ip] = 0
		}
	}
}

func (b *APNTokenBlocker) RecordSuccess(token, ip string) {
	b.mu.Lock()
	defer b.mu.Unlock()

	if token != "" {
		delete(b.failures, token)
		delete(b.blocked, token)
		if ip != "" {
			b.tokenIPs[token] = ip
		}
	}
	if ip != "" {
		delete(b.ipFails, ip)
		delete(b.ipBlock, ip)
	}
}

func (b *APNTokenBlocker) Cleanup() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.clearExpiredLocked(time.Now())
}

func (b *APNTokenBlocker) clearExpiredLocked(now time.Time) {
	for token, until := range b.blocked {
		if !until.After(now) {
			delete(b.blocked, token)
		}
	}
	for ip, until := range b.ipBlock {
		if !until.After(now) {
			delete(b.ipBlock, ip)
		}
	}
	for token, ip := range b.tokenIPs {
		if ip == "" {
			delete(b.tokenIPs, token)
			continue
		}
		if _, blocked := b.blocked[token]; blocked {
			continue
		}
		if _, failing := b.failures[token]; failing {
			continue
		}
		if _, blocked := b.ipBlock[ip]; blocked {
			continue
		}
		if _, failing := b.ipFails[ip]; failing {
			continue
		}
		delete(b.tokenIPs, token)
	}
}

// notifyWaiters sends a message to all waiters for a rid and removes them.
// Must be called with s.mu held.
func (s *Storage) notifyWaiters(rid string, msg WebSocketMessage) {
	waiters := s.waiters[rid]
	if waiters == nil {
		return
	}
	delete(s.waiters, rid)
	for _, ch := range waiters {
		select {
		case ch <- msg:
		default:
		}
	}
}

// immediateMessage checks if a request already has a result to return.
// Must be called with s.mu held.
func (s *Storage) immediateMessage(rid string) *WebSocketMessage {
	r := s.requests[rid]
	if r == nil {
		msg := WebSocketMessage{
			Type:    "error",
			Payload: ErrorPayload{Code: "missing", Message: "Request not found"},
		}
		return &msg
	}

	if r.Status == StatusReady && r.EncryptedSession != nil {
		msg := WebSocketMessage{
			Type: "session",
			Payload: SessionPayload{
				DeliveredAt:      nowISO8601(),
				EncryptedSession: *r.EncryptedSession,
			},
		}
		return &msg
	}

	if r.Status == StatusExpired {
		msg := WebSocketMessage{
			Type:    "error",
			Payload: ErrorPayload{Code: "expired", Message: "Request has expired"},
		}
		return &msg
	}

	if r.Status != StatusPending {
		msg := WebSocketMessage{
			Type:    "status",
			Payload: StatusPayload{Status: r.Status, Timestamp: nowISO8601()},
		}
		return &msg
	}

	if r.ExpiresAt.Before(time.Now()) {
		msg := WebSocketMessage{
			Type:    "error",
			Payload: ErrorPayload{Code: "expired", Message: "Request has expired"},
		}
		return &msg
	}

	return nil
}
