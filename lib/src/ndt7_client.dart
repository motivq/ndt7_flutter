// lib/src/ndt7_client.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// NDT7 data classes
import 'ndt7_measurement.dart';
import 'universal_websocket.dart';
import 'mlab_discovery.dart';

// For isolate / worker logic:
import 'package:isolates_helper/isolates_helper.dart';

/// The function the worker uses to generate random data of the requested size.
/// We use a top-level function so that `isolates_helper` can create a web worker / isolate.
@isolatesHelperWorker
List<int> makeRandomPayloadWorker(List<int> params) {
  final size = params[0];
  final rng = Random();
  final data = List<int>.generate(size, (_) => 65 + rng.nextInt(57));
  return data;
}

/// Default subprotocol required by ndt7
const ndt7WebSocketSubProtocol = 'net.measurementlab.ndt.v7';

/// Default path for download/upload
const ndt7DownloadPath = '/ndt/v7/download';
const ndt7UploadPath = '/ndt/v7/upload';

/// Default durations
const defaultDownloadTestDuration = Duration(seconds: 15);
const defaultUploadTestDuration = Duration(seconds: 10);

/// Maximum message size = 16 MiB
const maxMessageSize = 1 << 24;

/// Initial upload chunk size = 8 KiB
const initialUploadMessageSize = 1 << 13;

/// We'll double the chunk if chunkSize < totalSoFar / scalingFraction
const scalingFraction = 16;

/// We'll produce "client-based" measurements every 250 ms
const clientMeasurementInterval = Duration(milliseconds: 250);

/// If no scheme is provided, use 'wss'
const defaultScheme = 'wss';

/// A pure-Dart NDT7 client supporting the isolates_helper approach for random data generation.
class Ndt7Client {
  final String host;
  final String scheme;
  final String queryParams;
  final Duration downloadTestDuration;
  final Duration uploadTestDuration;
  final String? _fullDownloadUrl;
  final String? _fullUploadUrl;

  // We'll store an IsolatesHelper instance here, so we can reuse it for the entire test.
  // concurrency=1 is enough to saturate most links, but you can try 2 or 3.
  final IsolatesHelper isolates = IsolatesHelper(
    concurrent: 1,
    // Optional: 'worker' if you want custom worker name, or isDebug
  );

  Ndt7Client({
    required this.host,
    this.scheme = defaultScheme,
    this.queryParams = '',
    this.downloadTestDuration = defaultDownloadTestDuration,
    this.uploadTestDuration = defaultUploadTestDuration,
  })  : _fullDownloadUrl = null,
        _fullUploadUrl = null;

  Ndt7Client._withFullUrls({
    required String fullDownloadUrl,
    required String fullUploadUrl,
    required String fallbackHost,
    this.downloadTestDuration = defaultDownloadTestDuration,
    this.uploadTestDuration = defaultUploadTestDuration,
  })  : _fullDownloadUrl = fullDownloadUrl,
        _fullUploadUrl = fullUploadUrl,
        host = fallbackHost,
        scheme = defaultScheme,
        queryParams = '';

  /// Legacy approach that only obtains a host from older M-Lab locate
  static Future<Ndt7Client> withMlab({
    String userAgent = 'ndt7-dart/1.0',
    String scheme = defaultScheme,
    String queryParams = '',
    Duration downloadTestDuration = defaultDownloadTestDuration,
    Duration uploadTestDuration = defaultUploadTestDuration,
  }) async {
    final discoveredHost =
        await MLabDiscovery.discoverServer(userAgent: userAgent);
    return Ndt7Client(
      host: discoveredHost,
      scheme: scheme,
      queryParams: queryParams,
      downloadTestDuration: downloadTestDuration,
      uploadTestDuration: uploadTestDuration,
    );
  }

  /// Modern approach that obtains full wss:// URLs (with tokens) from M-Lab locate
  static Future<Ndt7Client> withMlabUrls({
    String userAgent = 'ndt7-dart/1.0',
    Duration downloadTestDuration = defaultDownloadTestDuration,
    Duration uploadTestDuration = defaultUploadTestDuration,
  }) async {
    final urls =
        await MLabDiscovery.discoverServerWithUrls(userAgent: userAgent);
    return Ndt7Client._withFullUrls(
      fullDownloadUrl: urls.downloadUrl,
      fullUploadUrl: urls.uploadUrl,
      fallbackHost: urls.fqdn ?? '',
      downloadTestDuration: downloadTestDuration,
      uploadTestDuration: uploadTestDuration,
    );
  }

