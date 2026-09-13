// Intentionally exercise the patched platform adapter, not a mock repository.
// ignore_for_file: implementation_imports, depend_on_referenced_packages
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart' as core_mocks;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore_platform_interface/src/method_channel/method_channel_firestore.dart';
import 'package:cloud_firestore_platform_interface/src/method_channel/utils/firestore_message_codec.dart';
import 'package:cloud_firestore_platform_interface/src/pigeon/messages.pigeon.dart';

class _App implements FirebaseApp {
  @override
  String get name => 'race-test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'native error while handler failure awaits cleanup completes only once',
    (tester) async {
      core_mocks.setupFirebaseCoreMocks();
      await Firebase.initializeApp(
        name: 'race-test',
        options: const FirebaseOptions(
          apiKey: 'test',
          appId: 'test',
          messagingSenderId: 'test',
          projectId: 'test',
        ),
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      const prefix =
          'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
      const create = BasicMessageChannel<Object?>(
        '$prefix.transactionCreate',
        FirebaseFirestoreHostApi.codec,
      );
      const store = BasicMessageChannel<Object?>(
        '$prefix.transactionStoreResult',
        FirebaseFirestoreHostApi.codec,
      );
      const eventName =
          'plugins.flutter.io/firebase_firestore/transaction/race';
      const events = MethodChannel(
        eventName,
        StandardMethodCodec(FirestoreMessageCodec()),
      );
      final cleanup = Completer<void>();
      var waitingForCleanup = false;
      messenger.setMockDecodedMessageHandler(create, (_) async => ['race']);
      messenger.setMockDecodedMessageHandler(store, (_) async {
        waitingForCleanup = true;
        await cleanup.future;
        return <Object?>[];
      });
      messenger.setMockMessageHandler(
        eventName,
        (_) async => events.codec.encodeSuccessEnvelope(null),
      );
      addTearDown(() {
        messenger.setMockDecodedMessageHandler(create, null);
        messenger.setMockDecodedMessageHandler(store, null);
        messenger.setMockMessageHandler(eventName, null);
      });
      Future<void> emit(Map<String, Object?> event) async {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          eventName,
          events.codec.encodeSuccessEnvelope(event),
          (_) => done.complete(),
        );
        await done.future;
      }

      final db = MethodChannelFirebaseFirestore(
        app: _App(),
        databaseId: '(default)',
      );
      final result = db.runTransaction<void>(
        (_) async => throw StateError('validation failed'),
      );
      final assertion = expectLater(
        result,
        throwsA(
          isA<FirebaseException>().having((e) => e.code, 'code', 'aborted'),
        ),
      );
      await tester.pump();
      await emit({'appName': 'race-test'});
      await tester.pump();
      expect(waitingForCleanup, isTrue);
      await emit({
        'error': {'code': 'aborted', 'message': 'native transaction failure'},
      });
      await tester.pump();
      cleanup.complete();
      await tester.pump();
      await assertion;
      expect(tester.takeException(), isNull);
    },
  );
}
