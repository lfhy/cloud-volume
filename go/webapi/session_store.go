// Session store keeps browser login state in memory for the web server.
package webapi

import (
	"crypto/rand"
	"encoding/hex"
	"sync"
	"time"
)

const sessionTTL = 12 * time.Hour

type sessionStore struct {
	mu       sync.Mutex
	sessions map[string]time.Time
}

func newSessionStore() *sessionStore {
	return &sessionStore{sessions: map[string]time.Time{}}
}

func (s *sessionStore) Create() (string, time.Time, error) {
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		return "", time.Time{}, err
	}
	token := hex.EncodeToString(tokenBytes)
	expiresAt := time.Now().Add(sessionTTL)
	s.mu.Lock()
	s.sessions[token] = expiresAt
	s.mu.Unlock()
	return token, expiresAt, nil
}

func (s *sessionStore) Valid(token string) bool {
	if token == "" {
		return false
	}
	now := time.Now()
	s.mu.Lock()
	defer s.mu.Unlock()
	for existingToken, expiresAt := range s.sessions {
		if now.After(expiresAt) {
			delete(s.sessions, existingToken)
		}
	}
	expiresAt, ok := s.sessions[token]
	return ok && now.Before(expiresAt)
}

func (s *sessionStore) Delete(token string) {
	if token == "" {
		return
	}
	s.mu.Lock()
	delete(s.sessions, token)
	s.mu.Unlock()
}

func (s *sessionStore) Reset() {
	s.mu.Lock()
	s.sessions = map[string]time.Time{}
	s.mu.Unlock()
}
