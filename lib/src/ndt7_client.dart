// lib/src/ndt7_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io' show WebSocketException;

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
  final size = params[0];
  final rng = Random();
  return List<int>.generate(size, (_) => 65 + rng.nextInt(57));
}

/// The subprotocol required by ndt7
const ndt7WebSocketSubProtocol = 'net.measurementlab.ndt.v7';

/// Default concurrency for isolate usage
const defaultIsolateConcurrency = 1;

/// A config object letting you specify server, durations, concurrency, etc.
class Ndt7Config {
  final String? fullDownloadUrl;
  final String? fullUploadUrl;
  final String? host;
  final String scheme;
  final String queryParams;
  final Duration downloadTestDuration;
  final Duration uploadTestDuration;
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

  /// Returns a copy with updated URLs / host from fresh locate.
  Ndt7Config copyWith({
    String? fullDownloadUrl,
    String? fullUploadUrl,
    String? host,
  }) {
    return Ndt7Config(
      fullDownloadUrl: fullDownloadUrl ?? this.fullDownloadUrl,
      fullUploadUrl: fullUploadUrl ?? this.fullUploadUrl,
      host: host ?? this.host,
      scheme: scheme,
      queryParams: queryParams,
      downloadTestDuration: downloadTestDuration,
      uploadTestDuration: uploadTestDuration,
      concurrency: concurrency,
    );
  }
}

/// A simple result combining the real-time measurement stream and a summary future.
class Ndt7TestResult {
  final Stream<Ndt7Measurement> measurements;
  final Future<Ndt7Summary> summary;
  Ndt7TestResult(this.measurements, this.summary);
}

/// The main NDT7 client that uses:
/// - One WebSocket for download
/// - One WebSocket for upload
/// - Concurrency for the upload tasks only
class Ndt7Client {
  late Ndt7Config config;
  final IsolatesHelper isolates;

  bool _autoRetryOn401 = false; // so we only refresh once if 401

  Ndt7Client({required this.config})
      : isolates = IsolatesHelper(concurrent: config.concurrency);

  // ---------------------------------------------------------------------------
  // Constructors that discover M-Lab
  // ---------------------------------------------------------------------------
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
  // Download test - single WebSocket
  // ---------------------------------------------------------------------------
  Ndt7TestResult startDownloadTest() {
    final ctrl = StreamController<Ndt7Measurement>.broadcast();
    final futureSummary = _runDownload(ctrl);
    return Ndt7TestResult(ctrl.stream, futureSummary);
  }

  Future<Ndt7Summary> _runDownload(
      StreamController<Ndt7Measurement> ctrl) async {
    final aggregator = _MeasurementAggregator(test: 'download');
    final completer = Completer<Ndt7Summary>();

    unawaited(
      _startDownload(ctrl, aggregator).then((_) {
        completer.complete(aggregator.finalize());
      }).catchError((err, st) {
        completer.completeError(err, st);
      }),
    );

    return completer.future;
  }

