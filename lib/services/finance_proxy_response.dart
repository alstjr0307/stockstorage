import 'dart:convert';

import 'package:http/http.dart' as http;

/// The callable proxy returns decoded strings, including Korean JSON and HTML.
/// Response's default Latin-1 encoding cannot represent those strings.
http.Response financeProxyResponse(Map<String, dynamic> item) =>
    http.Response.bytes(
      utf8.encode((item['body'] ?? '') as String),
      (item['status'] ?? 502) as int,
      headers: const {'content-type': 'text/plain; charset=utf-8'},
    );
