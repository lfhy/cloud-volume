// Response visibility keeps active-only polling separate from queue counts:
// the server counts all matching rows but returns only unsettled rows to polls.
package main

// remoteTaskCountInput keeps terminal history in scope for header/tab totals;
// includeHistory is a response-row visibility option, not a count filter.
func remoteTaskCountInput(input remoteTaskListArgs) remoteTaskListArgs {
	input.IncludeHistory = true
	return input
}

// remoteTaskResponseItems filters response rows after queue totals were
// computed. Failed/conflict rows stay visible because activeTaskStates treats
// them as unsettled attention work, while done/canceled become history only.
func remoteTaskResponseItems(items []any, includeHistory bool) []any {
	if includeHistory {
		return items
	}
	visible := make([]any, 0, len(items))
	active := activeTaskStates()
	for _, raw := range items {
		item, ok := raw.(map[string]any)
		if ok && active[taskWireString(item, "status")] {
			visible = append(visible, raw)
		}
	}
	return visible
}
