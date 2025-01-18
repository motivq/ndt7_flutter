// lib/src/upload_isolate.dart
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math';

class UploadMessage {
  final int currentSize;
  final int totalBytesSent;
  final int elapsedMicros;
  final Uint8List data;

  UploadMessage({
    required this.currentSize,
    required this.totalBytesSent,
    required this.elapsedMicros,
    required this.data,
  });
}

void uploadIsolateFunction(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  int currentSize = 8192; // Initial size (8KB)
  int totalBytesSent = 0;
  final maxSize = 8388608; // 8MB max
  final random = Random.secure();

  receivePort.listen((message) {
    if (message == 'generate') {
      // Create the payload
      final data = Uint8List(currentSize);
      for (int i = 0; i < currentSize; i++) {
        data[i] = random.nextInt(256);
      }

      totalBytesSent += currentSize;

      // Scale up message size if needed (every 16 messages)
      if (currentSize < maxSize) {
        if (totalBytesSent >= 16 * currentSize) {
          currentSize *= 2;
          if (currentSize > maxSize) currentSize = maxSize;
        }
      }

      // Send back the generated data and metadata
      sendPort.send(UploadMessage(
        currentSize: currentSize,
        totalBytesSent: totalBytesSent,
        elapsedMicros: DateTime.now().microsecondsSinceEpoch,
        data: data,
      ));
    } else if (message == 'stop') {
      Isolate.exit();
    }
  });
}
