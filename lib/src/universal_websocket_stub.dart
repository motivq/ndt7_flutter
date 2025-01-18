// lib/src/universal_websocket_stub.dart

import 'package:ndt7/src/universal_websocket_base.dart';

class UniversalWebSocket extends UniversalWebSocketBase {
  UniversalWebSocket._();

  static Future<UniversalWebSocket> connect(
    String url, {
    Iterable<String>? protocols,
  }) async {
    print('[universal_websocket_stub] connect() => $url, protocols=$protocols');
    throw UnsupportedError(
        'No WebSocket implementation available for this platform');
  }

  @override
  void send(dynamic data) {
    throw UnsupportedError('No WebSocket implementation available');
  }

  @override
  Stream<dynamic> get stream => const Stream.empty();

  @override
  Future<void> close() async {
    throw UnsupportedError('No WebSocket implementation available');
  }
}
