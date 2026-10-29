import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/app_files.dart';
import '../data/db.dart';
import '../theme/app_theme.dart';
import 'stroke.dart';

class _InkAction {
  final int page;
  final List<Stroke> added;
  final List<Stroke> removed;
  final List<InkText> addedText;
  final List<InkText> removedText;
  _InkAction(
    this.page, {
    this.added = const [],
    this.removed = const [],
    this.addedText = const [],
    this.removedText = const [],
  });
}

/// Strokes picked with the lasso.
class InkSelection {
  final int page;
  final List<Stroke> strokes;
  final Rect bounds; // page units
  const InkSelection(this.page, this.strokes, this.bounds);
}

/// Holds all drawings for one document/note, the current tool,
/// undo/redo, selection, and autosaves to disk.
class InkController extends ChangeNotifier {
  final int itemId;
  InkController._(this.itemId);

  final Map<int, List<Stroke>> _pages = {};
  final Map<int, List<InkText>> _texts = {};
  final Map<int, ValueNotifier<int>> _revs = {};
  final List<_InkAction> _undo = [];
  final List<_InkAction> _redo = [];

  // ── Tool state ─────────────────────────────────────────────
  InkTool tool = InkTool.pen;
  Color penColor = AppPalette.penColors.first;
  Color highlighterColor = AppPalette.highlighterColors.first;
  double penWidth = 0.0028; // fraction of page width
  double highlighterWidth = 0.02;
  double eraserRadius = 0.012;

  /// Lets a finger draw (handy for testing without a pen).
  final ValueNotifier<bool> fingerMode = ValueNotifier(false);
  bool get fingerDraws => fingerMode.value;

  /// True while the pen is touching the page — used to lock scrolling so
  /// a resting palm doesn't scroll the page mid-stroke.
  final ValueNotifier<bool> penActive = ValueNotifier(false);

  /// Palm filter for finger mode: touches with a contact radius bigger than
  /// this (logical px) are treated as a palm and ignored. 0 = off.
  double palmRadius = 14;

  /// Hidden diagnostic (long-press the hand icon).
  final ValueNotifier<bool> showPointerInfo = ValueNotifier(false);
  final ValueNotifier<String> pointerInfo = ValueNotifier('Touch the page…');

  /// Current lasso selection (null = nothing selected).
  final ValueNotifier<InkSelection?> selection = ValueNotifier(null);

  static const penWidths = [0.0018, 0.0028, 0.0045];
  static const highlighterWidths = [0.012, 0.02, 0.03];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void setTool(InkTool t) {
    tool = t;
    if (t != InkTool.select) clearSelection();
    notifyListeners();
  }

  void setColor(Color c) {
    if (tool == InkTool.highlighter) {
      highlighterColor = c;
    } else {
      penColor = c;
      if (tool == InkTool.eraser || tool == InkTool.select) tool = InkTool.pen;
      clearSelection();
    }
    notifyListeners();
  }

  void setWidth(double w) {
    if (tool == InkTool.highlighter) {
      highlighterWidth = w;
    } else {
      penWidth = w;
    }
    notifyListeners();
  }

  void toggleFingerDraws() {
    fingerMode.value = !fingerMode.value;
    notifyListeners();
  }

  // ── Strokes + text ─────────────────────────────────────────
  List<Stroke> strokes(int page) => _pages[page] ?? const [];
  List<InkText> texts(int page) => _texts[page] ?? const [];

  /// Repaint signal for a single page (so only that page redraws).
  ValueNotifier<int> rev(int page) => _revs.putIfAbsent(page, () => ValueNotifier(0));

  Stroke newStroke(List<Offset> points, {int? startMs, List<int>? times}) {
    final hl = tool == InkTool.highlighter;
    return Stroke(
      startMs: startMs,
      times: times,
      tool: hl ? InkTool.highlighter : InkTool.pen,
      color: hl
          ? highlighterColor.withValues(alpha: 0.38).toARGB32()
          : penColor.toARGB32(),
      width: hl ? highlighterWidth : penWidth,
      points: points,
    );
  }

  void addStroke(int page, Stroke s) {
    (_pages[page] ??= []).add(s);
    _record(_InkAction(page, added: [s]));
  }

  /// Removes strokes and text boxes under [p]. Returns what was removed so the
  /// caller can group a whole eraser drag into one undo step ([commitErase]).
  (List<Stroke>, List<InkText>) eraseAt(int page, Offset p) {
    final list = _pages[page];
    final hit = list == null
        ? const <Stroke>[]
        : list.where((s) => s.hitTest(p, eraserRadius)).toList();
    final tlist = _texts[page];
    final thit = tlist == null
        ? const <InkText>[]
        : tlist.where((t) => t.bounds.inflate(eraserRadius).contains(p)).toList();
    if (hit.isEmpty && thit.isEmpty) return (const [], const []);
    list?.removeWhere(hit.contains);
    tlist?.removeWhere(thit.contains);
    rev(page).value++;
    return (hit, thit);
  }

  void commitErase(int page, List<Stroke> removed, List<InkText> removedText) {
    if (removed.isEmpty && removedText.isEmpty) return;
    _record(_InkAction(page, removed: removed, removedText: removedText));
  }

