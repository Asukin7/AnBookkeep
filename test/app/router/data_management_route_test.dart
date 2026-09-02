import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/features/data_transfer/presentation/data_management_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings data management route opens the page', (tester) async {
    appRouter.go(AppRoutes.dataManagement);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DataManagementPage), findsOneWidget);
    expect(find.text('页面不存在'), findsNothing);
  });
}
