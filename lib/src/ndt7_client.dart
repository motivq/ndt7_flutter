// lib/src/ndt7_client.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:isolates_helper/isolates_helper.dart';

import 'ndt7_measurement.dart';
import 'universal_websocket.dart';
import 'mlab_discovery.dart';

/// We'll produce client-based measurements every 250 ms for both download & upload.
const Duration clientMeasurementInterval = Duration(milliseconds: 250);

/// The maximum single binary message size (16 MiB).
const int maxMessageSize = 1 << 24;

/// We'll double the chunk size if currentSize < totalSoFar / scalingFraction.
const int scalingFraction = 16;

/// The initial message size for upload (8 KiB).
const int initialUploadMessageSize = 1 << 13;

/// The worker function for generating random data in an isolate/worker.
@isolatesHelperWorker
List<int> makeRandomPayloadWorker(List<int> params) {
  final size = params[0] as int;
  final rng = Random();
  return List<int>.generate(size, (_) => 65 + rng.nextInt(57));
}

/// The subprotocol required by ndt7
const ndt7WebSocketSubProtocol = 'net.measurementlab.ndt.v7';

/// Default concurrency for isolate usage
const defaultIsolateConcurrency = 1;

/// A config object letting you specify server, durations, concurrency, etc.
class Ndt7Config {
  // If you already have wss:// URLs with tokens, set these:
  final String? fullDownloadUrl;
  final String? fullUploadUrl;

  // Or you have a host, scheme, query
  final String? host;
  final String scheme;
  final String queryParams;

  // Test durations
  final Duration downloadTestDuration;
  final Duration uploadTestDuration;

  // Worker concurrency for random data
  final int concurrency;

  Ndt7Config({
    this.fullDownloadUrl,
    this.fullUploadUrl,
    this.host,
    this.scheme = 'wss',
    this.queryParams = '',
    this.downloadTestDuration = const Duration(seconds: 15),
    this.uploadTestDuration = const Duration(seconds: 10),
    this.concurrency = defaultIsolateConcurrency,
  });
}

/// A simple result combining the real-time measurement stream and a summary future.
class Ndt7TestResult {
  final Stream<Ndt7Measurement> measurements;
  final Future<Ndt7Summary> summary;
  Ndt7TestResult(this.measurements, this.summary);
}

/// The main NDT7 client using isolate-based random data generation to saturate upload.
/// It respects [Ndt7Config] for durations, concurrency, etc.
class Ndt7Client {
  final Ndt7Config config;
  final IsolatesHelper isolates;

  Ndt7Client({required this.config})
      : isolates = IsolatesHelper(concurrent: config.concurrency);

  /// Legacy: discover just a single host from older M-Lab endpoints
  static Future<Ndt7Client> withMlab({
    String userAgent = 'ndt7-dart/1.0',
    String scheme = 'wss',
    String queryParams = '',
    Duration downloadTestDuration = const Duration(seconds: 15),
    Duration uploadTestDuration = const Duration(seconds: 10),
    int concurrency = defaultIsolateConcurrency,
  }) async {
    final discoveredHost =
        await MLabDiscovery.discoverServer(userAgent: userAgent);
    final cfg = Ndt7Config(
      host: discoveredHost,
      scheme: scheme,
      queryParams: queryParams,
      downloadTestDuration: downloadTestDuration,
      uploadTestDuration: uploadTestDuration,
      concurrency: concurrency,
    );
    return Ndt7Client(config: cfg);
  }

  /// Modern: discover token-based wss:// URLs from M-Lab v2
  static Future<Ndt7Client> withMlabUrls({
    String userAgent = 'ndt7-dart/1.0',
    Duration downloadTestDuration = const Duration(seconds: 15),
    Duration uploadTestDuration = const Duration(seconds: 10),
    int concurrency = defaultIsolateConcurrency,
  }) async {
    final urls =
        await MLabDiscovery.discoverServerWithUrls(userAgent: userAgent);
    final cfg = Ndt7Config(
      fullDownloadUrl: urls.downloadUrl,
      fullUploadUrl: urls.uploadUrl,
      host: urls.fqdn,
      scheme: 'wss',
      queryParams: '',
      downloadTestDuration: downloadTestDuration,
      uploadTestDuration: uploadTestDuration,
      concurrency: concurrency,
    );
    return Ndt7Client(config: cfg);
  }

