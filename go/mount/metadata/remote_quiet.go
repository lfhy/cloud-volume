// Namespace-wide quiet tracking keeps recursive local mutations off the provider.
package metadata

import "time"

type remoteMutation struct {
	service  *Service
	deadline int64
}

// beginRemoteMutation serializes a local journal commit with worker claims.
// Its finish method must receive true only after that commit records at least
// one new remote operation.
func (s *Service) beginRemoteMutation() *remoteMutation {
	s.remoteQuietMu.Lock()
	return &remoteMutation{service: s}
}

// nextAttempt is intentionally called inside the bbolt transaction, after it
// has obtained the store write slot. A queued transaction must receive its
// full quiet interval from journal admission, not from lock contention before
// that point.
func (m *remoteMutation) nextAttempt() int64 {
	if m.deadline == 0 {
		m.deadline = time.Now().Add(m.service.quietPeriod()).UnixNano()
	}
	return m.deadline
}

// finish releases the quiet gate and, when the transaction committed at least
// one remote operation, notifies task subscribers so push clients re-fetch.
func (m *remoteMutation) finish(committed bool) {
	if committed {
		if m.deadline > m.service.remoteQuietUntilNano {
			m.service.remoteQuietUntilNano = m.deadline
		}
		m.service.NotifyTaskChanged()
	}
	m.service.remoteQuietMu.Unlock()
}

// remoteQuietDeadline returns the current namespace mutation barrier. It is
// deliberately in-memory; pending journal timestamps rebuild its remainder on
// restart and bbolt remains the source of durable operation intent.
func (s *Service) remoteQuietDeadline() int64 {
	s.remoteQuietMu.Lock()
	defer s.remoteQuietMu.Unlock()
	return s.remoteQuietUntilNano
}

// rebuildRemoteQuietDeadline restores the remaining quiet period after a
// service reopen or policy change. A manually triggered operation still keeps
// other work quiet; only its own one-shot SkipQuiet flag bypasses the barrier.
func (s *Service) rebuildRemoteQuietDeadline() {
	quiet := s.quietPeriod()
	s.remoteQuietMu.Lock()
	defer s.remoteQuietMu.Unlock()
	var latest int64
	_ = s.store.view(func(tx boltTxT) error {
		return tx.Bucket([]byte(bucketJournal)).ForEach(func(_, value []byte) error {
			var op Op
			if decodeJSON(value, &op) != nil || op.State != OpStatePending || op.CreatedAtUnixNano == 0 {
				return nil
			}
			candidate := op.CreatedAtUnixNano + quiet.Nanoseconds()
			if candidate > latest {
				latest = candidate
			}
			return nil
		})
	})
	if latest <= time.Now().UnixNano() {
		latest = 0
	}
	s.remoteQuietUntilNano = latest
}

// clearRemoteQuietDeadline drops transient timing state after a namespace
// reset has removed every journal operation that could justify it.
func (s *Service) clearRemoteQuietDeadline() {
	s.remoteQuietMu.Lock()
	s.remoteQuietUntilNano = 0
	s.remoteQuietMu.Unlock()
}
