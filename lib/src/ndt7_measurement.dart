// lib/src/ndt7_measurement.dart

import 'dart:math';

/// Represents the JSON measurement structure from the ndt7 spec,
/// plus optional fields for client side updates or errors.
class Ndt7Measurement {
  /// If an error happened, store it here. Non-null means a failure event.
  final String? error;

  /// A Dart stack trace if available.
  final String? stackTrace;

  /// 'client' or 'server', specifying who created this measurement.
  String? origin;

  /// 'download' or 'upload' test phase.
  String? test;

  /// The application-level info. (Spec calls it AppInfo.)
  final AppInfo? appInfo;

  /// The connection-level info. (Spec calls it ConnectionInfo.)
  final ConnectionInfo? connectionInfo;

  /// Additional TCPInfo if available. (Spec calls it TCPInfo.)
  final TCPInfo? tcpInfo;

  /// Internal use to track the last binary chunk size in download.
  final int? internalBinaryDownloadCount;

  Ndt7Measurement({
    this.error,
    this.stackTrace,
    this.origin,
    this.test,
    this.appInfo,
    this.connectionInfo,
    this.tcpInfo,
    this.internalBinaryDownloadCount,
  });

  /// A synthetic measurement for counting binary message sizes (download).
  Ndt7Measurement.internalBinaryDownload(int byteCount)
      : error = null,
        stackTrace = null,
        origin = null,
        test = null,
        appInfo = null,
        connectionInfo = null,
        tcpInfo = null,
        internalBinaryDownloadCount = byteCount;

  /// Whether this measurement is effectively empty
  bool isEmpty() {
    return (error == null) &&
        (stackTrace == null) &&
        (origin == null) &&
        (test == null) &&
        (appInfo == null) &&
        (connectionInfo == null) &&
        (tcpInfo == null);
  }

  /// Parse a measurement from JSON (server-based).
  factory Ndt7Measurement.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return Ndt7Measurement(
        appInfo: AppInfo.fromJson(json['AppInfo']),
        connectionInfo: ConnectionInfo.fromJson(json['ConnectionInfo']),
        tcpInfo: TCPInfo.fromJson(json['TCPInfo']),
        origin: json['Origin'] as String?,
        test: json['Test'] as String?,
      );
    }
    return Ndt7Measurement(error: 'Invalid JSON type');
  }

  /// Returns an empty measurement (e.g. filtering synthetic event).
  factory Ndt7Measurement.empty() => Ndt7Measurement();

  @override
  String toString() {
    if (error != null) {
      return 'Ndt7Measurement(error=$error)';
    }
    return 'Ndt7Measurement(origin=$origin, test=$test, appInfo=$appInfo, tcpInfo=$tcpInfo)';
  }
}

/// AppInfo structure from the ndt7 spec, plus optional fields.
class AppInfo {
  /// Elapsed microseconds since the start of the test (client side).
  final int elapsedTimeMicros;

  /// Bytes transferred (client side).
  final int numBytes;

  /// Optionally store a computed mean speed in Mbps.
  final double? meanClientMbps;

  AppInfo({
    required this.elapsedTimeMicros,
    required this.numBytes,
    this.meanClientMbps,
  });

  factory AppInfo.fromJson(dynamic j) {
    if (j is Map<String, dynamic>) {
      return AppInfo(
        elapsedTimeMicros: (j['ElapsedTime'] ?? 0) as int,
        numBytes: (j['NumBytes'] ?? 0) as int,
        meanClientMbps: (j['MeanClientMbps'] as num?)?.toDouble(),
      );
    }
    return AppInfo(elapsedTimeMicros: 0, numBytes: 0);
  }

  @override
  String toString() => 'AppInfo($elapsedTimeMicros us, $numBytes bytes, '
      '${meanClientMbps?.toStringAsFixed(2) ?? 'N/A'} Mbps)';
}

/// ConnectionInfo from the ndt7 spec
class ConnectionInfo {
  final String? client;
  final String? server;
  final String? uuid;

  ConnectionInfo({this.client, this.server, this.uuid});

  factory ConnectionInfo.fromJson(dynamic j) {
    if (j is Map<String, dynamic>) {
      return ConnectionInfo(
        client: j['Client'] as String?,
        server: j['Server'] as String?,
        uuid: j['UUID'] as String?,
      );
    }
    return ConnectionInfo();
  }

