// lib/src/universal_http_html.dart
//
// Used if dart.library.html is available (web).

import 'dart:async';
import 'dart:html';

import 'universal_http_base.dart';

class UniversalHttpClient implements UniversalHttpClientBase {
  static Future<HttpResponse> getRequest(
    String url, {
    Map<String, String>? headers,
  }) async {
    print('[universal_http_html] GET => $url');
    final req = await HttpRequest.request(
      url,
      method: 'GET',
      requestHeaders: headers ?? {},
    );
    final sc = req.status;
    final body = req.responseText;
    print('[universal_http_html] statusCode=${sc ?? 0}');
    return HttpResponse(sc ?? 0, body);
  }
}

/// This top-level function overrides [UniversalHttpClientBase.get] at runtime
/// on Web
Future<HttpResponse> get(String url, {Map<String, String>? headers}) =>
    UniversalHttpClient.getRequest(url, headers: headers);
