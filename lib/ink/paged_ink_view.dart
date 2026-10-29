import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'ink_controller.dart';
import 'ink_layer.dart';

typedef PageBackgroundBuilder = Widget Function(
    BuildContext context, int page, double width, double height);

/// A vertical list of drawable pages, shared by the PDF viewer and notes.
class PagedInkView extends StatefulWidget {
  const PagedInkView({
    super.key,
    required this.controller,
    required this.pageCount,
    required this.aspectOf,
    required this.background,
    this.footer,
    this.topPadding = 80,
  });

  final InkController controller;
  final int pageCount;

  /// height / width of a page
  final double Function(int page) aspectOf;
  final PageBackgroundBuilder background;
  final Widget? footer;
  final double topPadding;

  @override
  State<PagedInkView> createState() => _PagedInkViewState();
}

class _PagedInkViewState extends State<PagedInkView> {
  final _scroll = ScrollController();
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    // Save drawings if the app is minimised or closed.
    _life = AppLifecycleListener(
      onHide: () => widget.controller.saveNow(),
      onPause: () => widget.controller.saveNow(),
    );
  }

  @override
  void dispose() {
    _life.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return LayoutBuilder(builder: (context, cons) {
      final pageWidth = math.min(cons.maxWidth - 32, 1000.0);
      return ListenableBuilder(
        listenable: Listenable.merge([c.penActive, c.fingerMode]),
        builder: (context, _) {
          final fingerDraws = c.fingerMode.value;
          return ScrollConfiguration(
            // Pens never scroll; fingers scroll unless "finger draws" is on.
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: fingerDraws
                  ? {PointerDeviceKind.trackpad}
                  : {PointerDeviceKind.touch, PointerDeviceKind.trackpad},
            ),
            child: Scrollbar(
              controller: _scroll,
              interactive: true,
              thumbVisibility: fingerDraws,
              thickness: fingerDraws ? 16 : null,
              child: ListView.builder(
                controller: _scroll,
                physics: c.penActive.value
                    ? const NeverScrollableScrollPhysics()
                    : null,
                padding: EdgeInsets.fromLTRB(16, widget.topPadding, 16, 48),
                itemCount: widget.pageCount + (widget.footer != null ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == widget.pageCount) return widget.footer!;
                  final h = pageWidth * widget.aspectOf(i);
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                                color: Color(0x1A000000),
                                blurRadius: 12,
                                offset: Offset(0, 3)),
                          ],
                        ),
                        child: InkLayer(
                          controller: c,
                          page: i,
                          width: pageWidth,
                          height: h,
                          background: widget.background(context, i, pageWidth, h),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    });
  }
}
