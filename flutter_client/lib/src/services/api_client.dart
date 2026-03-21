import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _httpClient.get(_uri(path, query));
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    final response = await _httpClient.post(
      _uri(path, query),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body ?? <String, dynamic>{}),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    final response = await _httpClient.delete(
      _uri(path, query),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body ?? <String, dynamic>{}),
    );
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.body.isEmpty) {
      if (response.statusCode >= 400) {
        throw Exception('Request failed: ${response.statusCode}');
      }
      return <String, dynamic>{};
    }

    dynamic jsonBody;
    try {
      jsonBody = jsonDecode(response.body);
    } on FormatException {
      final snippet = response.body.length > 160
          ? '${response.body.substring(0, 160)}...'
          : response.body;
      final url = response.request?.url.toString() ?? '<unknown-url>';
      throw Exception(
        'Expected JSON but received non-JSON from $url '
        '(status ${response.statusCode}). Response starts with: $snippet',
      );
    }
    if (jsonBody is! Map<String, dynamic>) {
      throw Exception('Unexpected response shape');
    }

    if (response.statusCode >= 400) {
      final err = jsonBody['error'] ?? 'Request failed: ${response.statusCode}';
      throw Exception(err);
    }

    return jsonBody;
  }
}
