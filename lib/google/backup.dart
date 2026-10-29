import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_files.dart';
import '../data/db.dart';
import '../data/kv.dart';
import 'google_api.dart';

/// Backs everything up to a private folder in her Google Drive (only this app
/// can see it) and restores it onto a tablet.
class Backup {
  static Future<DateTime?> lastBackup() async {
    final v = await Kv.get('last_backup');
    return v == null ? null : DateTime.tryParse(v);
  }

  static Future<void> backUpNow({required bool includeRecordings}) async {
    final zip = await _makeZip(includeRecordings: includeRecordings);
    try {
      await GoogleApi.uploadBackup(zip);
      await Kv.set('last_backup', DateTime.now().toIso8601String());
    } finally {
      if (await zip.exists()) await zip.delete();
    }
  }

  static Future<File> _makeZip({required bool includeRecordings}) async {
    final tmp = await getTemporaryDirectory();
    final zipPath = p.join(tmp.path, GoogleApi.backupName);
    final dbPath = await AppDb.instance.dbPath();
    await AppDb.instance.close(); // make sure everything is written to disk
    final enc = ZipFileEncoder();
    enc.create(zipPath);
    await enc.addFile(File(dbPath)); // stored as zee.db
    for (final folder in AppFiles.folders) {
      if (folder == 'recordings' && !includeRecordings) continue;
      final d = Directory(AppFiles.dir(folder));
      if (await d.exists()) await enc.addDirectory(d); // stored as docs/…, ink/…
    }
    await enc.close();
    return File(zipPath);
  }

  /// Replaces everything on this tablet with the newest backup.
  /// The app must be restarted afterwards.
  static Future<void> restoreLatest() async {
    final latest = await GoogleApi.latestBackup();
    if (latest == null) throw const GoogleApiException('No backup found in this Google account.');

    final tmp = await getTemporaryDirectory();
    final zip = File(p.join(tmp.path, 'restore.zip'));
    final out = Directory(p.join(tmp.path, 'restore'));
    if (await out.exists()) await out.delete(recursive: true);
    await GoogleApi.downloadFile(latest.$1, zip);
    await extractFileToDisk(zip.path, out.path);

    final restoredDb = File(p.join(out.path, 'zee.db'));
    if (!await restoredDb.exists()) {
      throw const GoogleApiException('That backup looks incomplete, so nothing was changed.');
    }

    await AppDb.instance.close();
    await restoredDb.copy(await AppDb.instance.dbPath());
    for (final folder in AppFiles.folders) {
      final from = Directory(p.join(out.path, folder));
      if (!await from.exists()) continue; // e.g. recordings left out of the backup
      final to = Directory(AppFiles.dir(folder));
      if (await to.exists()) await to.delete(recursive: true);
      await _copyDir(from, to);
    }
    await zip.delete();
    await out.delete(recursive: true);
  }

  static Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list(recursive: false)) {
      final target = p.join(to.path, p.basename(e.path));
      if (e is File) {
        await e.copy(target);
      } else if (e is Directory) {
        await _copyDir(e, Directory(target));
      }
    }
  }
}
