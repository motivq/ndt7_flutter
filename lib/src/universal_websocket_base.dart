// lib/src/universal_websocket_base.dart

/// The shared interface for a universal WebSocket.
abstract class UniversalWebSocketBase {
  /// Connect to the specified [url] with optional [protocols].
  static Future<UniversalWebSocketBase> connect(
    String url, {
    Iterable<String>? protocols,
  }) {
    throw UnimplementedError(
        'UniversalWebSocketBase.connect() not implemented');
  }

  /// Sends either a String (text) or binary data over the WebSocket.
  void send(dynamic data);

  /// A stream of messages from the WebSocket.
  /// Each message may be a String, Uint8List, or ByteBuffer.
  Stream<dynamic> get stream;

  /// Closes the underlying connection.
  Future<void> close();
}
