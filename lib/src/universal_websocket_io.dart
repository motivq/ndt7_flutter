// lib/src/universal_websocket_io.dart
//
// Used if dart.library.io is available (mobile, desktop).
import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:ndt7/src/universal_websocket_base.dart';

class UniversalWebSocket extends UniversalWebSocketBase {
  final io.WebSocket _socket;

  UniversalWebSocket(this._socket);

  static Future<UniversalWebSocket> connect(
    String url, {
    Iterable<String>? protocols,
  }) async {
    print('[universal_websocket_io] connect() => $url, protocols=$protocols');
    final socket = await io.WebSocket.connect(url, protocols: protocols);
    print('[universal_websocket_io] connect => success');
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
    print('[universal_websocket_io] closing socket');
    await _socket.close();
  }
}
