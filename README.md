# ndt7 Dart/Flutter Client

This is a **pure Dart** ndt7 client library for performing network speed tests (upload/download) based on the [ndt7 specification](https://github.com/m-lab/ndt-server/blob/master/spec/ndt7-protocol.md). It supports:

- **Service Discovery** for [M-Lab](https://www.measurementlab.net/) servers (finding the nearest server automatically).  
- **Pure Dart** WebSockets & HTTP, working on **Android**, **iOS**, **Web**, **Desktop**, etc. (thanks to conditional imports).  
- **Easy integration** with Flutter or other Dart environments (no native code needed, no Gradle/CocoaPods config).  

## Table of Contents

1. [Features](#features)  
2. [Installation](#installation)  
3. [Importing the Package](#importing-the-package)  
4. [Getting Started](#getting-started)  
5. [Usage](#usage)  
   - [1. Service Discovery (M-Lab)](#1-service-discovery-m-lab)  
   - [2. Download Test](#2-download-test)  
   - [3. Upload Test](#3-upload-test)  
6. [Receiving Measurements](#receiving-measurements)  
   - [Measurement Data Structures](#measurement-data-structures)  
   - [Sample Output](#sample-output)  
7. [API Reference](#api-reference)  
8. [Example Code](#example-code)  
9. [License](#license)  

---

## Features

- **M-Lab Service Discovery**: Automatically discover the nearest M-Lab ndt7 server by querying `https://locate.measurementlab.net/ndt7`.
- **Download / Upload Tests**: Start each test via `startDownload()` or `startUpload()`, each returning a Dart `Stream` of measurement updates.
- **Cross-Platform**: Works on mobile, web, desktop, or server, thanks to conditional imports for WebSockets and HTTP.
- **Pure Dart**: No native dependencies required. You can add it to any Flutter or Dart project.

---

## Installation

1. Add this package to your `pubspec.yaml`:

   ```yaml
   dependencies:
     ndt7: ^1.0.0
   ```

2. Run `flutter pub get` or `dart pub get` (depending on your environment).

---

## Importing the Package

In your Dart or Flutter code:

```dart
import 'package:ndt7/ndt7.dart';
```

This import provides:

- `Ndt7Client`  
- `Ndt7Measurement` (and related data structures)  
- `MLabDiscovery` (if you want raw control over discovery)  

---

## Getting Started

### Quick Steps

1. **Create** an `Ndt7Client` connected to a known host, **or** use M-Lab’s discovery.  
2. **Call** `startDownload()` or `startUpload()` to get a `Stream<Ndt7Measurement>`.  
3. **Listen** to the stream for measurement updates or errors.  

---

## Usage

### 1. Service Discovery (M-Lab)

**Recommended**: Let the library pick the nearest M-Lab ndt7 server:

```dart
final client = await Ndt7Client.withMlab(
  userAgent: 'my-ndt7-app/1.0',  // optional
);
```

Under the hood:
- The client calls `https://locate.measurementlab.net/ndt7`.
- On success, you get back a server FQDN (e.g. `ndt-iupui-mlab2-foo01.measurement-lab.org`).
- `withMlab()` returns an `Ndt7Client` pointed at that server.

You can optionally pass:
- `scheme`: `'wss'` (secure) or `'ws'` (insecure). Defaults to `wss`.
- `queryParams`: a string like `'?token=XYZ'`.
- `downloadTestDuration` or `uploadTestDuration`: overrides for test timeouts (defaults ~15s download, ~10s upload).

If discovery fails or M-Lab is out of capacity, `withMlab()` will throw an exception.

### 2. Download Test

```dart
final downloadStream = client.startDownload();
downloadStream.listen((measurement) {
  if (measurement.error != null) {
    print('Download error: ${measurement.error}');
  } else {
    print('Download measurement => $measurement');
  }
}, onDone: () {
  print('Download test complete');
});
```

- The method returns a `Stream<Ndt7Measurement>`.
- The stream ends either after the default 15s or if the server closes earlier, or on an error.

### 3. Upload Test

```dart
final uploadStream = client.startUpload();
uploadStream.listen((measurement) {
  if (measurement.error != null) {
    print('Upload error: ${measurement.error}');
  } else {
    print('Upload measurement => $measurement');
  }
}, onDone: () {
  print('Upload test complete');
});
```

- Similarly returns a `Stream<Ndt7Measurement>`.
- The stream ends after the default 10s or if the server closes earlier, or on an error.

---

## Receiving Measurements

### Measurement Data Structures

Each event from `startDownload()` or `startUpload()` is an `Ndt7Measurement`, which may include:

- **`origin`**: `'client'` or `'server'` – who generated the measurement.  
- **`test`**: `'download'` or `'upload'`.  
- **`error`**: A string if something went wrong.  
- **`stackTrace`**: For debugging, if an error occurred.  
- **`appInfo`**: For application-level counters:  
  - `elapsedTimeMicros`: microseconds since test started.  
  - `numBytes`: how many bytes we’ve sent/received so far.  
- **`connectionInfo`**: If provided by the server (with fields like `Client`, `Server`, `UUID`).  
- **`tcpInfo`**: If provided by the server, containing kernel-level stats like `RTT`, `BytesSent`, etc.  

Many server-based `tcpInfo` stats are optional, so always check for `null`.

### Sample Output

During the **download** test, you typically see a mix of:
- `origin='client'`: every 250ms or so, telling how many total bytes you’ve downloaded so far.
- `origin='server'`: from the server, including `tcpInfo` if available.

During **upload**, the library pushes binary data to saturate your upstream. You typically see:
- `origin='client'`: periodic local counters of how many bytes have been sent.
- `origin='server'`: server’s reported metrics (like `BytesReceived`, `MinRTT`, etc.).

---

## API Reference

### `Ndt7Client`

```dart
class Ndt7Client {
  // Main constructor:
  Ndt7Client({
    required String host,
    String scheme = 'wss',
    String queryParams = '',
    Duration downloadTestDuration = const Duration(seconds: 15),
    Duration uploadTestDuration = const Duration(seconds: 10),
  });

  // Discover nearest M-Lab server:
  static Future<Ndt7Client> withMlab({
    String userAgent = 'ndt7-dart/1.0',
    String scheme = 'wss',
    String queryParams = '',
    Duration downloadTestDuration = const Duration(seconds: 15),
    Duration uploadTestDuration = const Duration(seconds: 10),
  });

  // Download test:
  Stream<Ndt7Measurement> startDownload();

  // Upload test:
  Stream<Ndt7Measurement> startUpload();
}
```

### `Ndt7Measurement`

```dart
class Ndt7Measurement {
  final String? error;
  final String? stackTrace;
  String? origin;      // 'client' or 'server'
  String? test;        // 'download' or 'upload'
  final AppInfo? appInfo;
  final ConnectionInfo? connectionInfo;
  final TCPInfo? tcpInfo;
  // ...
}
```

- `AppInfo` has `elapsedTimeMicros` (int) and `numBytes` (int).
- `ConnectionInfo` has fields like `client`, `server`, `uuid`.
- `TCPInfo` has kernel-level counters (e.g., `busyTime`, `bytesAcked`, etc.).

---

## Example Code

```dart
import 'package:ndt7/ndt7.dart';

Future<void> main() async {
  try {
    // 1) Discover nearest M-Lab server and create an Ndt7Client
    final client = await Ndt7Client.withMlab(
      userAgent: 'my-ndt7-dart/1.0',
      scheme: 'wss', // secure WebSocket
    );

    // 2) Start a download test
    final downloadStream = client.startDownload();
    downloadStream.listen((measurement) {
      if (measurement.error != null) {
        print('Download error: ${measurement.error}');
      } else {
        print('Download measurement => $measurement');
      }
    }, onDone: () {
      print('Download test complete');
    });

    // 3) Start an upload test
    final uploadStream = client.startUpload();
    uploadStream.listen((measurement) {
      if (measurement.error != null) {
        print('Upload error: ${measurement.error}');
      } else {
        print('Upload measurement => $measurement');
      }
    }, onDone: () {
      print('Upload test complete');
    });

  } catch (e, st) {
    print('Failed to create or run ndt7 test: $e\n$st');
  }
}
```

---

## License

This library is released under a BSD-style license. See [LICENSE](LICENSE) for details.  