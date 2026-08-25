// Response visibility keeps active-only polling separate from queue counts:
// the server counts all matching rows but returns only unsettled rows to polls.
package webapi

// webRemoteTaskCountInput keeps terminal history in scope for header/tab
// totals; includeHistory is a response-row visibility option, not a count filter.
func webRemoteTaskCountInput(input invokeEnvelope) invokeEnvelope {
	input.IncludeHistory = true
	return input
}

// webRemoteTaskResponseItems filters response rows after queue totals were
// computed. Failed/conflict rows stay visible as attention work; done/canceled
// rows are omitted only from active-only poll responses.
func webRemoteTaskResponseItems(items []any, includeHistory bool) []any {
	if includeHistory {
		return items
	}
	visible := make([]any, 0, len(items))
	active := webActiveTaskStates()
	for _, raw := range items {
		item, ok := raw.(map[string]any)
		if ok && active[webTaskString(item, "status")] {
			visible = append(visible, raw)
		}
	}
	return visible
}
