// Serialized task-list reads: active polling and history pages share one gate
// so a page-entry load cannot race a cursor-owning refresh from another view.
part of 'remote_task_store.dart';

extension RemoteTaskStorePolling on RemoteTaskStore {
  // Active-only polling keeps every unsettled task on page one. It joins a
  // history request already in flight rather than interleaving another read.
  Future<void> pollActive() {
    if (_api == null) return Future<void>.value();
    final inFlightRead = _inFlightRead;
    if (inFlightRead != null) return inFlightRead;
    return _startRead(_pollActive);
  }

  /// Runs [read] after publishing its future synchronously, which also covers
  /// a gateway implementation that throws before returning a Future.
  Future<void> _startRead(Future<void> Function() read) {
    final completion = Completer<void>();
    final future = completion.future;
    _inFlightRead = future;
    unawaited(_completeRead(read, completion, future));
    return future;
  }

  Future<void> _completeRead(
    Future<void> Function() read,
    Completer<void> completion,
    Future<void> future,
  ) async {
    try {
      await read();
    } catch (error) {
      // Endpoint errors are normally handled by the request body. Keep this
      // fallback so an unexpected synchronous gateway failure still releases
      // the read gate for a later retry.
      _lastError = error;
      notifyListenersChanged();
    } finally {
      if (identical(_inFlightRead, future)) _inFlightRead = null;
      completion.complete();
    }
  }

  Future<void> _pollActive() async {
    final generation = _bindingGeneration;
    final api = _api;
    if (api == null) return;
    _polling = true;
    try {
      var cursor = '';
      do {
        final filter = RemoteTaskFilter(includeHistory: false, cursor: cursor);
        final page = await api.listRemoteTasks(filter);
        if (generation != _bindingGeneration || !identical(api, _api)) return;
        _mergeRemoteTasks(
          page.items,
          purgeMissingActive: cursor.isEmpty,
          // `total` covers the complete server projection even though this
          // request returns active rows only. A real zero is therefore a
          // definitive empty snapshot, not merely an empty active page.
          purgeAllWhenExplicitlyEmpty:
              page.hasTotal && page.total == 0 && page.items.isEmpty,
        );
        // Queue counts describe the complete queue, not just this active
        // response. A genuine all-zero report must still clear stale values.
        _applyQueue(page.queue);
        _total = page.total;
        _hasServerTotal = page.hasTotal;
        _freshness = page.freshness;
        _capabilities = Map<String, bool>.unmodifiable(page.capabilities);
        cursor = page.nextCursor;
      } while (cursor.isNotEmpty);
      if (!_hasLoadedMore) _nextCursor = '';
      _lastError = null;
      _lastFreshAt = DateTime.now();
      notifyListenersChanged();
    } catch (error) {
      if (generation != _bindingGeneration) return;
      _lastError = error;
      notifyListenersChanged();
    } finally {
      if (generation == _bindingGeneration) {
        _polling = false;
        _ensurePolling();
      }
    }
  }

  /// Refreshes one requested scope. Calls that overlap a read join it; callers
  /// that need a specific history page use loadMore(), which retries afterward.
  Future<void> refresh([RemoteTaskFilter filter = const RemoteTaskFilter()]) {
    if (_api == null) return Future<void>.value();
    final inFlightRead = _inFlightRead;
    if (inFlightRead != null) return inFlightRead;
    return _startRead(() => _refresh(filter));
  }

  Future<void> _refresh(RemoteTaskFilter filter) async {
    final generation = _bindingGeneration;
    final historyEpoch = _historyEpoch;
    final api = _api;
    if (api == null) return;
    _polling = true;
    try {
      final page = await api.listRemoteTasks(filter);
      if (generation != _bindingGeneration || !identical(api, _api)) return;
      // A clear invalidates every cursor-derived history response that was
      // already in flight, so it cannot resurrect deleted rows afterward.
      if (filter.includeHistory && historyEpoch != _historyEpoch) return;
      // A terminal completion can land after the active-only poll that gave us
      // this offset. Its newest-first insertion shifts every later cursor, so
      // invalidate a stale continuation rather than merging a skipped page.
      final historyStreamInvalidated = _applyQueue(page.queue);
      _total = page.total;
      _hasServerTotal = page.hasTotal;
      if (!_hasServerTotal && _total == 0 && _tasks.isNotEmpty) {
        _total = _tasks.length;
      }
      _freshness = page.freshness;
      _capabilities = Map<String, bool>.unmodifiable(page.capabilities);
      if (filter.includeHistory &&
          filter.cursor.isNotEmpty &&
          historyStreamInvalidated) {
        _lastError = null;
        _lastFreshAt = DateTime.now();
        notifyListenersChanged();
        return;
      }
      // A request without history or pagination never describes the full
      // task set, so it must not purge rows a loadMore call already merged.
      final completeSnapshot =
          filter.includeHistory &&
          filter.cursor.isEmpty &&
          page.nextCursor.isEmpty;
      // An active-only poll describes the FULL active set: any locally cached
      // row that is still marked active but absent from the response has
      // actually finished and must be dropped, otherwise the UI keeps showing
      // "进行中/等待" rows forever after they complete.
      final purgeMissingActive =
          !filter.includeHistory && filter.cursor.isEmpty;
      _mergeRemoteTasks(
        page.items,
        completeSnapshot: completeSnapshot,
        purgeMissingActive: purgeMissingActive,
        purgeAllWhenExplicitlyEmpty:
            page.hasTotal && page.total == 0 && page.items.isEmpty,
      );
      // Remember the server's unpaged total so the header can show the true
      // queue size even while only the first history page is cached locally.
      // The server always returns total (pre-pagination). Treat 0 as
      // empty; older binaries that omitted total fall back to cache size.
      // Cursor ownership: a paged history request owns the cursor outright,
      // so an exhausted stream clears it and hides 加载更多历史. An active-only
      // poll may refresh the cursor but must never clear one that a previous
      // loadMore already established.
      if (filter.cursor.isNotEmpty) {
        _nextCursor = page.nextCursor;
        _hasLoadedMore = true;
      } else if (!_hasLoadedMore &&
          !(filter.includeHistory && page.nextCursor.isEmpty)) {
        _nextCursor = page.nextCursor;
      }
      _lastError = null;
      _lastFreshAt = DateTime.now();
      notifyListenersChanged();
    } catch (error) {
      if (generation != _bindingGeneration) return;
      _lastError = error;
      // Keep the last known remote projection for continuity, but never copy
      // TransferQueue entries into it.
      notifyListenersChanged();
    } finally {
      if (generation == _bindingGeneration) {
        _polling = false;
        _ensurePolling();
      }
    }
  }
}
