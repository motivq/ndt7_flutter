import 'package:flutter/material.dart';
// Import your updated ndt7 library with saturating upload + isolates_helper logic
import 'package:ndt7/ndt7.dart';

void main() {
  runApp(const Ndt7ExampleApp());
}

class Ndt7ExampleApp extends StatelessWidget {
  const Ndt7ExampleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ndt7 Isolates Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const Ndt7HomePage(),
    );
  }
}

class Ndt7HomePage extends StatefulWidget {
  const Ndt7HomePage({Key? key}) : super(key: key);

  @override
  State<Ndt7HomePage> createState() => _Ndt7HomePageState();
}

class _Ndt7HomePageState extends State<Ndt7HomePage> {
  late Ndt7Client _client;
  bool _isReady = false;
  String _status = 'Idle';
  String _hostDiscovered = '';
  double _speed = 0;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _initMlab();
  }

  // Discover M-Lab server using token-based locate (withMlabUrls)
  Future<void> _initMlab() async {
    setState(() {
      _status = 'Discovering M-Lab...';
      _logs.clear();
    });
    try {
      final c = await Ndt7Client.withMlabUrls(
        userAgent: 'ndt7-example-flutter/isolates',
      );
      setState(() {
        _client = c;
        _hostDiscovered = c.host;
        _isReady = true;
        _status = 'Ready';
        _logs.add('Discovered host: $_hostDiscovered');
      });
    } catch (e, st) {
      setState(() {
        _status = 'Discovery failed';
        _logs.add('Error: $e\n$st');
      });
    }
  }

  // Start a normal download test
  void _startDownload() {
    if (!_isReady) return;
    setState(() {
      _status = 'Download in progress...';
      _logs.clear();
      _speed = 0;
    });

    // Just call the normal `startDownload()`.
    final stream = _client.startDownload();

    stream.listen((measurement) {
      if (measurement.error != null) {
        // Error from the library
        setState(() {
          _status = 'Download error';
          _logs.add('Error: ${measurement.error}');
        });
      } else if (measurement.appInfo != null &&
          measurement.appInfo!.elapsedTimeMicros > 0) {
        // Client-based measurement
        final us = measurement.appInfo!.elapsedTimeMicros.toDouble();
        final bytes = measurement.appInfo!.numBytes.toDouble();
        final sec = us / 1e6;
        final bits = bytes * 8.0;
        final speed = bits / sec / 1e6; // Mbit/s
        setState(() {
          _speed = speed;
          _logs.add('Download client => ${speed.toStringAsFixed(2)} Mbps');
        });
      }
      // Possibly parse measurement.tcpInfo for server-based stats
    }, onDone: () {
      setState(() {
        _status = 'Download complete';
        _logs.add('Download done');
      });
    });
  }

  // Start an upload test that saturates the link in a background isolate/worker
  void _startUpload() {
    if (!_isReady) return;
    setState(() {
      _status = 'Upload in progress...';
      _logs.clear();
      _speed = 0;
    });

    final stream = _client.startUpload();
    stream.listen((measurement) {
      if (measurement.error != null) {
        setState(() {
          _status = 'Upload error';
          _logs.add('Error: ${measurement.error}');
        });
      } else if (measurement.appInfo != null &&
          measurement.appInfo!.elapsedTimeMicros > 0) {
        // Client-based measurement
        final us = measurement.appInfo!.elapsedTimeMicros.toDouble();
        final bytes = measurement.appInfo!.numBytes.toDouble();
        final sec = us / 1e6;
        final bits = bytes * 8.0;
        final speed = bits / sec / 1e6; // Mbit/s
        setState(() {
          _speed = speed;
          _logs.add('Upload client => ${speed.toStringAsFixed(2)} Mbps');
        });
      }
      // Possibly parse measurement.tcpInfo for server-based stats
    }, onDone: () {
      setState(() {
        _status = 'Upload complete';
        _logs.add('Upload done');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ndt7 + Isolates Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Discovered Host: $_hostDiscovered', style: theme.titleMedium),
            const SizedBox(height: 16),
            Text('Status: $_status', style: theme.titleMedium),
            const SizedBox(height: 16),
            Text('Current Speed: ${_speed.toStringAsFixed(2)} Mbps',
                style: theme.headlineMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isReady ? _startDownload : null,
                  child: const Text('Download'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isReady ? _startUpload : null,
                  child: const Text('Upload'),
                ),
              ],
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(8),
                color: Colors.grey.shade200,
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (ctx, i) =>
                      Text(_logs[i], style: theme.bodyMedium),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
