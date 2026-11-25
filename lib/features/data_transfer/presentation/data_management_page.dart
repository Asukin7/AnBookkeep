import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DataManagementPage extends StatelessWidget {
  const DataManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: const Text('数据管理'),
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          AppCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('导出账单'),
                  subtitle: const Text('导出为 XLSX 或 CSV 文件'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.exportBills),
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('导入账单'),
                  subtitle: const Text('从 XLSX 或 CSV 文件导入'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.importBills),
                ),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('局域网备份'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.lanBackup),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
