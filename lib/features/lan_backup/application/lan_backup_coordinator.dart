import 'dart:async';
import 'dart:io';

import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/database/database_provider.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/data_transfer/application/data_export_service.dart';
import 'package:anbookkeep/features/data_transfer/domain/data_transfer_models.dart';
import 'package:anbookkeep/features/lan_backup/data/lan_backup_client.dart';
import 'package:anbookkeep/features/lan_backup/domain/lan_backup_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final lanBackupCoordinatorProvider = Provider<LanBackupCoordinator>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  if (preferences == null) throw StateError('SharedPreferences尚未初始化');
  final coordinator = LanBackupCoordinator(
    database: ref.watch(appDatabaseProvider),
    preferences: preferences,
    exporter: ref.watch(dataExportServiceProvider),
    exportSettings: () => ref.read(appSettingsProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final class LanBackupCoordinator {
  LanBackupCoordinator({
    required this._database,
    required this._preferences,
    required this._exporter,
    required this._exportSettings,
  });

  static const _enabledKey = 'lanBackup.enabled';
  static const _nameKey = 'lanBackup.fileName';
  static const _directAddressKey = 'lanBackup.directAddress';
  static const _secretKey = 'lanBackup.key';
  static const _revisionKey = 'lanBackup.lastUploadedRevision';
  static const _log = AppLogger('LanBackup');

  final AppDatabase _database;
  final SharedPreferences _preferences;
  final DataExportService _exporter;
  final AppSettings Function() _exportSettings;
  final _secureStorage = const FlutterSecureStorage();
  final _client = const LanBackupClient();

  LanBackupSettings _settings = const LanBackupSettings();
  LanBackupSettings? _persisted;
  Future<void>? _initialization;
  Future<void> _writes = Future.value();
  ({int generation, Future<void> done})? _running;
  StreamSubscription<int>? _revisions;
  int? _pendingRevision;
  int _lastUploadedRevision = 0;
  int _generation = 0;
  bool _monitoring = false;
  bool _disposed = false;

  Future<LanBackupSettings> settings() async {
    await (_initialization ??= _loadSettings());
    return _settings;
  }

  Future<void> _loadSettings() async {
    try {
      _settings = LanBackupSettings(
        enabled: _preferences.getBool(_enabledKey) ?? false,
        key: await _secureStorage.read(key: _secretKey) ?? '',
        fileName: _preferences.getString(_nameKey) ?? '',
        directAddress: _preferences.getString(_directAddressKey) ?? '',
      );
      _persisted = _settings;
      _lastUploadedRevision = _preferences.getInt(_revisionKey) ?? 0;
    } on Object {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> updateSettings(LanBackupSettings value) async {
    await settings();
    if (_disposed) return;
    if (_settings != value) {
      _settings = value;
      _generation++;
      if (_running != null) unawaited(_cancelTransport());
      _stopWatchingRevisions();
    }
    final previous = _writes;
    final write = _persistAfter(previous, value);
    _writes = write;
    await write;
  }

  Future<void> _persistAfter(
    Future<void> previous,
    LanBackupSettings value,
  ) async {
    try {
      await previous;
    } on Object {
      // A later settings save also retries any value that did not persist.
    }
    if (_persisted == value) return;
    if (_persisted?.key != value.key) {
      if (value.key.isEmpty) {
        await _secureStorage.delete(key: _secretKey);
      } else {
        await _secureStorage.write(key: _secretKey, value: value.key);
      }
    }
    if (!await _preferences.setString(_nameKey, value.fileName) ||
        !await _preferences.setString(_directAddressKey, value.directAddress) ||
        !await _preferences.setBool(_enabledKey, value.enabled)) {
      throw StateError('Cannot save backup settings');
    }
    _persisted = value;
    if (_settings == value) _watchRevisions();
  }

  Future<void> monitorChanges() async {
    if (_disposed) return;
    _monitoring = true;
    try {
      await settings();
      if (_revisions == null) {
        _watchRevisions();
        return;
      }
      final generation = _generation;
      final revision = await _database.readBackupRevision().getSingle();
      if (!_disposed && generation == _generation) {
        _queueAutomaticBackup(revision);
      }
    } on Object catch (error) {
      _log.error('lan_backup_monitor_failed', cause: error);
    }
  }

  void _stopWatchingRevisions() {
    final previous = _revisions;
    _revisions = null;
    _pendingRevision = null;
    if (previous != null) unawaited(previous.cancel());
  }

  void _watchRevisions() {
    _stopWatchingRevisions();
    if (_disposed ||
        !_monitoring ||
        !_settings.canBackUp ||
        _settings != _persisted) {
      return;
    }
    _revisions = _database.readBackupRevision().watchSingle().distinct().listen(
      _queueAutomaticBackup,
      onError: (Object error) =>
          _log.error('lan_backup_revision_watch_failed', cause: error),
    );
  }

  void _queueAutomaticBackup(int revision) {
    if (_isBackedUp(revision) || revision <= (_pendingRevision ?? 0)) return;
    _pendingRevision = revision;
    _startPendingBackup();
  }

  void _startPendingBackup() {
    final revision = _pendingRevision;
    if (_running != null || revision == null) return;
    _pendingRevision = null;
    if (_disposed || !_settings.canBackUp || _isBackedUp(revision)) return;
    unawaited(
      _start(manual: false).catchError((Object error) {
        if (error is PlatformException &&
            (error.code == 'cancelled' || error.code == 'lan_unavailable')) {
          return;
        }
        _log.error('lan_backup_automatic_failed', cause: error);
      }),
    );
  }

  bool _isBackedUp(int revision) => revision <= _lastUploadedRevision;

  Future<void> backupNow() async {
    await settings();
    for (
      var active = _running;
      active != null && active.generation != _generation;
      active = _running
    ) {
      try {
        await active.done;
      } on Object {
        // Changing the address can cancel the previous backup.
      }
    }
    await _writes;
    if (!_settings.canBackUp || _disposed) {
      throw PlatformException(code: 'backup_not_configured');
    }
    final active = _running;
    if (active == null) {
      await _start(manual: true);
      return;
    }
    final revision = await _database.readBackupRevision().getSingle();
    await active.done;
    _ensureCurrent(active.generation);
    if (!_isBackedUp(revision)) {
      await (_running?.done ?? _start(manual: true));
    }
  }

  Future<void> _start({required bool manual}) {
    final generation = _generation;
    final result = _perform(_settings, generation, manual: manual).whenComplete(
      () {
        _running = null;
        _startPendingBackup();
      },
    );
    _running = (generation: generation, done: result);
    return result;
  }

  Future<void> _perform(
    LanBackupSettings configuration,
    int generation, {
    required bool manual,
  }) async {
    _ensureCurrent(generation);
    Directory? directory;
    try {
      await _client.prepare(
        configuration.connectionKey!,
        directEndpoint: configuration.directEndpoint,
        requireLan: !manual,
      );
      final revision = await _database.readBackupRevision().getSingle();
      _ensureCurrent(generation);
      final exportSettings = _exportSettings();
      final payload = await _exporter.build(
        format: ExportFileFormat.xlsx,
        timePrecision: exportSettings.timePrecision,
        themeColor: exportSettings.themeColor,
      );
      _ensureCurrent(generation);
      directory = await (await getTemporaryDirectory()).createTemp(
        'lan-backup-',
      );
      final file = await File(
        '${directory.path}${Platform.pathSeparator}backup.xlsx',
      ).writeAsBytes(payload.bytes);
      _ensureCurrent(generation);
      await _client.upload(path: file.path, name: configuration.fileName);
      _ensureCurrent(generation);
      if (!await _preferences.setInt(_revisionKey, revision)) {
        throw StateError('Cannot record successful backup');
      }
      _lastUploadedRevision = revision;
    } finally {
      await _cancelTransport();
      if (directory != null) {
        try {
          await directory.delete(recursive: true);
        } on FileSystemException catch (error) {
          _log.error('lan_backup_temp_cleanup_failed', cause: error);
        }
      }
    }
  }

  void _ensureCurrent(int generation) {
    if (_disposed || generation != _generation) {
      throw PlatformException(code: 'cancelled');
    }
  }

  Future<void> _cancelTransport() async {
    try {
      await _client.cancel();
    } on Object catch (error) {
      _log.error('lan_backup_connection_cleanup_failed', cause: error);
    }
  }

  void dispose() {
    _disposed = true;
    _stopWatchingRevisions();
    if (_running != null) unawaited(_cancelTransport());
  }
}