  // ----------------------------------------------------------------------------
  // Download test: normal approach, not using isolates for random data,
  // because the server is the one sending data in download.
  // ----------------------------------------------------------------------------
  Stream<Ndt7Measurement> startDownload() async* {
    final uri =
        _fullDownloadUrl ?? '$scheme://$host$ndt7DownloadPath$queryParams';
    print('[startDownload] => $uri');

    final controller = StreamController<Ndt7Measurement>();
    final cutoffTimer = Timer(downloadTestDuration, () {
      if (!controller.isClosed) controller.close();
    });

    try {
      // Make sure the isolates are started if we want them for something else
      await isolates.ensureStarted;

      final socket =
          await universalConnect(uri, protocols: [ndt7WebSocketSubProtocol]);
      print('[startDownload] WebSocket connected OK');

      // Listen for server messages (binary => measure, text => parse JSON)
      _listenForDownload(socket, controller);

      final startTime = DateTime.now();
      int totalBytes = 0;

      // 250ms "client-based" measurement
      final measureTimer = Timer.periodic(clientMeasurementInterval, (_) {
        if (!controller.isClosed) {
          final elapsedUs = DateTime.now().difference(startTime).inMicroseconds;
          final meas = Ndt7Measurement(
            appInfo:
                AppInfo(elapsedTimeMicros: elapsedUs, numBytes: totalBytes),
            origin: 'client',
            test: 'download',
          );
          controller.add(meas);
        }
      });

      yield* controller.stream
          .handleError((err, st) {
            print('[startDownload] error => $err');
            if (!controller.isClosed) {
              controller.add(Ndt7Measurement(
                error: err.toString(),
                stackTrace: st?.toString(),
                test: 'download',
              ));
              controller.close();
            }
          })
          .map((m) {
            // If it's a synthetic event for counting binary
            if (m.internalBinaryDownloadCount != null) {
              totalBytes += m.internalBinaryDownloadCount!;
              return Ndt7Measurement.empty();
            }
            return m;
          })
          .where((m) => !m.isEmpty())
          .doOnDone(() {
            print('[startDownload] done => cleanup');
            measureTimer.cancel();
            cutoffTimer.cancel();
            socket.close();
          })
          .doOnCancel(() {
            print('[startDownload] canceled => cleanup');
            measureTimer.cancel();
            cutoffTimer.cancel();
            socket.close();
          });
    } catch (err, st) {
      yield Ndt7Measurement(
        error: err.toString(),
        stackTrace: st.toString(),
        test: 'download',
      );
    }
  }

  // ----------------------------------------------------------------------------
  // Upload test using isolates_helper for random data generation
  // ----------------------------------------------------------------------------
  Stream<Ndt7Measurement> startUpload() async* {
    final uri = _fullUploadUrl ?? '$scheme://$host$ndt7UploadPath$queryParams';
    print('[startUpload] => $uri');

    final controller = StreamController<Ndt7Measurement>();
    final cutoffTimer = Timer(uploadTestDuration, () {
      if (!controller.isClosed) controller.close();
    });

    try {
      // Ensure the worker is started
      await isolates.ensureStarted;

      final socket =
          await universalConnect(uri, protocols: [ndt7WebSocketSubProtocol]);
      print('[startUpload] WebSocket connected OK');

      // Listen for server messages (server's "counterflow" text messages).
      _listenForUpload(socket, controller);

      final startTime = DateTime.now();
      int totalSoFar = 0;
      int currentSize = initialUploadMessageSize;

      // We'll do a saturating loop that continuously requests random data from the isolate
      // and sends it. We'll run in a microtask approach so we don't block the event loop entirely.
      bool keepRunning = true;

      void uploadLoop() async {
        while (keepRunning && !controller.isClosed) {
          // 1) if we passed test time, break
          if (DateTime.now().difference(startTime) >= uploadTestDuration) {
            print('[uploadLoop] reached uploadTestDuration => closing');
            if (!controller.isClosed) controller.close();
            break;
          }

          // 2) get random payload from worker
          //    We'll pass [currentSize] as the param list
          List<int>? chunk;
          try {
            chunk = await isolates.compute(
              makeRandomPayloadWorker,
              [currentSize],
              workerFunction: 'makeRandomPayloadWorker', // optional
            );
          } catch (err) {
            print('[uploadLoop] error getting random data => $err');
            if (!controller.isClosed) {
              controller
                  .add(Ndt7Measurement(error: err.toString(), test: 'upload'));
              controller.close();
            }
            break;
          }

          // 3) send that chunk to the server
          try {
            socket.send(Uint8List.fromList(chunk));
          } catch (sendErr) {
            print('[uploadLoop] socket.send error => $sendErr');
            if (!controller.isClosed) {
              controller.add(
                  Ndt7Measurement(error: sendErr.toString(), test: 'upload'));
              controller.close();
            }
            break;
          }

          // 4) update totalSoFar
          totalSoFar += currentSize;

          // 5) scale chunk if needed
          if (currentSize < maxMessageSize) {
            if (currentSize < (totalSoFar ~/ scalingFraction)) {
              currentSize *= 2;
              if (currentSize > maxMessageSize) currentSize = maxMessageSize;
            }
          }

          // yield back so we don't block everything
          await Future(() {});
        }
      }

      uploadLoop(); // start in the background

      // Meanwhile, produce "client-based" measurement every 250ms
      final measureTimer = Timer.periodic(clientMeasurementInterval, (_) {
        if (!controller.isClosed) {
          final elapsedUs = DateTime.now().difference(startTime).inMicroseconds;
          final meas = Ndt7Measurement(
            appInfo:
                AppInfo(elapsedTimeMicros: elapsedUs, numBytes: totalSoFar),
            origin: 'client',
            test: 'upload',
          );
          controller.add(meas);
        }
      });

      yield* controller.stream.handleError((err, st) {
        print('[startUpload] error => $err');
        if (!controller.isClosed) {
          controller.add(Ndt7Measurement(
            error: err.toString(),
            stackTrace: st?.toString(),
            test: 'upload',
          ));
          controller.close();
        }
      }).doOnDone(() {
        print('[startUpload] done => cleanup');
        keepRunning = false;
        measureTimer.cancel();
        cutoffTimer.cancel();
        socket.close();
        // We can also stop the isolates if we want, or reuse them for next test
      }).doOnCancel(() {
        print('[startUpload] canceled => cleanup');
        keepRunning = false;
        measureTimer.cancel();
        cutoffTimer.cancel();
        socket.close();
      });
    } catch (err, st) {
      yield Ndt7Measurement(
        error: err.toString(),
        stackTrace: st.toString(),
        test: 'upload',
      );
    }
  }