  // ── Lasso selection ────────────────────────────────────────
  /// Selects strokes that are mostly inside the lasso polygon (page units).
  void selectWithLasso(int page, List<Offset> lasso) {
    if (lasso.length < 3) {
      clearSelection();
      return;
    }
    final path = ui.Path()..addPolygon(lasso, true);
    final picked = <Stroke>[];
    for (final s in strokes(page)) {
      if (s.points.isEmpty) continue;
      var inside = 0;
      for (final pt in s.points) {
        if (path.contains(pt)) inside++;
      }
      if (inside / s.points.length >= 0.6) picked.add(s);
    }
    if (picked.isEmpty) {
      clearSelection();
      return;
    }
    var b = picked.first.bounds;
    for (final s in picked.skip(1)) {
      b = b.expandToInclude(s.bounds);
    }
    selection.value = InkSelection(page, picked, b);
    rev(page).value++;
  }

  void clearSelection() {
    final s = selection.value;
    if (s == null) return;
    selection.value = null;
    rev(s.page).value++;
  }

  void deleteSelection() {
    final s = selection.value;
    if (s == null) return;
    _pages[s.page]?.removeWhere(s.strokes.contains);
    selection.value = null;
    _record(_InkAction(s.page, removed: s.strokes));
  }

  /// Swaps the selected handwriting for typed [text] in the same spot.
  void replaceSelectionWithText(String text, {required int lineCount}) {
    final s = selection.value;
    if (s == null || text.trim().isEmpty) return;
    final lineH = s.bounds.height / (lineCount < 1 ? 1 : lineCount);
    final box = InkText(
      pos: s.bounds.topLeft,
      width: s.bounds.width.clamp(0.15, 0.95).toDouble(),
      text: text.trim(),
      fontSize: (lineH * 0.55).clamp(0.014, 0.04).toDouble(),
      color: AppPalette.penColors.first.toARGB32(),
    );
    _pages[s.page]?.removeWhere(s.strokes.contains);
    (_texts[s.page] ??= []).add(box);
    selection.value = null;
    _record(_InkAction(s.page, removed: s.strokes, addedText: [box]));
  }

  // ── Undo / redo ────────────────────────────────────────────
  void _record(_InkAction a) {
    _undo.add(a);
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
    _changed(a.page);
  }

  void undo() {
    if (_undo.isEmpty) return;
    clearSelection();
    final a = _undo.removeLast();
    final list = _pages[a.page] ??= [];
    list.removeWhere(a.added.contains);
    list.addAll(a.removed);
    final tl = _texts[a.page] ??= [];
    tl.removeWhere(a.addedText.contains);
    tl.addAll(a.removedText);
    _redo.add(a);
    _changed(a.page);
  }

  void redo() {
    if (_redo.isEmpty) return;
    clearSelection();
    final a = _redo.removeLast();
    final list = _pages[a.page] ??= [];
    list.removeWhere(a.removed.contains);
    list.addAll(a.added);
    final tl = _texts[a.page] ??= [];
    tl.removeWhere(a.removedText.contains);
    tl.addAll(a.addedText);
    _undo.add(a);
    _changed(a.page);
  }

  void _changed(int page) {
    rev(page).value++;
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), saveNow);
    notifyListeners();
  }

  // ── Saving / loading ───────────────────────────────────────
  bool _dirty = false;
  Timer? _saveTimer;

  /// Saves still being written, per item. Loading waits for these so a
  /// document closed and reopened quickly never shows stale drawings.
  static final Map<int, Future<void>> _pendingSaves = {};

  static Future<InkController> load(int itemId) async {
    final pending = _pendingSaves[itemId];
    if (pending != null) await pending;
    final c = InkController._(itemId);
    final f = AppFiles.inkFile(itemId);
    if (await f.exists()) {
      try {
        final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final pages = (data['pages'] as Map<String, dynamic>?) ?? {};
        pages.forEach((k, v) {
          c._pages[int.parse(k)] = [
            for (final s in v as List) Stroke.fromJson(s as Map<String, dynamic>)
          ];
        });
        final texts = (data['texts'] as Map<String, dynamic>?) ?? {};
        texts.forEach((k, v) {
          c._texts[int.parse(k)] = [
            for (final t in v as List) InkText.fromJson(t as Map<String, dynamic>)
          ];
        });
      } catch (e) {
        debugPrint('Could not read ink for $itemId: $e');
      }
    }
    return c;
  }

  Future<void> saveNow() {
    _saveTimer?.cancel();
    if (!_dirty) return _pendingSaves[itemId] ?? Future.value();
    _dirty = false;
    final data = {
      'v': 2,
      'pages': {
        for (final e in _pages.entries)
          if (e.value.isNotEmpty) '${e.key}': [for (final s in e.value) s.toJson()]
      },
      'texts': {
        for (final e in _texts.entries)
          if (e.value.isNotEmpty) '${e.key}': [for (final t in e.value) t.toJson()]
      },
    };
    final previous = _pendingSaves[itemId] ?? Future.value();
    final job = previous.then((_) async {
      // Write to a temp file then rename, so a crash never corrupts drawings.
      final f = AppFiles.inkFile(itemId);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(f.path);
      await AppDb.instance.touchItem(itemId);
    });
    _pendingSaves[itemId] = job;
    job.whenComplete(() {
      if (identical(_pendingSaves[itemId], job)) _pendingSaves.remove(itemId);
    });
    return job;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final r in _revs.values) {
      r.dispose();
    }
    penActive.dispose();
    fingerMode.dispose();
    showPointerInfo.dispose();
    pointerInfo.dispose();
    selection.dispose();
    super.dispose();
  }
}
