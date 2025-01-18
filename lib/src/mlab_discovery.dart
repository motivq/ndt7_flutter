// lib/src/mlab_discovery.dart

import 'dart:convert';
import 'universal_http.dart';

class MlabLocation {
  final String? country;
  final String? city;

  MlabLocation({
    this.country,
    this.city,
  });
}

/// Holds full URLs for download & upload WebSocket tests
/// as returned by the M-Lab locate service (including tokens).
class MlabServerUrls {
  final String downloadUrl;
  final String uploadUrl;
  final String fqdn;
  final MlabLocation? location;

  MlabServerUrls({
    required this.downloadUrl,
    required this.uploadUrl,
    required this.fqdn,
    this.location,
  });
}

/// A utility class to discover the nearest M-Lab ndt7 server.
class MLabDiscovery {
  /// The older method returns just a single FQDN, ignoring tokens.
  /// If your environment returns just { "fqdn": ... }, you can still use it.
  static Future<String> discoverServer({
    String userAgent = 'ndt7-dart/1.0',
  }) async {
    const url = 'https://locate.measurementlab.net/ndt7';
    print('[MLabDiscovery] GET => $url with User-Agent=$userAgent');

    final response = await universalGet(
      url,
      headers: {
        'User-Agent': userAgent,
        'Accept': 'application/json',
      },
    );

    print('[MLabDiscovery] Response statusCode=${response.statusCode}');

    if (response.statusCode == 200 && response.body != null) {
      final decoded = json.decode(response.body!);
      // If the older locate API just returns: { "fqdn": "..."}
      if (decoded is Map<String, dynamic> && decoded['fqdn'] is String) {
        final fqdn = decoded['fqdn'] as String;
        print('[MLabDiscovery] Found old-style fqdn: $fqdn');
        return fqdn;
      } else {
        throw 'Expected legacy "fqdn" field. Use discoverServerWithUrls() instead.';
      }
    } else if (response.statusCode == 204) {
      throw 'MLabDiscovery: No capacity (HTTP 204). Try again later.';
    } else {
      throw 'MLabDiscovery: HTTP ${response.statusCode} error from locate.measurementlab.net';
    }
  }

  /// Queries a new locate endpoint that returns arrays with "results", each
  /// containing "urls" => { "wss:///v0/ndt7/download": "...?access_token=..." } etc.
  ///
  /// Example snippet:
  ///  {
  ///    "results": [
  ///      {
  ///        "urls": {
  ///          "wss:///v0/ndt7/download": "wss://pt-mlab2-dfw08.../v0/ndt7/download?access_token=..."
  ///          "wss:///v0/ndt7/upload":   "wss://pt-mlab2-dfw08.../v0/ndt7/upload?access_token=..."
  ///        }
  ///      }
  ///    ]
  ///  }
  ///
  /// We pick the first result and read "wss:///v0/ndt7/download" & ".../upload".
  static Future<MlabServerUrls> discoverServerWithUrls({
    String userAgent = 'ndt7-dart/1.0',
  }) async {
    const url =
        'https://locate.measurementlab.net/v2/nearest/ndt/ndt7?format=json';
    // or whichever endpoint returns the "results" array with "urls".

    print('[MLabDiscovery] GET => $url with User-Agent=$userAgent');

    final response = await universalGet(
      url,
      headers: {
        'User-Agent': userAgent,
        'Accept': 'application/json',
      },
    );

    print('[MLabDiscovery] Response statusCode=${response.statusCode}');

    if (response.statusCode == 200 && response.body != null) {
      final decoded = json.decode(response.body!);
      if (decoded is Map<String, dynamic> && decoded['results'] is List) {
        final results = decoded['results'] as List;
        if (results.isEmpty) {
          throw 'MLabDiscovery: results array is empty.';
        }
        // We'll pick the first result
        final first = results[1];
        if (first is Map<String, dynamic> && first['urls'] is Map) {
          final location = first['location'] as Map<String, dynamic>;
          final city = location['city'] as String?;
          final country = location['country'] as String?;

          final urlsMap = first['urls'] as Map;
          final downloadKey = 'wss:///ndt/v7/download';
          final uploadKey = 'wss:///ndt/v7/upload';

          if (!urlsMap.containsKey(downloadKey)) {
            throw 'MLabDiscovery: missing "$downloadKey" in the JSON.';
          }
          final dlUrl = urlsMap[downloadKey] as String;
          final ulUrl = urlsMap[uploadKey] as String;
          final fqdn = first['hostname'] as String;
          print('[MLabDiscovery] Found downloadUrl=$dlUrl, uploadUrl=$ulUrl');

          return MlabServerUrls(
            downloadUrl: dlUrl,
            uploadUrl: ulUrl,
            fqdn: fqdn,
            location: MlabLocation(city: city, country: country),
          );
        } else {
          throw 'MLabDiscovery: Invalid format for "results[0].urls"';
        }
      } else {
        throw 'MLabDiscovery: No "results" array found in locate response.';
      }
    } else if (response.statusCode == 204) {
      throw 'MLabDiscovery: No capacity (HTTP 204). Try again later.';
    } else {
      throw 'MLabDiscovery: HTTP ${response.statusCode} error from locate.measurementlab.net';
    }
  }
}
