// lib/src/universal_http_io.dart
//
// Used if dart.library.io is available

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'universal_http_base.dart';

class UniversalHttpClient implements UniversalHttpClientBase {
  static Future<HttpResponse> getRequest(
    String url, {
    Map<String, String>? headers,
  }) async {
    print('[universal_http_io] GET => $url');
    final uri = Uri.parse(url);
    final client = io.HttpClient();

    try {
      final request = await client.getUrl(uri);
      headers?.forEach((k, v) {
        request.headers.set(k, v);
      });
      final response = await request.close();
      final sc = response.statusCode;
      final body = await response.transform(utf8.decoder).join();
      print('[universal_http_io] statusCode=$sc');
      return HttpResponse(sc, body);
    } finally {
      client.close(force: true);
    }
  }
}

/// This top-level function overrides [UniversalHttpClientBase.get] at runtime
/// when dart:io is available.
Future<HttpResponse> get(String url, {Map<String, String>? headers}) =>
    UniversalHttpClient.getRequest(url, headers: headers);
