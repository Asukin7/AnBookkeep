import 'dart:async';

import 'package:anbookkeep/features/lan_backup/application/lan_backup_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LanBackupLifecycle extends ConsumerStatefulWidget {
  const LanBackupLifecycle({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<LanBackupLifecycle> createState() => _LanBackupLifecycleState();
}

class _LanBackupLifecycleState extends ConsumerState<LanBackupLifecycle> {
  AppLifecycleListener? _listener;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final coordinator = ref.read(lanBackupCoordinatorProvider);
    _listener = AppLifecycleListener(
      onShow: () => unawaited(coordinator.monitorChanges()),
    );
    unawaited(coordinator.monitorChanges());
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
