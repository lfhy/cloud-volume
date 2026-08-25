// IO push channel: metadata workers tick a localhost websocket so the task
// store refreshes immediately; the Web conditional import uses a polling stub.

import 'dart:async';
import 'dart:io';

/// Watches the bridge task-event websocket and invokes [onTick] for every
/// coalesced change signal. Returns a stop function.
TaskEventsHandle watchTaskEvents(String wsUrl, void Function() onTick) {
  return TaskEventsHandle._(wsUrl, onTick);
}

class TaskEventsHandle {
  TaskEventsHandle._(String wsUrl, void Function() onTick) {
    unawaited(_run(wsUrl, onTick));
  }

  bool _stopped = false;
  WebSocket? _socket;

  void dispose() {
    _stopped = true;
    // Close the live socket too: without this, a rebind leaks a connection
    // whose await-for keeps the run loop parked forever.
    final socket = _socket;
    _socket = null;
    unawaited(socket?.close());
  }

  // Raw WebSocket handshake over dart:io keeps this dependency-free.
  Future<void> _run(String wsUrl, void Function() onTick) async {
    while (!_stopped) {
      WebSocket? socket;
      try {
        socket = await WebSocket.connect(wsUrl);
        // dispose can race the asynchronous TCP/WebSocket handshake. Do not
        // leave a newly connected old handle parked in await-for afterward.
        if (_stopped) {
          await socket.close();
          return;
        }
        _socket = socket;
        socket.pingInterval = const Duration(seconds: 20);
        await for (final message in socket) {
          if (_stopped) break;
          if (message is String && message.contains('changed')) {
            onTick();
          }
        }
      } catch (_) {
        // The push listener is optional; polling remains the fallback.
      }
      _socket = null;
      await socket?.close();
      if (_stopped) return;
      // Reconnect with a modest backoff so a socket outage degrades to the
      // polling cadence instead of a busy loop.
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}
