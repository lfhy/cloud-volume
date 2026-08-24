// Web task events intentionally use the store's polling fallback: the desktop
// debug socket is localhost-only and must never be attempted from a browser.

class TaskEventsHandle {
  TaskEventsHandle._();

  void dispose() {}
}

TaskEventsHandle watchTaskEvents(String wsUrl, void Function() onTick) =>
    TaskEventsHandle._();
