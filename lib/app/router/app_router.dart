import 'package:anbookkeep/features/analytics/presentation/analytics_page.dart';
import 'package:anbookkeep/features/bookkeeping/presentation/bookkeeping_page.dart';
import 'package:anbookkeep/features/detail/presentation/detail_page.dart';
import 'package:anbookkeep/features/data_transfer/presentation/data_management_page.dart';
import 'package:anbookkeep/features/data_transfer/presentation/export_bills_page.dart';
import 'package:anbookkeep/features/data_transfer/presentation/import_bills_page.dart';
import 'package:anbookkeep/features/lan_backup/presentation/lan_backup_page.dart';
import 'package:anbookkeep/features/search/domain/search_criteria.dart';
import 'package:anbookkeep/features/search/presentation/search_page.dart';
import 'package:anbookkeep/features/settings/presentation/settings_page.dart';
import 'package:anbookkeep/features/settings/presentation/category_management_page.dart';
import 'package:anbookkeep/features/settings/presentation/category_editor_page.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/prompt_template.dart';
import 'package:anbookkeep/features/smart_bookkeeping/presentation/ai_bookkeeping_settings_page.dart';
import 'package:anbookkeep/features/smart_bookkeeping/presentation/prompt_editor_page.dart';
import 'package:anbookkeep/features/smart_bookkeeping/presentation/prompt_management_page.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/smart_bookkeeping_draft.dart';
import 'package:anbookkeep/features/smart_bookkeeping/presentation/batch_recognition_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRoutes {
  static const detail = '/';
  static const bookkeeping = '/bookkeeping';
  static const analytics = '/analytics';
  static const search = '/search';
  static const settings = '/settings';
  static const categories = '/settings/categories';
  static const dataManagement = '/settings/data-management';
  static const exportBills = '/settings/data-management/export';
  static const importBills = '/settings/data-management/import';
  static const lanBackup = '/settings/data-management/lan-backup';
  static const categoryEditor = '/settings/categories/editor';
  static const aiBookkeeping = '/settings/ai-bookkeeping';
  static const aiPrompts = '/settings/ai-bookkeeping/prompts';
  static const aiPromptEditor = '/settings/ai-bookkeeping/prompts/editor';
  static const batchRecognition = '/smart-bookkeeping/batch';
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: AppRoutes.detail,
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('页面不存在')),
    body: Center(
      child: FilledButton(
        onPressed: () => context.go(AppRoutes.detail),
        child: const Text('返回明细'),
      ),
    ),
  ),
  routes: [
    GoRoute(
      path: AppRoutes.detail,
      builder: (context, state) => const DetailPage(),
    ),
    GoRoute(
      path: AppRoutes.bookkeeping,
      builder: (context, state) {
        final args = state.extra;
        return BookkeepingPage(
          initialDraft: args is BookkeepingDraftPageArgs ? args.draft : null,
          returnDraft: args is BookkeepingDraftPageArgs && args.returnDraft,
        );
      },
      routes: [
        GoRoute(
          path: ':transactionId/edit',
          builder: (context, state) => BookkeepingPage(
            transactionId: state.pathParameters['transactionId'],
          ),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.analytics,
      builder: (context, state) => const AnalyticsPage(),
    ),
    GoRoute(
      path: AppRoutes.search,
      builder: (context, state) {
        final criteria = state.extra;
        return SearchPage(
          initialCriteria: criteria is SearchCriteria ? criteria : null,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.batchRecognition,
      builder: (context, state) {
        final args = state.extra;
        if (args is BatchRecognitionArgs) {
          return BatchRecognitionPage(args: args);
        }
        return const Scaffold(body: Center(child: Text('缺少批量识别参数')));
      },
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsPage(),
      routes: [
        GoRoute(
          path: 'data-management',
          builder: (context, state) => const DataManagementPage(),
          routes: [
            GoRoute(
              path: 'export',
              builder: (context, state) => const ExportBillsPage(),
            ),
            GoRoute(
              path: 'import',
              builder: (context, state) => const ImportBillsPage(),
            ),
            GoRoute(
              path: 'lan-backup',
              builder: (context, state) => const LanBackupPage(),
            ),
          ],
        ),
        GoRoute(
          path: 'categories',
          builder: (context, state) => const CategoryManagementPage(),
          routes: [
            GoRoute(
              path: 'editor',
              builder: (context, state) {
                final args = state.extra;
                if (args is CategoryEditorArgs) {
                  return CategoryEditorPage(args: args);
                }
                return const Scaffold(body: Center(child: Text('缺少分类编辑参数')));
              },
            ),
          ],
        ),
        GoRoute(
          path: 'ai-bookkeeping',
          builder: (context, state) => const AiBookkeepingSettingsPage(),
          routes: [
            GoRoute(
              path: 'prompts',
              builder: (context, state) => const PromptManagementPage(),
              routes: [
                GoRoute(
                  path: 'editor',
                  builder: (context, state) => PromptEditorPage(
                    template: state.extra is PromptTemplate
                        ? state.extra! as PromptTemplate
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
