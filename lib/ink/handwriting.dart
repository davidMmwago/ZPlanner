import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;

import 'stroke.dart';

/// Result of reading some handwriting.
class HandwritingResult {
  final String text;
  final int lineCount;

  /// Other possible readings (only for a single line of writing).
  final List<String> alternatives;
  const HandwritingResult(this.text, this.lineCount, this.alternatives);
}

/// Handwriting → text, on the tablet (Google ML Kit digital ink).
/// The ~20 MB English model is downloaded once, the first time it's used.
class Handwriting {
  static const lang = 'en-US';
  static final _models = mlkit.DigitalInkRecognizerModelManager();
  static mlkit.DigitalInkRecognizer? _recognizer;

  /// Page units → recogniser units (roughly screen pixels on a tablet page).
  static const _scale = 1000.0;

  static Future<bool> isReady() async {
    try {
      return await _models.isModelDownloaded(lang);
    } catch (_) {
      return false;
    }
  }

  /// Downloads the model if needed. Returns false if that isn't possible.
  static Future<bool> ensureModel() async {
    try {
      if (await _models.isModelDownloaded(lang)) return true;
      return await _models.downloadModel(lang, isWifiRequired: false);
    } catch (_) {
      return false;
    }
  }

  /// Reads the strokes line by line.
  static Future<HandwritingResult> recognize(List<Stroke> strokes) async {
    final rec = _recognizer ??= mlkit.DigitalInkRecognizer(languageCode: lang);
    final lines = _splitIntoLines(strokes);
    final out = <String>[];
    var alternatives = <String>[];

    for (final line in lines) {
      final ink = mlkit.Ink()..strokes = _toMlStrokes(line);

      // Telling the recogniser how big the writing area is helps it tell
      // capitals from lowercase, and the previous words help it guess
      // the next ones.
      final b = _boundsOf(line);
      final prev = out.isEmpty ? '' : out.last;
      final context = mlkit.DigitalInkRecognitionContext(
        preContext: prev.length > 20 ? prev.substring(prev.length - 20) : prev,
        writingArea: mlkit.WritingArea(
          width: b.width * _scale * 1.1 + 40,
          height: b.height * _scale * 1.3 + 20,
        ),
      );

      final candidates = await rec.recognize(ink, context: context);
      if (candidates.isEmpty) continue;
      out.add(candidates.first.text);
      if (lines.length == 1) {
        alternatives = [
          for (final c in candidates.skip(1).take(4))
            if (c.text.trim().isNotEmpty && c.text != candidates.first.text) c.text
        ];
      }
    }
    return HandwritingResult(out.join('\n'), lines.length, alternatives);
  }

  /// Converts strokes to ML Kit's format, using the real pen timing when we
  /// have it, otherwise a natural writing speed.
  static List<mlkit.Stroke> _toMlStrokes(List<Stroke> line) {
    final result = <mlkit.Stroke>[];
    var clock = DateTime.now().millisecondsSinceEpoch - 600000;
    for (final s in line) {
      final pts = <mlkit.StrokePoint>[];
      final times = s.times;
      final start = s.startMs;
      if (times != null && start != null && times.length == s.points.length) {
        // Real timing. Keep strokes in order even if clocks overlap.
        final base = math.max(start, clock + 1);
        for (var i = 0; i < s.points.length; i++) {
          final p = s.points[i];
          pts.add(mlkit.StrokePoint(x: p.dx * _scale, y: p.dy * _scale, t: base + times[i]));
        }
        clock = base + times.last;
      } else {
        // Estimated timing: ~8000 ms per page-width of travel.
        var t = clock + 150; // pen lift
        for (var i = 0; i < s.points.length; i++) {
          if (i > 0) t += math.max(1, ((s.points[i] - s.points[i - 1]).distance * 8000).round());
          final p = s.points[i];
          pts.add(mlkit.StrokePoint(x: p.dx * _scale, y: p.dy * _scale, t: t));
        }
        clock = t;
      }
      result.add(mlkit.Stroke()..points = pts);
    }
    return result;
  }

  static Rect _boundsOf(List<Stroke> strokes) =>
      strokes.skip(1).fold(strokes.first.bounds, (r, s) => r.expandToInclude(s.bounds));

  /// Groups strokes into lines of writing.
  ///
  /// Small marks (dots on i's, crossbars on t's, commas, apostrophes) are
  /// attached to the nearest line instead of starting a line of their own,
  /// which was the main cause of misreads.
  static List<List<Stroke>> _splitIntoLines(List<Stroke> strokes) {
    if (strokes.length <= 1) return [strokes];
    final order = {for (var i = 0; i < strokes.length; i++) strokes[i]: i};

    // Typical letter height = median stroke height.
    final heights = strokes.map((s) => s.bounds.height).toList()..sort();
    final typical = math.max(heights[heights.length ~/ 2], 0.004);

    // One line if the whole selection is barely taller than a letter.
    final all = _boundsOf(strokes);
    if (all.height < typical * 1.9) return [strokes];

    final big = strokes.where((s) => s.bounds.height >= typical * 0.5).toList()
      ..sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));
    final small = strokes.where((s) => s.bounds.height < typical * 0.5).toList();

    // Cluster the real letters into lines by vertical position.
    final lines = <List<Stroke>>[];
    final bands = <(double, double)>[]; // (top, bottom) per line
    for (final s in big) {
      final cy = s.bounds.center.dy;
      if (bands.isNotEmpty) {
        final (top, bottom) = bands.last;
        // Same line if its middle is within the band (with some slack).
        if (cy <= bottom + typical * 0.15 && cy >= top - typical * 0.5) {
          lines.last.add(s);
          bands[bands.length - 1] =
              (math.min(top, s.bounds.top), math.max(bottom, s.bounds.bottom));
          continue;
        }
      }
      lines.add([s]);
      bands.add((s.bounds.top, s.bounds.bottom));
    }
    if (lines.isEmpty) return [strokes];

    // Attach each small mark to the line whose band is closest.
    for (final s in small) {
      final cy = s.bounds.center.dy;
      var best = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < bands.length; i++) {
        final (top, bottom) = bands[i];
        // Marks just above a line (i-dots) belong to that line.
        final d = cy < top ? (top - cy) * 0.7 : (cy > bottom ? cy - bottom : 0.0);
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      lines[best].add(s);
    }

    // Keep the original writing order within each line.
    for (final l in lines) {
      l.sort((a, b) => order[a]!.compareTo(order[b]!));
    }
    return lines;
  }
}
