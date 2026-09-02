import 'dart:io';

import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

final class ImagePreprocessor {
  ImagePreprocessor({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const _directoryName = 'smart_bookkeeping';
  static const _maxAge = Duration(hours: 24);

  final Uuid _uuid;

  Future<File> prepare(String sourcePath, {String? operationId}) async {
    final stopwatch = Stopwatch()..start();
    final source = File(sourcePath);
    if (!await source.exists()) {
      _log.error('image_prepare_missing_source', operationId: operationId);
      throw const FileSystemException('所选图片不存在');
    }
    final sourceBytes = await source.length();
    _log.info(
      'image_prepare_started',
      operationId: operationId,
      fields: {'sourceBytes': sourceBytes},
    );
    final directory = await _temporaryDirectory();
    final targetPath =
        '${directory.path}${Platform.pathSeparator}${_uuid.v7()}.jpg';
    final compressed = await FlutterImageCompress.compressAndGetFile(
      source.path,
      targetPath,
      minWidth: 1920,
      minHeight: 1920,
      quality: 84,
      format: CompressFormat.jpeg,
      keepExif: false,
      autoCorrectionAngle: true,
    );
    if (compressed == null) {
      _log.error(
        'image_prepare_failed',
        operationId: operationId,
        fields: {'elapsedMs': stopwatch.elapsedMilliseconds},
      );
      throw const FileSystemException('图片处理失败');
    }
    final result = File(compressed.path);
    _log.info(
      'image_prepare_completed',
      operationId: operationId,
      fields: {
        'sourceBytes': sourceBytes,
        'outputBytes': await result.length(),
        'elapsedMs': stopwatch.elapsedMilliseconds,
      },
    );
    return result;
  }

  Future<void> delete(String path) async {
    try {
      final file = File(path);
      final directory = await _temporaryDirectory();
      if (_isWithin(file, directory) && await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Temporary cleanup is best-effort and must not block bookkeeping.
    }
  }

  Future<void> cleanupExpired() async {
    try {
      final directory = await _temporaryDirectory();
      final cutoff = DateTime.now().subtract(_maxAge);
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) await entity.delete();
      }
    } on Object {
      // The OS may have already removed the cache directory.
    }
  }

  Future<Directory> _temporaryDirectory() async {
    final base = await getTemporaryDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}$_directoryName',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static bool _isWithin(File file, Directory directory) {
    final root = directory.absolute.path.toLowerCase();
    final target = file.absolute.path.toLowerCase();
    return target == root ||
        target.startsWith('$root${Platform.pathSeparator}');
  }
}

const _log = AppLogger('SmartBookkeeping');
