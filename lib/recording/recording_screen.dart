import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../data/app_files.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import 'transcriber.dart';

/// Play a recording and read (or make) its transcript.
/// Tapping a line of the transcript jumps the audio there.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key, required this.item});
  final StudyItem item;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription>[];
  Duration _pos = Duration.zero;
  Duration _len = Duration.zero;
  bool _playing = false;
  double _speed = 1.0;
  List<TranscriptSegment>? _segments;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
    Transcriber.instance.addListener(_onJobs);
  }

  Future<void> _init() async {
    try {
      final d = await _player.setFilePath(AppFiles.recordingPath(widget.item.fileName!));
      _len = d ?? Duration(seconds: widget.item.pageCount);
      _subs.add(_player.positionStream.listen((p) => setState(() => _pos = p)));
      _subs.add(_player.playerStateStream.listen((s) {
        setState(() => _playing = s.playing && s.processingState != ProcessingState.completed);
        if (s.processingState == ProcessingState.completed) {
          _player.pause();
          _player.seek(Duration.zero);
        }
      }));
    } catch (e) {
      _error = 'Could not open this recording ($e)';
    }
    _segments = await Transcriber.load(widget.item.id);
    if (mounted) setState(() => _loaded = true);
  }

  bool _wasRunning = false;
  void _onJobs() async {
    final running = Transcriber.instance.jobs.containsKey(widget.item.id);
    if (_wasRunning && !running) {
      final s = await Transcriber.load(widget.item.id);
      if (mounted) setState(() => _segments = s);
    }
    _wasRunning = running;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Transcriber.instance.removeListener(_onJobs);
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  String _t(Duration d) => d.inHours > 0
      ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
      : '${d.inMinutes}:${two(d.inSeconds % 60)}';

  void _skip(int seconds) {
    var p = _pos + Duration(seconds: seconds);
    if (p < Duration.zero) p = Duration.zero;
    if (p > _len) p = _len;
    _player.seek(p);
  }

  Future<void> _startTranscribe() async {
    final accurate = await Transcriber.accurate();
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transcribe this recording?'),
        content: Text(
          'This runs on the tablet, so it works offline.\n\n'
          '• Mode: ${accurate ? 'Accurate' : 'Quick'} (change it in Settings)\n'
          '• It can take ${accurate ? 'about as long as the recording' : 'about half the recording\'s length'}.\n'
          '• Keep the app open while it works.\n'
          '• The first time, it downloads the speech model (${accurate ? '~142' : '~75'} MB).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Transcribe')),
        ],
      ),
    );
    if (go == true) Transcriber.instance.transcribe(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final job = Transcriber.instance.jobs[widget.item.id];
    final segs = _segments;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.title),
        actions: [
          if (segs != null && segs.isNotEmpty)
            IconButton(
              tooltip: 'Copy transcript',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: segs.map((s) => s.text).join(' ')));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Transcript copied')));
                }
              },
            ),
          const SizedBox(width: AppSpace.s),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // ── Player ──
              Card(
                margin: const EdgeInsets.all(AppSpace.l),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.l),
                  child: _error != null
                      ? Text(_error!)
                      : Column(children: [
                          Slider(
                            value: _pos.inMilliseconds.clamp(0, _len.inMilliseconds).toDouble(),
                            max: _len.inMilliseconds <= 0 ? 1 : _len.inMilliseconds.toDouble(),
                            onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
                          ),
                          Row(children: [
                            Text(_t(_pos), style: const TextStyle(color: AppPalette.muted)),
                            const Spacer(),
                            Text(_t(_len), style: const TextStyle(color: AppPalette.muted)),
                          ]),
                          const SizedBox(height: AppSpace.s),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            IconButton(
                                tooltip: 'Back 10 s',
                                iconSize: 32,
                                onPressed: () => _skip(-10),
                                icon: const Icon(Icons.replay_10)),
                            const SizedBox(width: AppSpace.m),
                            IconButton.filled(
                              iconSize: 40,
                              onPressed: _playing ? _player.pause : _player.play,
                              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                            ),
                            const SizedBox(width: AppSpace.m),
                            IconButton(
                                tooltip: 'Forward 10 s',
                                iconSize: 32,
                                onPressed: () => _skip(10),
                                icon: const Icon(Icons.forward_10)),
                            const SizedBox(width: AppSpace.l),
                            PopupMenuButton<double>(
                              tooltip: 'Speed',
                              initialValue: _speed,
                              onSelected: (v) {
                                setState(() => _speed = v);
                                _player.setSpeed(v);
                              },
                              itemBuilder: (_) => [
                                for (final v in const [0.75, 1.0, 1.25, 1.5, 2.0])
                                  PopupMenuItem(value: v, child: Text('${v}x')),
                              ],
                              child: Chip(label: Text('${_speed}x')),
                            ),
                          ]),
                        ]),
                ),
              ),
              // ── Transcript ──
              Expanded(
                child: Card(
                  margin: const EdgeInsets.fromLTRB(AppSpace.l, 0, AppSpace.l, AppSpace.l),
                  child: job != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpace.xl),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(job.$1, style: t.titleMedium),
                              const SizedBox(height: AppSpace.m),
                              SizedBox(
                                width: 320,
                                child: LinearProgressIndicator(value: job.$2 < 0 ? null : job.$2 / 100),
                              ),
                              const SizedBox(height: AppSpace.s),
                              if (job.$2 >= 0) Text('${job.$2}%', style: const TextStyle(color: AppPalette.muted)),
                              const SizedBox(height: AppSpace.m),
                              const Text('You can keep using the app, just don\'t close it.',
                                  style: TextStyle(color: AppPalette.muted)),
                            ]),
                          ),
                        )
                      : (segs == null || segs.isEmpty)
                          ? Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.subtitles_outlined, size: 48, color: AppPalette.muted),
                                const SizedBox(height: AppSpace.m),
                                Text(segs == null ? 'No transcript yet' : 'No speech was found',
                                    style: t.titleMedium),
                                const SizedBox(height: AppSpace.m),
                                FilledButton.icon(
                                  onPressed: _startTranscribe,
                                  icon: const Icon(Icons.auto_awesome),
                                  label: const Text('Transcribe'),
                                ),
                              ]),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(AppSpace.m),
                              itemCount: segs.length,
                              itemBuilder: (context, i) {
                                final s = segs[i];
                                final current = _pos >= s.start && _pos < s.end;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    _player.seek(s.start);
                                    if (!_playing) _player.play();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: current ? AppPalette.chart.withValues(alpha: 0.10) : null,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      SizedBox(
                                        width: 64,
                                        child: Text(_t(s.start),
                                            style: const TextStyle(color: AppPalette.muted, fontSize: 13)),
                                      ),
                                      Expanded(child: Text(s.text, style: t.bodyLarge)),
                                    ]),
                                  ),
                                );
                              },
                            ),
                ),
              ),
            ]),
    );
  }
}
