// lib/src/ndt7_measurement.dart

/// Represents the JSON measurement structure from the ndt7 spec,
/// plus optional fields for client side updates or errors.
class Ndt7Measurement {
  /// If an error happened, store it here. Non-null means a failure event.
  final String? error;

  /// A Dart stack trace if available.
  final String? stackTrace;

  /// A short string describing whether this measurement is from the
  /// 'client' or the 'server' perspective. (Spec uses "Origin".)
  String? origin;

  /// Either 'download' or 'upload'.
  String? test;

  /// The application-level info. (Spec calls it AppInfo.)
  final AppInfo? appInfo;

  /// The connection-level info. (Spec calls it ConnectionInfo.)
  final ConnectionInfo? connectionInfo;

  /// Additional TCPInfo if available. (Spec calls it TCPInfo.)
  final TCPInfo? tcpInfo;

  /// For internal use: how many bytes in the last binary message.
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

  Ndt7Measurement.internalBinaryDownload(int byteCount)
      : error = null,
        stackTrace = null,
        origin = null,
        test = null,
        appInfo = null,
        connectionInfo = null,
        tcpInfo = null,
        internalBinaryDownloadCount = byteCount;

  bool isEmpty() {
    return (error == null) &&
        (stackTrace == null) &&
        (origin == null) &&
        (test == null) &&
        (appInfo == null) &&
        (connectionInfo == null) &&
        (tcpInfo == null);
  }

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

  factory Ndt7Measurement.empty() => Ndt7Measurement();

  @override
  String toString() {
    if (error != null) {
      return 'Ndt7Measurement(error=$error)';
    }
    return 'Ndt7Measurement(origin=$origin, test=$test, appInfo=$appInfo, tcpInfo=$tcpInfo)';
  }
}

/// AppInfo structure from the ndt7 spec, plus any optional fields.
class AppInfo {
  final int elapsedTimeMicros;
  final int numBytes;
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
  String toString() =>
      'AppInfo($elapsedTimeMicros us, $numBytes bytes, ${meanClientMbps?.toStringAsFixed(2) ?? 'N/A'} Mbps)';
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

/// TCPInfo from the ndt7 spec
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
