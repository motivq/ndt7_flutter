// lib/src/universal_websocket_html.dart
//
// Used if dart.library.html is available (web).
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:ndt7/src/universal_websocket_base.dart';

class UniversalWebSocket extends UniversalWebSocketBase {
  final html.WebSocket _socket;
  final StreamController<dynamic> _controller = StreamController<dynamic>();

  UniversalWebSocket._(this._socket) {
    _socket.binaryType = 'arraybuffer';

    _socket.onMessage.listen((event) {
      final data = event.data;
      _controller.add(data);
    }, onError: (err, st) {
      _controller.addError(err, st);
      _controller.close();
    }, onDone: () {
      _controller.close();
    });
  }

  static Future<UniversalWebSocket> connect(
    String url, {
    Iterable<String>? protocols,
  }) {
    print('[universal_websocket_html] connect() => $url, protocols=$protocols');
    final completer = Completer<UniversalWebSocket>();
    final ws = html.WebSocket(url, protocols);
    ws.binaryType = 'arraybuffer';

    ws.onOpen.first.then((_) {
      print('[universal_websocket_html] connect => success');
      completer.complete(UniversalWebSocket._(ws));
    });
    ws.onError.first.then((_) {
      completer.completeError('WebSocket connection failed to $url');
    });

    return completer.future;
  }

  @override
  void send(dynamic data) {
    if (data is String) {
      _socket.sendString(data);
    } else if (data is List<int>) {
      _socket.sendByteBuffer(Uint8List.fromList(data).buffer);
    } else if (data is Uint8List) {
      _socket.sendByteBuffer(data.buffer);
    } else if (data is ByteBuffer) {
      _socket.sendByteBuffer(data);
    }
  }

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  Future<void> close() async {
    print('[universal_websocket_html] closing socket');
    _socket.close();
    await _controller.close();
  }
}
