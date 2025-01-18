// lib/src/universal_http_base.dart

/// A simple holder for an HTTP response status code and body.
class HttpResponse {
  final int statusCode;
  final String? body;

  HttpResponse(this.statusCode, this.body);
}

/// A minimal interface for universal HTTP GET.
abstract class UniversalHttpClientBase {
  static Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
  }) {
    throw UnsupportedError(
      'No UniversalHttpClient implementation for this platform',
    );
  }
}
