import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/app_files.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../util/format.dart';

/// Records audio (e.g. a lecture) into a module. Lives for the whole app,
/// so recording continues while she moves between notes and slides.
///
/// Note: Android only lets the microphone keep recording while the app is
/// on screen, so the screen is kept awake while recording.
class RecordingController extends ChangeNotifier {
  RecordingController._();
  static final RecordingController instance = RecordingController._();

  final _rec = AudioRecorder();
  bool recording = false;
  bool paused = false;
  int? moduleId;
  String? _fileName;
  DateTime? _since;
  Duration _before = Duration.zero;
  Timer? _ticker;

  Duration get elapsed =>
      _before + (_since == null || paused ? Duration.zero : DateTime.now().difference(_since!));

  /// Starts recording. Returns false if the microphone permission was refused.
  Future<bool> start(int moduleId) async {
    if (recording) return true;
    if (!await _rec.hasPermission()) return false;
    final now = DateTime.now();
    _fileName = 'rec_${now.millisecondsSinceEpoch}.m4a';
    await _rec.start(
      // Mono AAC at 64 kbps: clear speech at ~29 MB per hour.
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
      path: AppFiles.recordingPath(_fileName!),
    );
    this.moduleId = moduleId;
    recording = true;
    paused = false;
    _before = Duration.zero;
    _since = now;
    WakelockPlus.enable();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
    return true;
  }

  Future<void> pause() async {
    if (!recording || paused) return;
    await _rec.pause();
    _before = elapsed;
    _since = null;
    paused = true;
    notifyListeners();
  }

  Future<void> resume() async {
    if (!recording || !paused) return;
    await _rec.resume();
    _since = DateTime.now();
    paused = false;
    notifyListeners();
  }

  /// Stops and saves the recording into the module. Returns the new item.
  Future<StudyItem?> stop() async {
    if (!recording) return null;
    final length = elapsed;
    await _rec.stop();
    _ticker?.cancel();
    WakelockPlus.disable();
    recording = false;
    paused = false;
    _since = null;
    final mId = moduleId, name = _fileName;
    notifyListeners();
    if (mId == null || name == null) return null;
    final d = DateTime.now();
    final id = await AppDb.instance.addItem(
      moduleId: mId,
      type: ItemType.audio,
      title: 'Recording ${d.day} ${monthsShort[d.month - 1]} ${hhmm(d)}',
      fileName: name,
      pageCount: length.inSeconds, // length in seconds
    );
    return AppDb.instance.item(id);
  }
}
