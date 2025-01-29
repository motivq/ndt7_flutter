// lib/src/universal_websocket_io.dart
//
// Used if dart.library.io is available (mobile, desktop).
import 'dart:async';
import 'dart:io' as io;

import 'package:ndt7/src/universal_websocket_base.dart';

void _log(String message, {Map<String, dynamic>? data}) {
  const bool isProduction = bool.fromEnvironment('dart.vm.product');

  if (!isProduction) {
    final logData = {
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'DEBUG',
      'component': 'UniversalWebSocket',
      'message': message,
      if (data != null) ...data,
    };

    // Format log entry
    final logEntry = '[${logData['timestamp']}] '
        '[${logData['level']}] '
        '[${logData['component']}] '
        '${logData['message']}';

    if (data != null) {
      final dataStr = data.entries.map((e) => '${e.key}=${e.value}').join(', ');
      // ignore: avoid_print
      print('$logEntry | $dataStr');
    } else {
      // ignore: avoid_print
      print(logEntry);
    }
  }
}

class UniversalWebSocket extends UniversalWebSocketBase {
  final io.WebSocket _socket;

  UniversalWebSocket(this._socket);

  static Future<UniversalWebSocket> connect(
    String url, {
    Iterable<String>? protocols,
  }) async {
    _log('[universal_websocket_io] connect() => $url, protocols=$protocols');
    final socket = await io.WebSocket.connect(url, protocols: protocols);
    _log('[universal_websocket_io] connect => success');
    return UniversalWebSocket(socket);
  }

  @override
  void send(dynamic data) {
    _socket.add(data);
  }

  @override
  Stream<dynamic> get stream => _socket;

  @override
  Future<void> close() async {
    _log('[universal_websocket_io] closing socket');
    await _socket.close();
  }
}
