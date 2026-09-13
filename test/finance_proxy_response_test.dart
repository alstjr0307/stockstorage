import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/services/finance_proxy_response.dart';

void main() {
  test('proxy preserves Korean JSON and HTML without Latin-1 failures', () {
    for (final body in [
      '{"stockName":"코스피","direction":"상승"}',
      '<p>시세 · € 📈</p>',
    ]) {
      final response = financeProxyResponse({'status': 200, 'body': body});
      expect(response.statusCode, 200);
      expect(response.body, body);
      expect(utf8.decode(response.bodyBytes), body);
    }
  });

  test('missing proxy result remains an explicit failure', () {
    expect(financeProxyResponse({}).statusCode, 502);
  });
}
