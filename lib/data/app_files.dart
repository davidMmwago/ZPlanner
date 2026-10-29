import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Where the app keeps its files on the tablet.
///   docs/         imported PDFs
///   ink/          drawings (one JSON file per document or note)
///   recordings/   audio recordings
///   transcripts/  transcripts (one JSON file per recording)
class AppFiles {
  static late Directory root;
  static const folders = ['docs', 'ink', 'recordings', 'transcripts'];

  static Future<void> init() async {
    root = await getApplicationDocumentsDirectory();
    for (final f in folders) {
      await Directory(p.join(root.path, f)).create(recursive: true);
    }
  }

  static String dir(String folder) => p.join(root.path, folder);

  static String docPath(String fileName) => p.join(root.path, 'docs', fileName);

  static String recordingPath(String fileName) => p.join(root.path, 'recordings', fileName);

  static File inkFile(int itemId) => File(p.join(root.path, 'ink', '$itemId.json'));

  static File transcriptFile(int itemId) =>
      File(p.join(root.path, 'transcripts', '$itemId.json'));

  /// Copies a picked PDF into app storage and returns the new file name.
  static Future<String> importPdf(String sourcePath) async {
    final name = uniqueName(p.basename(sourcePath));
    await File(sourcePath).copy(docPath(name));
    return name;
  }

  /// Copies a picked audio file into recordings/ and returns the new file name.
  static Future<String> importAudio(String sourcePath) async {
    final name = uniqueName(p.basename(sourcePath));
    await File(sourcePath).copy(recordingPath(name));
    return name;
  }

  static String uniqueName(String base) {
    final clean = base.replaceAll(RegExp(r'[^\w\-. ]'), '_');
    return '${DateTime.now().millisecondsSinceEpoch}_$clean';
  }

  static Future<void> deleteItemFiles(StudyItem item) async {
    final files = <File>[
      inkFile(item.id),
      transcriptFile(item.id),
      if (item.fileName != null && item.type == ItemType.pdf) File(docPath(item.fileName!)),
      if (item.fileName != null && item.type == ItemType.audio) File(recordingPath(item.fileName!)),
    ];
    for (final f in files) {
      if (await f.exists()) await f.delete();
    }
  }
}
