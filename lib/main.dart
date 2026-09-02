import 'dart:async';
import 'dart:ui';

import 'package:anbookkeep/app/app.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/image_preprocessor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        _log.error(
          'flutter_framework_error',
          cause: details.exception,
          stackTrace: details.stack,
          fields: {'library': details.library},
        );
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        _log.error(
          'platform_unhandled_error',
          cause: error,
          stackTrace: stackTrace,
        );
        return true;
      };

      _log.info('app_starting');
      unawaited(ImagePreprocessor().cleanupExpired());
      final preferences = await SharedPreferences.getInstance();
      runApp(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: const AnBookkeepApp(),
        ),
      );
      _log.info('app_started');
    },
    (error, stackTrace) {
      _log.error('zone_unhandled_error', cause: error, stackTrace: stackTrace);
    },
  );
}

const _log = AppLogger('App');
