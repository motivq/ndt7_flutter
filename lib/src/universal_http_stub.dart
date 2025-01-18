// lib/src/universal_http_stub.dart

import 'dart:async';

import 'universal_http_base.dart';

class UniversalHttpClient implements UniversalHttpClientBase {
  static Future<HttpResponse> getRequest(
    String url, {
    Map<String, String>? headers,
  }) async {
    // DEBUG:
    print('[universal_http_stub] Attempting GET => $url, but stub is used!');
    throw UnsupportedError('No HTTP implementation for this platform');
  }
}

/// This top-level function overrides [UniversalHttpClientBase.get] at runtime
/// if neither dart.library.io nor dart.library.html is found.
Future<HttpResponse> get(String url, {Map<String, String>? headers}) =>
    UniversalHttpClient.getRequest(url, headers: headers);
