// lib/src/universal_http.dart

import 'universal_http_base.dart';
import 'universal_http_stub.dart'
    if (dart.library.io) 'universal_http_io.dart'
    if (dart.library.html) 'universal_http_html.dart';

export 'universal_http_base.dart';
export 'universal_http_stub.dart'
    if (dart.library.io) 'universal_http_io.dart'
    if (dart.library.html) 'universal_http_html.dart';

Future<HttpResponse> universalGet(
  String url, {
  Map<String, String>? headers,
}) {
  return UniversalHttpClient.getRequest(url, headers: headers);
}
