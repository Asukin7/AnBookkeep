import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/app/theme/app_theme.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/smart_bookkeeping/presentation/shared_image_intent_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnBookkeepApp extends ConsumerWidget {
  const AnBookkeepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return SharedImageIntentListener(
      child: MaterialApp.router(
        title: '安安记账',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(seedColor: settings.themeColor),
        darkTheme: AppTheme.dark(seedColor: settings.themeColor),
        themeMode: settings.themeMode,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: appRouter,
      ),
    );
  }
}
