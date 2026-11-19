// Verifies production store opening against a simulated shared native database.
// Method-channel fakes only: no device, database file, or real key storage.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'opening a shared store never rolls back another engine transaction',
    () async {
      const databaseChannel = MethodChannel('com.tekartik.sqflite');
      const secureChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final previousFactory = databaseFactoryOrNull;
      final calls = <MethodCall>[];
      final key = List<int>.generate(32, (index) => index);
      var foreignTransactionActive = true;
      Database? opened;

      databaseFactory = databaseFactorySqflitePlugin;
      addTearDown(() async {
        await opened?.close();
        databaseFactory = previousFactory;
        messenger.setMockMethodCallHandler(databaseChannel, null);
        messenger.setMockMethodCallHandler(secureChannel, null);
      });

      messenger.setMockMethodCallHandler(secureChannel, (call) async {
        expect(
          call.method,
          'read',
          reason: 'Opening must not rotate the existing key.',
        );
        expect(call.arguments['key'], 'medbuddy_dose_outbox_key_v1');
        return base64Encode(key);
      });
      messenger.setMockMethodCallHandler(databaseChannel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getDatabasesPath':
            return '${Directory.systemTemp.path}/dose-open-channel-test';
          case 'openDatabase':
            expect(call.arguments['singleInstance'], isTrue);
            return {
              'id': 41,
              'recovered': true,
              'recoveredInTransaction': true,
            };
          case 'query':
            expect(call.arguments['sql'], 'PRAGMA user_version');
            return {
              'columns': ['user_version'],
              'rows': [
                [1],
              ],
            };
          case 'execute':
            if (call.arguments['sql'] == 'ROLLBACK') {
              foreignTransactionActive = false;
              return null;
            }
            fail(
              'Unexpected SQL while opening an existing store: ${call.arguments}',
            );
          case 'closeDatabase':
            return null;
          default:
            fail('Unexpected database operation: ${call.method}');
        }
      });

      final store = await DoseOutboxStore.open();
      opened = store.db;

      expect(
        calls.where((call) => call.method == 'openDatabase'),
        hasLength(1),
      );
      expect(
        calls.where((call) => call.method == 'execute'),
        isEmpty,
        reason:
            'A recovered connection belongs to a live engine, not a hot restart.',
      );
      expect(foreignTransactionActive, isTrue);
      expect(await store.key.extractBytes(), key);
    },
  );
}
