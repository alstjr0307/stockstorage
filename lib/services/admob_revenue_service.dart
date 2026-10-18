import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AdmobRevenueService {
  static const scope = 'https://www.googleapis.com/auth/admob.report';
  // Public OAuth client ID from this project's google-services.json.
  final _google = GoogleSignIn(
    scopes: const [scope],
    clientId: kIsWeb
        ? '475716336297-g6g9jjshmnhr68e7ocoaielvsh2i224n.apps.googleusercontent.com'
        : null,
  );
  String? _accessToken;

  Future<bool> connect() async {
    _accessToken = null;
    await _google.signOut();
    final account = await _google.signIn();
    if (account == null) return false;
    // This plugin implements canAccessScopes only on web.
    if (!(kIsWeb && await _google.canAccessScopes([scope])) &&
        !await _google.requestScopes([scope])) {
      return false;
    }
    // This authorizes reports only; never signs in/out of Firebase Auth.
    _accessToken = (await account.authentication).accessToken;
    return _accessToken != null;
  }

  Future<Map<String, dynamic>> load({bool refresh = false}) async {
    if (_accessToken == null && !kIsWeb) {
      try {
        final account = await _google.signInSilently();
        _accessToken = (await account?.authentication)?.accessToken;
      } catch (_) {
        // Cached reports remain available without prompting on tab open.
      }
    }
    final result =
        await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable(
              'getAdminAdmobRevenue',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 55),
              ),
            )
            .call<Map<String, dynamic>>({
              if (_accessToken != null) 'accessToken': _accessToken,
              'refresh': refresh,
            });
    return result.data;
  }
}
