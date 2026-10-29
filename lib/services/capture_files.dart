import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Capture originals and exported clipboard files have independent lifetimes.
class CaptureFiles {
  static Future<void> deleteOriginal(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A later startup cleanup retries stale files.
    }
  }

  static Future<void> cleanStale({String? clipboardPath}) async {
    final temp = await getTemporaryDirectory();
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final clipboardUri = clipboardPath == null
        ? null
        : File(clipboardPath).absolute.uri.normalizePath();
    for (final name in ['snap_craft_captures', 'snap_craft_clipboard']) {
      final dir = Directory('${temp.path}/$name');
      if (!await dir.exists()) continue;
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! File ||
            entry.absolute.uri.normalizePath() == clipboardUri)
          continue;
        final base = entry.uri.pathSegments.last;
        if (!RegExp(r'^(snap|clipboard)_\d+\.png$').hasMatch(base)) continue;
        try {
          if ((await entry.stat()).modified.isBefore(cutoff)) {
            await entry.delete();
          }
        } on FileSystemException {
          // Best effort: another process or the OS may have removed it.
        }
      }
    }
    final updates = Directory('${temp.path}/snap_craft_update');
    if (await updates.exists()) {
      await for (final entry in updates.list(followLinks: false)) {
        if (entry is! Directory ||
            !entry.uri.pathSegments
                .where((part) => part.isNotEmpty)
                .last
                .startsWith('install_')) {
          continue;
        }
        try {
          if ((await entry.stat()).modified.isBefore(cutoff)) {
            await entry.delete(recursive: true);
          }
        } on FileSystemException {
          // Keep installation artifacts if they cannot safely be removed.
        }
      }
    }
  }
}
