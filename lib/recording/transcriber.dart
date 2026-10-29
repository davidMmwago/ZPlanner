import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../data/app_files.dart';
import '../data/kv.dart';
import '../data/models.dart';
import '../mascot/ghost.dart';
import '../mascot/mascot.dart';

class TranscriptSegment {
  final Duration start;
  final Duration end;
  final String text;
  const TranscriptSegment(this.start, this.end, this.text);

  Map<String, dynamic> toJson() => {'s': start.inMilliseconds, 'e': end.inMilliseconds, 't': text};

  factory TranscriptSegment.fromJson(Map<String, dynamic> j) => TranscriptSegment(
        Duration(milliseconds: j['s'] as int),
        Duration(milliseconds: j['e'] as int),
        j['t'] as String,
      );
}

/// Turns recordings into text on the tablet (whisper.cpp, no internet needed
/// after the one-time model download).
///   Quick    = tiny.en model (~75 MB), roughly half the recording's length
///   Accurate = base.en model (~142 MB), roughly as long as the recording
class Transcriber extends ChangeNotifier {
  Transcriber._();
  static final Transcriber instance = Transcriber._();

  final _whisper = WhisperController();

  /// Jobs in progress: item id → (status text, percent or -1).
  final Map<int, (String, int)> jobs = {};

  static Future<bool> accurate() async => await Kv.get('whisper_accurate') == '1';
  static Future<void> setAccurate(bool v) => Kv.set('whisper_accurate', v ? '1' : '0');

  static Future<List<TranscriptSegment>?> load(int itemId) async {
    final f = AppFiles.transcriptFile(itemId);
    if (!await f.exists()) return null;
    final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return [
      for (final s in data['segments'] as List) TranscriptSegment.fromJson(s as Map<String, dynamic>)
    ];
  }

  void _set(int id, String stage, int pct) {
    jobs[id] = (stage, pct);
    notifyListeners();
  }

  /// Transcribes a recording and saves the transcript next to it.
  Future<void> transcribe(StudyItem item) async {
    if (jobs.containsKey(item.id) || item.fileName == null) return;
    final model = await accurate() ? WhisperModel.baseEn : WhisperModel.tinyEn;
    try {
      final modelPath = await _whisper.getPath(model);
      if (!File(modelPath).existsSync()) {
        _set(item.id, 'Downloading the speech model (one time only)…', -1);
        await _whisper.downloadModel(model);
      }
      _set(item.id, 'Transcribing…', 0);
      final result = await _whisper.transcribe(
        model: model,
        audioPath: AppFiles.recordingPath(item.fileName!),
        lang: 'en',
        withSegments: true,
        maxContext: 0, // fewer repeated lines on long recordings
        onProgress: (p) => _set(item.id, 'Transcribing…', p),
      );
      if (result == null) throw Exception('the speech engine returned nothing');

      final segs = <TranscriptSegment>[
        for (final s in result.transcription.segments ?? const <WhisperTranscribeSegment>[])
          if (s.text.trim().isNotEmpty) TranscriptSegment(s.fromTs, s.toTs, s.text.trim()),
      ];
      if (segs.isEmpty && result.transcription.text.trim().isNotEmpty) {
        segs.add(TranscriptSegment(Duration.zero, Duration(seconds: item.pageCount),
            result.transcription.text.trim()));
      }
      await AppFiles.transcriptFile(item.id).writeAsString(jsonEncode({
        'model': model.toString(),
        'segments': [for (final s in segs) s.toJson()],
      }));
      Mascot.instance.say('Your transcript of "${item.title}" is ready!', pose: GhostPose.flower);
    } catch (e) {
      Mascot.instance.say('Sorry, I couldn\'t transcribe "${item.title}". ($e)');
    } finally {
      jobs.remove(item.id);
      notifyListeners();
    }
  }
}
