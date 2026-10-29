import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/format.dart';
import 'recording_controller.dart';

/// Mic button for app bars. While recording it shows a red timer pill with
/// pause and stop.
class RecordButton extends StatelessWidget {
  const RecordButton({super.key, required this.moduleId});
  final int moduleId;

  @override
  Widget build(BuildContext context) {
    final r = RecordingController.instance;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) {
        if (!r.recording) {
          return IconButton(
            tooltip: 'Record audio',
            icon: const Icon(Icons.mic_none),
            onPressed: () async {
              final ok = await r.start(moduleId);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Microphone permission is needed to record.')));
              }
            },
          );
        }
        final e = r.elapsed;
        final time = e.inHours > 0
            ? '${e.inHours}:${two(e.inMinutes % 60)}:${two(e.inSeconds % 60)}'
            : '${two(e.inMinutes)}:${two(e.inSeconds % 60)}';
        return Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            color: AppPalette.moneyOut.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.fiber_manual_record,
                size: 14, color: r.paused ? AppPalette.muted : AppPalette.moneyOut),
            const SizedBox(width: 6),
            Text(time,
                style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w600)),
            IconButton(
              tooltip: r.paused ? 'Resume recording' : 'Pause recording',
              icon: Icon(r.paused ? Icons.play_arrow : Icons.pause),
              onPressed: r.paused ? r.resume : r.pause,
            ),
            IconButton(
              tooltip: 'Stop and save',
              icon: const Icon(Icons.stop),
              onPressed: () async {
                final item = await r.stop();
                if (item != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Saved "${item.title}" to the module.')));
                }
              },
            ),
          ]),
        );
      },
    );
  }
}
