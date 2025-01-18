// lib/src/universal_websocket.dart

import 'universal_websocket_stub.dart'
    if (dart.library.io) 'universal_websocket_io.dart'
    if (dart.library.html) 'universal_websocket_html.dart';

export 'universal_websocket_stub.dart'
    if (dart.library.io) 'universal_websocket_io.dart'
    if (dart.library.html) 'universal_websocket_html.dart';

/// A convenience function that calls the correct `connect` method
/// from whichever UniversalWebSocket was chosen at compile-time.
Future<UniversalWebSocket> universalConnect(
  String url, {
  Iterable<String>? protocols,
}) {
  print(
      '[universal_websocket aggregator] universalConnect => $url, protocols=$protocols');
  return UniversalWebSocket.connect(url, protocols: protocols);
}
