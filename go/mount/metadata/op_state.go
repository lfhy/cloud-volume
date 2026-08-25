package metadata

// Journal state helpers keep worker scheduling, reset guards, and task
// projection aligned. A failed operation remains unsettled until the caller
// explicitly retries it; all other listed states may still need provider work.
func opStateUnsettled(state OpState) bool {
	switch state {
	case OpStatePending, OpStateRunning, OpStateFailed,
		OpStateReconciling, OpStateVerifying, OpStateCancelRequested:
		return true
	default:
		return false
	}
}

func opStateReady(state OpState) bool {
	return state == OpStatePending || state == OpStateFailed ||
		state == OpStateReconciling || state == OpStateVerifying ||
		state == OpStateCancelRequested
}

func opStateNeedsReconciliation(state OpState) bool {
	return state == OpStateReconciling || state == OpStateVerifying ||
		state == OpStateCancelRequested
}
