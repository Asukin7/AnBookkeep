import 'dart:async';
import 'dart:io';

import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/database/database_provider.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/data_transfer/application/data_export_service.dart';
import 'package:anbookkeep/features/lan_backup/application/lan_backup_coordinator.dart';
import 'package:anbookkeep/features/lan_backup/domain/lan_backup_settings.dart';
import 'package:anbookkeep/features/lan_backup/presentation/lan_backup_lifecycle.dart';
import 'package:anbookkeep/features/lan_backup/presentation/lan_backup_page.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fingerprint = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _encodedKey = 'dGVzdC1rZXk';
const _connectionKey = '$_fingerprint.$_encodedKey';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('accepts IPv4 and bracketed IPv6 with a valid port', () {
    const ipv4 = LanBackupSettings(directAddress: '172.31.100.203:18765');
    expect(ipv4.directEndpoint?.address.rawAddress, [172, 31, 100, 203]);
    expect(ipv4.directEndpoint?.port, 18765);

    const ipv6 = LanBackupSettings(directAddress: '[2001:db8::1]:65535');
    expect(ipv6.directEndpoint?.address.rawAddress, hasLength(16));
    expect(ipv6.directEndpoint?.port, 65535);

    for (final invalid in [
      '172.31.100.203',
      '172.31.100.203:0',
      '172.31.100.203:65536',
      '172.31.100.256:18765',
      '2001:db8::1:18765',
    ]) {
      expect(LanBackupSettings(directAddress: invalid).directEndpoint, isNull);
    }
  });

  testWidgets('Key is hidden by default and the eye toggles visibility', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'lanBackup.key': 'test-key'});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
        child: const MaterialApp(home: LanBackupPage()),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Key');
    TextField keyField() => tester.widget<TextField>(field);

    expect(find.text('请复制电脑端显示的完整 Key'), findsOneWidget);
    expect(keyField().obscureText, isTrue);
    await tester.tap(find.byTooltip('显示 Key'));
    await tester.pumpAndSettle();
    expect(keyField().obscureText, isFalse);
    expect(keyField().controller!.text, 'test-key');

    await tester.tap(find.byTooltip('隐藏 Key'));
    await tester.pumpAndSettle();
    expect(keyField().obscureText, isTrue);
  });

  test('starts immediately and coalesces edits during an upload', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase(NativeDatabase.memory());
    final repository = BookkeepingRepository(database);
    final coordinator = LanBackupCoordinator(
      database: database,
      preferences: preferences,
      exporter: DataExportService(repository),
      exportSettings: () => const AppSettings(),
    );
    const channel = MethodChannel('com.an.anbookkeep/lan_backup');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final directory = await Directory.systemTemp.createTemp('lan-backup-test-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final uploadStarted = [Completer<void>(), Completer<void>()];
    final finishUpload = [Completer<void>(), Completer<void>()];
    var preparations = 0;
    var uploads = 0;
    messenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => directory.path,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'prepare') {
        expect(call.arguments, {
          'key': _encodedKey,
          'fingerprint': _fingerprint,
          'requireLan': true,
        });
        preparations++;
      } else if (call.method == 'upload') {
        final index = uploads++;
        final arguments = call.arguments as Map<Object?, Object?>;
        expect(arguments['name'], 'AN');
        expect(File(arguments['path']! as String).existsSync(), isTrue);
        uploadStarted[index].complete();
        await finishUpload[index].future;
      }
      return null;
    });
    addTearDown(() async {
      coordinator.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(pathChannel, null);
      await database.close();
      await directory.delete(recursive: true);
    });

    await coordinator.updateSettings(
      const LanBackupSettings(
        enabled: true,
        key: _connectionKey,
        fileName: 'AN',
      ),
    );
    await coordinator.monitorChanges();
    await Future<void>.delayed(Duration.zero);
    expect(preparations, 0);

    Future<void> createBill() => repository.create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.fromDecimal(Decimal.one),
      occurredAt: LocalMinute.parse('2026-11-25 12:00'),
    );

    await createBill();
    await uploadStarted[0].future.timeout(const Duration(seconds: 5));
    expect(preferences.getInt('lanBackup.lastUploadedRevision'), isNull);
    await createBill();
    await createBill();
    expect(preparations, 1);

    finishUpload[0].complete();
    await uploadStarted[1].future.timeout(const Duration(seconds: 5));
    expect(preferences.getInt('lanBackup.lastUploadedRevision'), 1);
    final manualBackup = coordinator.backupNow();
    await Future<void>.delayed(Duration.zero);
    finishUpload[1].complete();
    await manualBackup;
    expect(preferences.getInt('lanBackup.lastUploadedRevision'), 3);
    expect(preparations, 2);
    expect(uploads, 2);

    await coordinator.updateSettings(
      const LanBackupSettings(key: _connectionKey, fileName: 'AN'),
    );
    await createBill();
    await Future<void>.delayed(Duration.zero);
    expect(preparations, 2);
  });

  testWidgets(
    'startup and returning from the background retry only pending revisions',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'lanBackup.enabled': true,
        'lanBackup.fileName': 'AN',
        'lanBackup.lastUploadedRevision': 1,
      });
      FlutterSecureStorage.setMockInitialValues({
        'lanBackup.key': _connectionKey,
      });
      final preferences = await SharedPreferences.getInstance();
      final database = AppDatabase(NativeDatabase.memory());
      final repository = BookkeepingRepository(database);
      LanBackupCoordinator createCoordinator() => LanBackupCoordinator(
        database: database,
        preferences: preferences,
        exporter: DataExportService(repository),
        exportSettings: () => const AppSettings(),
      );
      var coordinator = createCoordinator();
      const channel = MethodChannel('com.an.anbookkeep/lan_backup');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var attempts = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'prepare') {
          attempts++;
          throw PlatformException(code: 'receiver_unavailable');
        }
        return null;
      });
      addTearDown(() async {
        coordinator.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        await database.close();
      });

      Future<void> createBill() => repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.fromDecimal(Decimal.one),
        occurredAt: LocalMinute.parse('2026-11-25 12:00'),
      );
      Future<void> mountMonitor() => tester.pumpWidget(
        ProviderScope(
          overrides: [
            lanBackupCoordinatorProvider.overrideWithValue(coordinator),
          ],
          child: const LanBackupLifecycle(child: SizedBox.shrink()),
        ),
      );
      Future<void> changeAppState(AppLifecycleState state) async {
        final lifecycle = SystemChannels.lifecycle;
        await messenger.handlePlatformMessage(
          lifecycle.name,
          lifecycle.codec.encodeMessage(state.toString()),
          null,
        );
        await tester.pump();
      }

      await changeAppState(AppLifecycleState.resumed);
      await createBill();
      await mountMonitor();
      await tester.pump();
      expect(attempts, 0);
      await changeAppState(AppLifecycleState.paused);
      await changeAppState(AppLifecycleState.resumed);
      expect(attempts, 0);

      await createBill();
      await tester.pump();
      expect(attempts, 1);
      expect(preferences.getInt('lanBackup.lastUploadedRevision'), 1);

      await tester.pump(const Duration(minutes: 1));
      expect(attempts, 1);
      await changeAppState(AppLifecycleState.inactive);
      await changeAppState(AppLifecycleState.resumed);
      expect(attempts, 1);

      await changeAppState(AppLifecycleState.paused);
      expect(attempts, 1);
      await changeAppState(AppLifecycleState.resumed);
      expect(attempts, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      coordinator = createCoordinator();
      await mountMonitor();
      await tester.pump();
      expect(attempts, 3);
      expect(preferences.getInt('lanBackup.lastUploadedRevision'), 1);
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets('saves a direct endpoint and clearing it returns to discovery', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lanBackup.enabled': true,
      'lanBackup.fileName': 'AN',
    });
    FlutterSecureStorage.setMockInitialValues({
      'lanBackup.key': _connectionKey,
    });
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase(NativeDatabase.memory());
    const channel = MethodChannel('com.an.anbookkeep/lan_backup');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final preparations = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'prepare') {
        preparations.add(call.arguments);
        throw PlatformException(code: 'receiver_unreachable');
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(home: LanBackupPage()),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, '直连地址（选填）');
    await tester.enterText(field, '172.31.100.203:18765');
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      preferences.getString('lanBackup.directAddress'),
      '172.31.100.203:18765',
    );

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();
    expect(preparations.single, {
      'key': _encodedKey,
      'fingerprint': _fingerprint,
      'address': [172, 31, 100, 203],
      'port': 18765,
    });

    await tester.enterText(field, '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();
    expect(preparations.last, {
      'key': _encodedKey,
      'fingerprint': _fingerprint,
    });
    expect(preferences.getString('lanBackup.directAddress'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