  // ---------------------------------------------------------------------------
  // Download test
  // ---------------------------------------------------------------------------
  Ndt7TestResult startDownloadTest() {
    final controller = StreamController<Ndt7Measurement>.broadcast();
    final futureSummary = _runDownload(controller);
    return Ndt7TestResult(controller.stream, futureSummary);
  }

  Future<Ndt7Summary> _runDownload(
      StreamController<Ndt7Measurement> ctrl) async {
    final aggregator = _MeasurementAggregator(test: 'download');
    final doneCompleter = Completer<Ndt7Summary>();

    unawaited(
      _startDownload(ctrl, aggregator).then((_) {
        doneCompleter.complete(aggregator.finalize());
      }).catchError((err, st) {
        doneCompleter.completeError(err, st);
      }),
    );

    return doneCompleter.future;
  }

  Future<void> _startDownload(
    StreamController<Ndt7Measurement> ctrl,
    _MeasurementAggregator aggregator,
  ) async {
    final downloadUrl = config.fullDownloadUrl ??
        '${config.scheme}://${config.host}/ndt/v7/download${config.queryParams}';

    try {
      await isolates.ensureStarted;

      final socket = await universalConnect(downloadUrl,
          protocols: [ndt7WebSocketSubProtocol]);
      aggregator.log('Download WebSocket connected: $downloadUrl');

      final cutoffTimer = Timer(config.downloadTestDuration, () {
        if (!ctrl.isClosed) ctrl.close();
      });

      final startTime = DateTime.now();
      int totalBytes = 0;

      _listenDownload(socket, ctrl, aggregator);

      // 250 ms client-based measurement
      final measureTimer = Timer.periodic(clientMeasurementInterval, (_) {
        if (ctrl.isClosed) return;
        final elapsedUs = DateTime.now().difference(startTime).inMicroseconds;
        aggregator.addClientMeasurement(
          test: 'download',
          elapsedUs: elapsedUs,
          totalBytes: totalBytes,
          ctrl: ctrl,
        );
      });

      // Wait for the stream to close
      await for (final m in ctrl.stream) {
        if (m.internalBinaryDownloadCount != null) {
          totalBytes += m.internalBinaryDownloadCount!;
        }
      }

      aggregator.log('Download finished. totalBytes=$totalBytes');
      measureTimer.cancel();
      cutoffTimer.cancel();
      socket.close();
    } catch (err, st) {
      aggregator.log('Download exception => $err');
      ctrl.add(Ndt7Measurement(
          error: err.toString(), stackTrace: st.toString(), test: 'download'));
      ctrl.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Upload test with concurrency
  // ---------------------------------------------------------------------------
  Ndt7TestResult startUploadTest() {
    final controller = StreamController<Ndt7Measurement>.broadcast();
    final futureSummary = _runUpload(controller);
    return Ndt7TestResult(controller.stream, futureSummary);
  }

  Future<Ndt7Summary> _runUpload(StreamController<Ndt7Measurement> ctrl) async {
    final aggregator = _MeasurementAggregator(test: 'upload');
    final doneCompleter = Completer<Ndt7Summary>();

    unawaited(
      _startUpload(ctrl, aggregator).then((_) {
        doneCompleter.complete(aggregator.finalize());
      }).catchError((err, st) {
        doneCompleter.completeError(err, st);
      }),
    );

    return doneCompleter.future;
  }

  /// A saturating upload loop, spawns up to `config.concurrency` random tasks in parallel.
  /// We identify which future completed using `Future.any(...)` on mapped futures.
  Future<void> _startUpload(
    StreamController<Ndt7Measurement> ctrl,
    _MeasurementAggregator aggregator,
  ) async {
    final uploadUrl = config.fullUploadUrl ??
        '${config.scheme}://${config.host}/ndt/v7/upload${config.queryParams}';

    try {
      await isolates.ensureStarted;

      final socket = await universalConnect(uploadUrl,
          protocols: [ndt7WebSocketSubProtocol]);
      aggregator.log('Upload WebSocket connected: $uploadUrl');

      final cutoffTimer = Timer(config.uploadTestDuration, () {
        if (!ctrl.isClosed) ctrl.close();
      });

      final startTime = DateTime.now();
      bool keepRunning = true;
      int totalSoFar = 0;
      int currentSize = initialUploadMessageSize;

      // Listen for server messages (upload)
      _listenUpload(socket, ctrl, aggregator);

      // Our concurrency queue
      final tasks = <Future<List<int>>>[];

      // Spawns tasks up to concurrency
      void maybeSpawnTasks() {
        while (keepRunning &&
            !ctrl.isClosed &&
            tasks.length < config.concurrency) {
          final future = isolates.compute(
            makeRandomPayloadWorker,
            [currentSize],
            workerFunction: 'makeRandomPayloadWorker',
          );
          tasks.add(future);
        }
      }

      // Kickstart
      maybeSpawnTasks();

      Future<void> concurrencyLoop() async {
        while (keepRunning) {
          // check if we are out of time or closed
          if (ctrl.isClosed ||
              DateTime.now().difference(startTime) >=
                  config.uploadTestDuration) {
            aggregator.log('Reached uploadTestDuration or closed => break');
            break;
          }
          if (tasks.isEmpty) {
            // spawn tasks if possible
            maybeSpawnTasks();
            if (tasks.isEmpty) {
              aggregator.log('No tasks can be spawned => break');
              break;
            }
          }

          // Wait for the first completed future
          final pairFuture = Future.any(
            tasks.map((f) => f.then((res) => [f, res])),
          );

          // If there's an error in the tasks, it might throw
          final pair = await pairFuture;
          // pair = [theFuture, theChunk]
          final completedFuture = pair[0] as Future<List<int>>;
          final chunkData = pair[1] as List<int>;

          // remove it from tasks
          tasks.remove(completedFuture);

          // check if time is still left
          if (ctrl.isClosed ||
              DateTime.now().difference(startTime) >=
                  config.uploadTestDuration) {
            aggregator.log('Time or closed => break');
            break;
          }

          // Send the chunk
          try {
            socket.send(Uint8List.fromList(chunkData));
          } catch (sendErr) {
            aggregator.log('socket.send error => $sendErr');
            if (!ctrl.isClosed) {
              ctrl.add(
                  Ndt7Measurement(error: sendErr.toString(), test: 'upload'));
              ctrl.close();
            }
            break;
          }

          totalSoFar += currentSize;

          // scale up chunk size if needed
          if (currentSize < maxMessageSize) {
            final threshold = totalSoFar ~/ scalingFraction;
            if (currentSize < threshold) {
              currentSize *= 2;
              if (currentSize > maxMessageSize) {
                currentSize = maxMessageSize;
              }
            }
          }

          // Refill concurrency
          maybeSpawnTasks();

          // yield
          await Future(() {});
        }

        aggregator.log('Exiting concurrency loop');
        // We can close if not closed
        if (!ctrl.isClosed) {
          ctrl.close();
        }
      }

      // start the concurrency loop
      concurrencyLoop();

      // Meanwhile, produce client-based measurement every 250 ms
      final measureTimer = Timer.periodic(clientMeasurementInterval, (_) {
        if (!ctrl.isClosed) {
          final elapsedUs = DateTime.now().difference(startTime).inMicroseconds;
          aggregator.addClientMeasurement(
            test: 'upload',
            elapsedUs: elapsedUs,
            totalBytes: totalSoFar,
            ctrl: ctrl,
          );
        }
      });

      // wait for ctrl to close
      await for (final _ in ctrl.stream) {
        // aggregator sees each measurement
      }

      aggregator.log('Upload finished. totalBytes=$totalSoFar');
      keepRunning = false;
      measureTimer.cancel();
      cutoffTimer.cancel();
      socket.close();
    } catch (err, st) {
      aggregator.log('Upload exception => $err');
      ctrl.add(Ndt7Measurement(
          error: err.toString(), stackTrace: st.toString(), test: 'upload'));
      ctrl.close();
    }
  }

  // Listen for server messages (download)
  void _listenDownload(
    UniversalWebSocket socket,
    StreamController<Ndt7Measurement> ctrl,
    _MeasurementAggregator aggregator,
  ) {
    socket.stream.listen((data) {
      if (ctrl.isClosed) return;
      if (data is ByteBuffer) {
        ctrl.add(Ndt7Measurement.internalBinaryDownload(data.lengthInBytes));
      } else if (data is Uint8List) {
        ctrl.add(Ndt7Measurement.internalBinaryDownload(data.length));
      } else if (data is String) {
        try {
          final obj = json.decode(data);
          final meas = Ndt7Measurement.fromJson(obj)
            ..origin = 'server'
            ..test = 'download';
          ctrl.add(meas);
          aggregator.addServerMeasurement(meas);
        } catch (err) {
          ctrl.add(Ndt7Measurement(
              error: 'JSON parse error: $err', test: 'download'));
        }
      }
    }, onError: (error, st) {
      ctrl.add(Ndt7Measurement(
          error: error.toString(),
          stackTrace: st?.toString(),
          test: 'download'));
      ctrl.close();
    }, onDone: () {
      ctrl.close();
    });
  }

  // Listen for server messages (upload)
  void _listenUpload(
    UniversalWebSocket socket,
    StreamController<Ndt7Measurement> ctrl,
    _MeasurementAggregator aggregator,
  ) {
    socket.stream.listen((data) {
      if (ctrl.isClosed) return;
      if (data is String) {
        try {
          final obj = json.decode(data);
          final meas = Ndt7Measurement.fromJson(obj)
            ..origin = 'server'
            ..test = 'upload';
          ctrl.add(meas);
          aggregator.addServerMeasurement(meas);
        } catch (err) {
          ctrl.add(
              Ndt7Measurement(error: 'JSON parse error: $err', test: 'upload'));
        }
      }
    }, onError: (error, st) {
      ctrl.add(Ndt7Measurement(
          error: error.toString(), stackTrace: st?.toString(), test: 'upload'));
      ctrl.close();
    }, onDone: () {
      ctrl.close();
    });
  }
}

/// A private aggregator that collects measurements to produce a final summary
class _MeasurementAggregator {
  final String test;
  final List<Ndt7Measurement> all = [];
  final List<String> logs = [];

  _MeasurementAggregator({required this.test});

  /// Called when we produce a client-based measurement
  void addClientMeasurement({
    required String test,
    required int elapsedUs,
    required int totalBytes,
    required StreamController<Ndt7Measurement> ctrl,
  }) {
    final secs = elapsedUs / 1e6;
    final bits = totalBytes * 8.0;
    final speed = (secs > 0) ? (bits / secs / 1e6) : 0.0;

    if (!ctrl.isClosed) {
      ctrl.add(
        Ndt7Measurement(
          test: test,
          origin: 'client',
          appInfo: AppInfo(
            elapsedTimeMicros: elapsedUs,
            numBytes: totalBytes,
            meanClientMbps: speed,
          ),
        ),
      );
    }

    // Store for final summary
    all.add(
      Ndt7Measurement(
        test: test,
        origin: 'client',
        appInfo: AppInfo(
          elapsedTimeMicros: elapsedUs,
          numBytes: totalBytes,
          meanClientMbps: speed,
        ),
      ),
    );
  }

  /// Called when we receive a server-based measurement
  void addServerMeasurement(Ndt7Measurement m) {
    all.add(m);
  }

  void log(String msg) {
    logs.add(msg);
  }

  /// Produces a final Ndt7Summary at the end
  Future<Ndt7Summary> finalize() async {
    double avgMbps = 0.0;
    final clientMs = all
        .where(
            (m) => m.origin == 'client' && m.test == test && m.appInfo != null)
        .toList();
    if (clientMs.isNotEmpty) {
      final last = clientMs.last;
      final us = last.appInfo!.elapsedTimeMicros.toDouble();
      final bytes = last.appInfo!.numBytes.toDouble();
      if (us > 0) {
        final secs = us / 1e6;
        final bits = bytes * 8.0;
        avgMbps = bits / secs / 1e6;
      }
    }

    // gather server RTT
    final rtts = <double>[];
    for (var m in all) {
      if (m.origin == 'server' && m.test == test && m.tcpInfo?.rtt != null) {
        final r = m.tcpInfo!.rtt!;
        if (r > 0) {
          rtts.add(r / 1000.0);
        }
      }
    }
    double avgRtt = 0.0;
    if (rtts.isNotEmpty) {
      avgRtt = rtts.reduce((a, b) => a + b) / rtts.length;
    }
    final jitter = Ndt7Scoring.computeStdDev(rtts);

    final dScore = Ndt7Scoring.scoreDownload(avgMbps);
    final uScore = Ndt7Scoring.scoreUpload(avgMbps);
    final lScore = Ndt7Scoring.scoreLatency(avgRtt);
    final jScore = Ndt7Scoring.scoreJitter(jitter);

    return Ndt7Summary(
      test: test,
      avgMbps: avgMbps,
      avgRttMs: avgRtt,
      jitterMs: jitter,
      downloadScore: dScore,
      uploadScore: uScore,
      latencyScore: lScore,
      jitterScore: jScore,
    );
  }
}

// ---------------------------------------------------------------------------
// doOnDone() / doOnCancel() to handle final events on a Stream
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