  // Listen for server messages in download
  void _listenForDownload(
      UniversalWebSocket socket, StreamController<Ndt7Measurement> ctrl) {
    socket.stream.listen((data) {
      if (ctrl.isClosed) return;
      if (data is ByteBuffer) {
        if (!ctrl.isClosed) {
          ctrl.add(Ndt7Measurement.internalBinaryDownload(data.lengthInBytes));
        }
      } else if (data is Uint8List) {
        ctrl.add(Ndt7Measurement.internalBinaryDownload(data.length));
      } else if (data is String) {
        try {
          final obj = json.decode(data);
          final meas = Ndt7Measurement.fromJson(obj)
            ..origin = 'server'
            ..test = 'download';
          ctrl.add(meas);
        } catch (err) {
          ctrl.add(Ndt7Measurement(
              error: 'JSON parse error: $err', test: 'download'));
        }
      }
    }, onError: (err, st) {
      if (!ctrl.isClosed) {
        ctrl.add(Ndt7Measurement(
            error: err.toString(),
            stackTrace: st?.toString(),
            test: 'download'));
        ctrl.close();
      }
    }, onDone: () {
      if (!ctrl.isClosed) {
        ctrl.close();
      }
    });
  }

  // Listen for server messages in upload
  void _listenForUpload(
      UniversalWebSocket socket, StreamController<Ndt7Measurement> ctrl) {
    socket.stream.listen((data) {
      if (ctrl.isClosed) return;
      if (data is String) {
        try {
          final obj = json.decode(data);
          final meas = Ndt7Measurement.fromJson(obj)
            ..origin = 'server'
            ..test = 'upload';
          ctrl.add(meas);
        } catch (err) {
          ctrl.add(
              Ndt7Measurement(error: 'JSON parse error: $err', test: 'upload'));
        }
      }
    }, onError: (err, st) {
      if (!ctrl.isClosed) {
        ctrl.add(Ndt7Measurement(
            error: err.toString(), stackTrace: st?.toString(), test: 'upload'));
        ctrl.close();
      }
    }, onDone: () {
      if (!ctrl.isClosed) {
        ctrl.close();
      }
    });
  }
}

// ---------------------------------------------------------------------------
// We add doOnDone() / doOnCancel() so we can handle final events easily
// ---------------------------------------------------------------------------
extension Ndt7StreamExtensions<T> on Stream<T> {
  Stream<T> doOnDone(void Function() action) {
    return transform(
      StreamTransformer<T, T>.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, st, sink) => sink.addError(error, st),
        handleDone: (sink) {
          action();
          sink.close();
        },
      ),
    );
  }

  Stream<T> doOnCancel(void Function() action) {
    final ctrl = StreamController<T>();
    late StreamSubscription<T> sub;
    ctrl.onListen = () {
      sub = listen(
        ctrl.add,
        onError: ctrl.addError,
        onDone: ctrl.close,
      );
    };
    ctrl.onCancel = () async {
      action();
      await sub.cancel();
    };
    return ctrl.stream;
  }
}
