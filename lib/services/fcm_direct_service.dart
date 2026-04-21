import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

/// 서비스 어카운트 키를 사용해 FCM v1 API 직접 호출 (Cloud Functions 없이)
///
/// Firestore _admin/fcm_service_account 문서에 다음 필드가 필요합니다:
///   client_email : 서비스 어카운트 이메일
///   private_key  : RSA 개인키 (PEM 형식, \\n 포함)
class FcmDirectService {
  static const _projectId = 'stockstorage-13828';

  static String _normalizePrivateKey(String rawKey) {
    // Firestore에 따라 "\n", "\\n", "\r\n" 형태가 섞여 저장될 수 있어 정규화
    return rawKey
        .replaceAll(r'\\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll('\r\n', '\n')
        .trim();
  }

  static Future<void> sendTopicNotification({
    required String title,
    required String body,
    String topic = 'stock_alerts',
  }) async {
    try {
      // 1. Firestore에서 서비스 어카운트 정보 읽기
      final doc = await FirebaseFirestore.instance
          .collection('_admin')
          .doc('fcm_service_account')
          .get();

      if (!doc.exists) {
        throw Exception('서비스 어카운트 키가 Firestore에 없습니다. 설정 필요.');
      }

      final data = doc.data()!;
      final clientEmail = data['client_email'] as String;
      final privateKey = _normalizePrivateKey(data['private_key'] as String);

      // 2. JWT 생성
      final nowUtc = DateTime.now().toUtc();
      // 클라이언트 시계 오차를 완화하기 위해 iat를 1분 과거로 설정
      final iat =
          nowUtc.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
          1000;
      // Google OAuth JWT assertion은 최대 60분 이내 만료여야 함
      final exp = iat + (59 * 60);
      final jwt = JWT({
        'iss': clientEmail,
        'scope': 'https://www.googleapis.com/auth/firebase.messaging',
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': iat,
        'exp': exp,
      });
      final signedToken = jwt.sign(
        RSAPrivateKey(privateKey),
        algorithm: JWTAlgorithm.RS256,
      );

      // 3. JWT → OAuth2 액세스 토큰 교환
      final tokenResp = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': signedToken,
        },
      );

      if (tokenResp.statusCode != 200) {
        throw Exception('OAuth2 토큰 발급 실패: ${tokenResp.body}');
      }

      final accessToken = jsonDecode(tokenResp.body)['access_token'] as String;

      // 4. FCM v1 API로 토픽 푸시 발송
      final fcmResp = await http.post(
        Uri.parse(
          'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send',
        ),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'message': {
            'topic': topic,
            'notification': {'title': title, 'body': body},
            'android': {
              'notification': {
                'sound': 'default',
                'channel_id': 'stockstorage_alerts',
              },
            },
            'apns': {
              'payload': {
                'aps': {'sound': 'default'},
              },
            },
          },
        }),
      );

      if (fcmResp.statusCode != 200) {
        throw Exception('FCM 발송 실패: ${fcmResp.body}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