  @override
  String toString() =>
      'ConnectionInfo(client=$client, server=$server, uuid=$uuid)';
}

/// TCPInfo from the ndt7 spec, summarizing kernel-level metrics.
class TCPInfo {
  final int? busyTime;
  final int? bytesAcked;
  final int? bytesReceived;
  final int? bytesSent;
  final int? bytesRetrans;
  final int? elapsedTime;
  final int? minRTT;
  final int? rtt;
  final int? rttVar;
  final int? rwndLimited;
  final int? sndBufLimited;

  TCPInfo({
    this.busyTime,
    this.bytesAcked,
    this.bytesReceived,
    this.bytesSent,
    this.bytesRetrans,
    this.elapsedTime,
    this.minRTT,
    this.rtt,
    this.rttVar,
    this.rwndLimited,
    this.sndBufLimited,
  });

  factory TCPInfo.fromJson(dynamic j) {
    if (j is Map<String, dynamic>) {
      return TCPInfo(
        busyTime: j['BusyTime'] as int?,
        bytesAcked: j['BytesAcked'] as int?,
        bytesReceived: j['BytesReceived'] as int?,
        bytesSent: j['BytesSent'] as int?,
        bytesRetrans: j['BytesRetrans'] as int?,
        elapsedTime: j['ElapsedTime'] as int?,
        minRTT: j['MinRTT'] as int?,
        rtt: j['RTT'] as int?,
        rttVar: j['RTTVar'] as int?,
        rwndLimited: j['RWndLimited'] as int?,
        sndBufLimited: j['SndBufLimited'] as int?,
      );
    }
    return TCPInfo();
  }

  @override
  String toString() =>
      'TCPInfo(rtt=$rtt, bytesSent=$bytesSent, bytesAcked=$bytesAcked)';
}

/// A final summary object describing the entire ndt7 test run.
class Ndt7Summary {
  /// 'download' or 'upload'
  final String test;

  /// The final average speed in Mbit/s (client-based).
  final double avgMbps;

  /// The final average RTT in ms (based on server TCPInfo, if available).
  final double avgRttMs;

  /// A naive jitter measure in ms (std dev of the rtt samples).
  final double jitterMs;

  /// Some user-friendly scores from 0-100
  final double downloadScore;
  final double uploadScore;
  final double latencyScore;
  final double jitterScore;

  Ndt7Summary({
    required this.test,
    required this.avgMbps,
    required this.avgRttMs,
    required this.jitterMs,
    required this.downloadScore,
    required this.uploadScore,
    required this.latencyScore,
    required this.jitterScore,
  });

  @override
  String toString() {
    return 'Ndt7Summary('
        'test=$test, '
        'avgMbps=${avgMbps.toStringAsFixed(2)}, '
        'avgRttMs=${avgRttMs.toStringAsFixed(2)}, '
        'jitterMs=${jitterMs.toStringAsFixed(2)}, '
        'scores={down=$downloadScore, up=$uploadScore, lat=$latencyScore, jit=$jitterScore})';
  }
}

/// A helper to compute naive "scores" from final speed or RTT or jitter.
class Ndt7Scoring {
  static double scoreDownload(double mbps) {
    // e.g. if 100+ => 100, else linear 0..100
    return (mbps >= 100.0) ? 100.0 : mbps;
  }

  static double scoreUpload(double mbps) {
    // e.g. if 50+ => 100, else linear
    return (mbps >= 50.0) ? 100.0 : (mbps / 50.0 * 100.0).clamp(0, 100);
  }

  static double scoreLatency(double rttMs) {
    // e.g. if <20 => 100, >300 => 0, else linear
    if (rttMs <= 20.0) return 100;
    if (rttMs >= 300.0) return 0;
    final range = 300.0 - 20.0;
    final dist = (rttMs - 20.0) / range;
    return (1.0 - dist) * 100.0;
  }

  static double scoreJitter(double jitMs) {
    // e.g. if <5 => 100, >100 => 0, else linear
    if (jitMs <= 5.0) return 100;
    if (jitMs >= 100.0) return 0;
    final range = 100.0 - 5.0;
    final dist = (jitMs - 5.0) / range;
    return (1.0 - dist) * 100.0;
  }

  static double computeStdDev(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    double sumSq = 0;
    for (var s in samples) {
      final d = s - mean;
      sumSq += d * d;
    }
    final variance = sumSq / samples.length;
    return sqrt(variance);
  }
}