  /// The standard single-connection approach for download. There's no concurrency
  /// because the server is sending data. The concurrency param is effectively unused here.
  Future<void> _startDownload(
    StreamController<Ndt7Measurement> ctrl,
    _MeasurementAggregator aggregator,
  ) async {
    final downloadUrl = config.fullDownloadUrl ??
        '${config.scheme}://${config.host}/ndt/v7/download${config.queryParams}';
    try {
      await isolates.ensureStarted;

      final cutoffTimer = Timer(config.downloadTestDuration, () {
        if (!ctrl.isClosed) ctrl.close();
      });

      final startTime = DateTime.now();
      int totalBytes = 0;

      aggregator.log('Connecting to $downloadUrl for download...');
      final socket = await universalConnect(downloadUrl,
          protocols: [ndt7WebSocketSubProtocol]);
      aggregator.log('Download WebSocket connected: $downloadUrl');

      // Listen for data
      late StreamSubscription sub;
      sub = socket.stream.listen(
        (data) {
          if (ctrl.isClosed) return;
          if (data is ByteBuffer) {
            totalBytes += data.lengthInBytes;
            ctrl.add(
                Ndt7Measurement.internalBinaryDownload(data.lengthInBytes));
          } else if (data is Uint8List) {
            totalBytes += data.length;
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
        },
        onError: (error, st) {
          aggregator.log('[download single-conn] onError => $error');
          if (_isClosedSocketError(error)) {
            aggregator.log('[download] ignoring closed-socket => $error');
            return;
          }
          if (!ctrl.isClosed) {
            if (_is401(error) && !_autoRetryOn401) {
              aggregator.log('[download] 401 => attempt refresh');
              _autoRetryOn401 = true;
              // Don't close the controller yet - let the retry handle that
              socket.close();
              _refreshUrlsAndRetry(aggregator, ctrl, wasDownload: true);
            } else {
              ctrl.add(Ndt7Measurement(
                  error: error.toString(),
                  stackTrace: st?.toString(),
                  test: 'download'));
              ctrl.close();
            }
          }
        },
        onDone: () {
          aggregator.log('[download single-conn] onDone');
          sub.cancel();
          socket.close();
        },
      );

      // 250ms measurement
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

      // Wait for stream to close
      await ctrl.done;
      aggregator.log('[download single-conn] totalBytes=$totalBytes');
      measureTimer.cancel();
      cutoffTimer.cancel();
      sub.cancel();
      socket.close();
    } catch (err, st) {
      aggregator.log('[download single-conn] error => $err');
      if (_is401(err) && !_autoRetryOn401) {
        aggregator.log('[download single-conn] 401 => attempt refresh');
        _autoRetryOn401 = true;
        if (!ctrl.isClosed) ctrl.close();
        await _refreshUrlsAndRetry(aggregator, ctrl, wasDownload: true);
      } else {
        if (!ctrl.isClosed) {
          ctrl.add(Ndt7Measurement(
              error: err.toString(),
              stackTrace: st.toString(),
              test: 'download'));
          ctrl.close();
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Upload test - single WebSocket, concurrency for random data tasks
  // ---------------------------------------------------------------------------
  Ndt7TestResult startUploadTest() {
    final ctrl = StreamController<Ndt7Measurement>.broadcast();
    final futureSummary = _runUpload(ctrl);
    return Ndt7TestResult(ctrl.stream, futureSummary);
  }

  Future<Ndt7Summary> _runUpload(StreamController<Ndt7Measurement> ctrl) async {
    final aggregator = _MeasurementAggregator(test: 'upload');
    final completer = Completer<Ndt7Summary>();

    unawaited(
      _startUpload(ctrl, aggregator).then((_) {
        completer.complete(aggregator.finalize());
      }).catchError((err, st) {
        completer.completeError(err, st);
      }),
    );

    return completer.future;
  }

  Future<void> _startUpload(
    StreamController<Ndt7Measurement> ctrl,
    _MeasurementAggregator aggregator,
  ) async {
    final uploadUrl = config.fullUploadUrl ??
        '${config.scheme}://${config.host}/ndt/v7/upload${config.queryParams}';

    try {
      await isolates.ensureStarted;

      final cutoffTimer = Timer(config.uploadTestDuration, () {
        if (!ctrl.isClosed) ctrl.close();
      });

      final socket = await universalConnect(uploadUrl,
          protocols: [ndt7WebSocketSubProtocol]);
      aggregator.log('Upload WebSocket connected: $uploadUrl');

      final startTime = DateTime.now();
      bool keepRunning = true;
      int totalSoFar = 0;
      int currentSize = initialUploadMessageSize;

      // Listen for server messages
      late StreamSubscription sub;
      sub = socket.stream.listen(
        (data) {
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
              ctrl.add(Ndt7Measurement(
                  error: 'JSON parse error: $err', test: 'upload'));
            }
          }
        },
        onError: (error, st) {
          aggregator.log('[upload single-conn] onError => $error');
          if (_isClosedSocketError(error)) {
            aggregator.log('[upload] ignoring closed-socket => $error');
            return;
          }
          if (!ctrl.isClosed) {
            if (_is401(error) && !_autoRetryOn401) {
              aggregator.log('[upload] 401 => attempt refresh');
              _autoRetryOn401 = true;
              // ctrl.close();
              socket.close();
              _refreshUrlsAndRetry(aggregator, ctrl, wasDownload: false);
            } else {
              ctrl.add(Ndt7Measurement(
                  error: error.toString(),
                  stackTrace: st?.toString(),
                  test: 'upload'));
              ctrl.close();
            }
          }
        },
        onDone: () {
          aggregator.log('[upload single-conn] onDone');
          sub.cancel();
          socket.close();
        },
      );

      // concurrency for random tasks
      final tasks = <Future<List<int>>>[];

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

      maybeSpawnTasks();

      Future<void> concurrencyLoop() async {
        while (keepRunning) {
          if (ctrl.isClosed ||
              DateTime.now().difference(startTime) >=
                  config.uploadTestDuration) {
            aggregator.log('[Upload single-conn] done => break');
            break;
          }
          if (tasks.isEmpty) {
            maybeSpawnTasks();
            if (tasks.isEmpty) {
              aggregator.log('[Upload single-conn] no tasks => break');
              break;
            }
          }

          // Wait for first completed
          final pair = await Future.any(
            tasks.map((f) => f.then((res) => [f, res])),
          );
          final completedFuture = pair[0] as Future<List<int>>;
          final chunkData = pair[1] as List<int>;

          tasks.remove(completedFuture);

          if (ctrl.isClosed ||
              DateTime.now().difference(startTime) >=
                  config.uploadTestDuration) {
            aggregator.log('[Upload single-conn] time or closed => break');
            break;
          }

          // send chunk
          try {
            socket.send(Uint8List.fromList(chunkData));
          } catch (sendErr) {
            aggregator.log('[Upload single-conn] send error => $sendErr');
            if (!ctrl.isClosed) {
              ctrl.add(
                  Ndt7Measurement(error: sendErr.toString(), test: 'upload'));
              ctrl.close();
            }
            break;
          }

          totalSoFar += currentSize;

          // scale
          if (currentSize < maxMessageSize) {
            final threshold = totalSoFar ~/ scalingFraction;
            if (currentSize < threshold) {
              currentSize *= 2;
              if (currentSize > maxMessageSize) {
                currentSize = maxMessageSize;
              }
            }
          }

          maybeSpawnTasks();
          await Future(() {});
        }

        aggregator.log('[Upload single-conn] concurrency loop done');
        if (!ctrl.isClosed) ctrl.close();
      }

      concurrencyLoop();

      // 250ms measurement
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

      // wait for stream to close
      await ctrl.done;
      aggregator.log('[Upload single-conn] totalSoFar=$totalSoFar');
      keepRunning = false;
      measureTimer.cancel();
      socket.close();
      sub.cancel();
      cutoffTimer.cancel();
    } catch (err, st) {
      aggregator.log('[upload single-conn] error => $err');
      if (_is401(err) && !_autoRetryOn401) {
        aggregator.log('[upload single-conn] 401 => attempt refresh');
        _autoRetryOn401 = true;
        if (!ctrl.isClosed) ctrl.close();
        await _refreshUrlsAndRetry(aggregator, ctrl, wasDownload: false);
      } else {
        if (!ctrl.isClosed) {
          ctrl.add(Ndt7Measurement(
              error: err.toString(),
              stackTrace: st.toString(),
              test: 'upload'));
          ctrl.close();
        }
      }
    }
  }

  /// Called if we see 401 => we do MLab re-locate and re-run
  Future<void> _refreshUrlsAndRetry(
    _MeasurementAggregator aggregator,
    StreamController<Ndt7Measurement> ctrl, {
    required bool wasDownload,
    String userAgent = 'ndt7-dart/1.0',
  }) async {
    aggregator.log('[refreshUrlsAndRetry] begin');
    try {
      final newUrls = await MLabDiscovery.discoverServerWithUrls(
        userAgent: '$userAgent refresh',
      );
      config = config.copyWith(
        fullDownloadUrl: newUrls.downloadUrl,
        fullUploadUrl: newUrls.uploadUrl,
        host: newUrls.fqdn,
      );
      aggregator.log('[refreshUrlsAndRetry] got new FQDN=${newUrls.fqdn}');

      if (!ctrl.isClosed) {
        if (wasDownload) {
          await _startDownload(ctrl, aggregator);
        } else {
          await _startUpload(ctrl, aggregator);
        }
      }
    } catch (e, st) {
      aggregator.log('[refreshUrlsAndRetry] failed => $e');
      if (!ctrl.isClosed) {
        ctrl.add(Ndt7Measurement(
            error: e.toString(),
            stackTrace: st.toString(),
            test: wasDownload ? 'download' : 'upload'));
        ctrl.close();
      }
    }
  }

  // If error text has '401'
  bool _is401(dynamic err) {
    if (err is WebSocketException) {
      return err.httpStatusCode == 401;
    }
    // Also check string representation for platforms where WebSocketException might be different
    final errStr = err.toString().toLowerCase();
    return errStr.contains('401') || errStr.contains('unauthorized');
  }

  // If error text is "Reading from a closed socket"
  bool _isClosedSocketError(dynamic err) {
    final msg = err?.toString() ?? '';
    return msg.contains('Reading from a closed socket');
  }
}

/// Aggregates measurements for final summary, plus we track total downloaded bytes if concurrency>1.
/// But now we only do single-socket for download, so totalDownloadBytes just increments in that one subscription.
class _MeasurementAggregator {
  final String test;
  final List<Ndt7Measurement> all = [];
  final List<String> logs = [];

  // For single-socket download, we just increment in the subscription logic
  int totalClientDownloadBytes = 0;

  _MeasurementAggregator({required this.test});

  /// For client-based measurement
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

  void addServerMeasurement(Ndt7Measurement m) {
    all.add(m);
  }

  void addDownloadBytes(int count) {
    totalClientDownloadBytes += count;
  }

  void log(String msg) {
    logs.add(msg);
  }

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
