// example/lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ndt7/ndt7.dart'; // The updated library

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
  bool _isReady = false;
  String _status = 'Idle';
  String _hostDiscovered = '';
  double _speed = 0;

  // We'll keep a list of textual log lines
  final List<String> _logs = [];

  // We'll store some config fields for a demo UI:
  final TextEditingController _downloadSecsCtrl =
      TextEditingController(text: '15');
  final TextEditingController _uploadSecsCtrl =
      TextEditingController(text: '10');
  final TextEditingController _concurrencyCtrl =
      TextEditingController(text: '1');

  // We'll hold our client. If you want to show concurrency changes or durations,
  // we can rebuild the client each time we press "Apply Config."
  late Ndt7Client _client;

  @override
  void initState() {
    super.initState();
    _initMlab();
  }

  // Discover M-Lab server using the modern approach (withMlabUrls).
  Future<void> _initMlab() async {
    setState(() {
      _status = 'Discovering M-Lab...';
      _logs.clear();
      _isReady = false;
    });
    try {
      // We just do a quick call with default durations & concurrency=1
      final c = await Ndt7Client.withMlabUrls(
        userAgent: 'ndt7-example-flutter/isolates',
      );
      setState(() {
        _client = c;
        _hostDiscovered = c.config.host ?? '';
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

  // A function to update the client config based on our text fields
  void _applyConfig() {
    setState(() {
      final downloadSecs = int.tryParse(_downloadSecsCtrl.text) ?? 15;
      final uploadSecs = int.tryParse(_uploadSecsCtrl.text) ?? 10;
      final concurrency = int.tryParse(_concurrencyCtrl.text) ?? 1;

      // Rebuild the config. We'll keep the same "discovered" host and token URLs if any.
      // We can keep everything the same except durations & concurrency.
      final oldConfig = _client.config;
      final newConfig = Ndt7Config(
        fullDownloadUrl: oldConfig.fullDownloadUrl,
        fullUploadUrl: oldConfig.fullUploadUrl,
        host: oldConfig.host,
        scheme: oldConfig.scheme,
        queryParams: oldConfig.queryParams,
        downloadTestDuration: Duration(seconds: downloadSecs),
        uploadTestDuration: Duration(seconds: uploadSecs),
        concurrency: concurrency,
      );
      _client = Ndt7Client(config: newConfig);
      _logs.add(
          'Updated config => d=$downloadSecs, u=$uploadSecs, concurrency=$concurrency');
    });
  }

  // Start a normal download test
  Future<void> _startDownload() async {
    if (!_isReady) return;
    setState(() {
      _status = 'Download in progress...';
      _logs.clear();
      _speed = 0;
    });

    // Create fresh client for each test
    _client = await Ndt7Client.withMlabUrls(
      userAgent: 'ndt7-example-flutter/isolates',
    );

    // startDownloadTest() returns Ndt7TestResult with a stream + a summary future
    final result = _client.startDownloadTest();

    // Subscribe to real-time measurements
    result.measurements.listen(
      (measurement) {
        if (measurement.error != null) {
          setState(() {
            _status = 'Download error';
            _logs.add('Error: ${measurement.error}');
          });
        } else if (measurement.appInfo != null &&
            measurement.appInfo!.elapsedTimeMicros > 0) {
          final us = measurement.appInfo!.elapsedTimeMicros.toDouble();
          final bytes = measurement.appInfo!.numBytes.toDouble();
          final sec = us / 1e6;
          final bits = bytes * 8.0;
          final speed = bits / sec / 1e6; // Mbit/s
          setState(() {
            _speed = speed;
            _logs.add('Download => ${speed.toStringAsFixed(2)} Mbps');
          });
        }
      },
      onDone: () {
        setState(() {
          _status = 'Download complete';
          _logs.add('Download done');
        });
      },
    );

    // We can also await the final summary if we want:
    result.summary.then((summary) {
      setState(() {
        _logs.add('Final Download Summary => $summary');
      });
    });
  }

  // Start an upload test
  Future<void> _startUpload() async {
    if (!_isReady) return;
    setState(() {
      _status = 'Upload in progress...';
      _logs.clear();
      _speed = 0;
    });

    // Create fresh client for each test
    _client = await Ndt7Client.withMlabUrls(
      userAgent: 'ndt7-example-flutter/isolates',
    );

    final result = _client.startUploadTest();

    result.measurements.listen(
      (measurement) {
        if (measurement.error != null) {
          setState(() {
            _status = 'Upload error';
            _logs.add('Error: ${measurement.error}');
          });
        } else if (measurement.appInfo != null &&
            measurement.appInfo!.elapsedTimeMicros > 0) {
          final us = measurement.appInfo!.elapsedTimeMicros.toDouble();
          final bytes = measurement.appInfo!.numBytes.toDouble();
          final sec = us / 1e6;
          final bits = bytes * 8.0;
          final speed = bits / sec / 1e6; // Mbit/s
          setState(() {
            _speed = speed;
            _logs.add('Upload => ${speed.toStringAsFixed(2)} Mbps');
          });
        }
      },
      onDone: () {
        setState(() {
          _status = 'Upload complete';
          _logs.add('Upload done');
        });
      },
    );

    // Also wait for the summary
    result.summary.then((summary) {
      setState(() {
        _logs.add('Final Upload Summary => $summary');
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
            // Config panel at the top
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _downloadSecsCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Download secs'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _uploadSecsCtrl,
                    decoration: const InputDecoration(labelText: 'Upload secs'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _concurrencyCtrl,
                    decoration: const InputDecoration(labelText: 'Concurrency'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isReady ? _applyConfig : null,
                  child: const Text('Apply Config'),
                ),
              ],
            ),
            const SizedBox(height: 16),

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
