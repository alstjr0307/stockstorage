// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart' as core_mocks;
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/services/subscription_service.dart';

class _Auth extends FirebaseAuthPlatform {
  UserPlatform? user;
  @override
  UserPlatform? get currentUser => user;
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) => this;
}

class _AnonymousUser with MockPlatformInterfaceMixin implements UserPlatform {
  @override
  bool get isAnonymous => true;
  @override
  String get uid => 'anonymous-test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = _Auth();
  setUpAll(() async {
    core_mocks.setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = auth;
  });
  for (final anonymous in [false, true]) {
    test(
      'blocks ${anonymous ? 'anonymous account' : 'logged-out user'} before billing SDK',
      () async {
        auth.user = anonymous ? _AnonymousUser() : null;
        var sdkCalls = 0;
        const channel = MethodChannel('purchases_flutter');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              sdkCalls++;
              throw StateError('Billing SDK must not be called');
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final service = SubscriptionService.instance;
        expect(await service.purchaseMonthly(), isFalse);
        expect(service.lastPurchaseError, contains('로그인 후'));
        expect(await service.restore(), isFalse);
        expect(service.lastPurchaseError, contains('로그인 후'));
        expect(sdkCalls, 0);
      },
    );
  }
}
