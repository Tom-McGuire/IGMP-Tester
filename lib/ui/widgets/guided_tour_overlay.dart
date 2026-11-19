import 'dart:async' show FutureOr;
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// A single highlighted step in a [GuidedTourOverlay] walkthrough.
class GuidedTourStep {
  /// The key of the widget to highlight with the spotlight cutout.
  final GlobalKey targetKey;

  /// The heading displayed in the floating walkthrough card.
  final String title;

  /// The body explanation displayed below [title].
  final String description;

  /// Optional callback invoked before measuring [targetKey] for this step.
  final FutureOr<void> Function()? onStepEnter;

  /// Creates a step definition for [GuidedTourOverlay].
  const GuidedTourStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.onStepEnter,
  });
}

/// Interactive spotlight walkthrough overlay that highlights [steps] over [child].
class GuidedTourOverlay extends StatefulWidget {
  /// Ordered list of walkthrough steps to present while [isActive] is `true`.
  final List<GuidedTourStep> steps;

  /// Called when the user finishes or exits the walkthrough.
  final VoidCallback onFinish;

  /// The underlying application UI shown beneath the spotlight backdrop.
  final Widget child;

  /// Whether the spotlight overlay and tooltip card are currently displayed.
  final bool isActive;

  /// Creates a spotlight guided tour overlay wrapping [child].
  const GuidedTourOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
    required this.child,
    required this.isActive,
  });

  @override
  State<GuidedTourOverlay> createState() => _GuidedTourOverlayState();
}

class _GuidedTourOverlayState extends State<GuidedTourOverlay> {
  int _currentIndex = 0;
  int _activationToken = 0;
  Rect? _targetRect;
  Size? _lastScreenSize;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.isActive && widget.steps.isNotEmpty) {
      _activateStep(0, notify: false);
    }
  }

  @override
  void didUpdateWidget(covariant GuidedTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      if (widget.steps.isNotEmpty) {
        _activateStep(0, notify: false);
      }
    } else if (!widget.isActive && oldWidget.isActive) {
      _activationToken++;
      _targetRect = null;
      _currentIndex = 0;
      _lastScreenSize = null;
    } else if (widget.isActive) {
      if (widget.steps.isEmpty) {
        _activationToken++;
        _targetRect = null;
        _currentIndex = 0;
      } else if (_currentIndex >= widget.steps.length) {
        _activateStep(widget.steps.length - 1, notify: false);
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _activateStep(int index, {bool notify = true}) async {
    if (index < 0 || index >= widget.steps.length) return;
    final token = ++_activationToken;

    if (notify && mounted) {
      setState(() {
        _currentIndex = index;
      });
    } else {
      _currentIndex = index;
    }

    final step = widget.steps[index];
    if (step.onStepEnter != null) {
      await step.onStepEnter!();
      if (!mounted || !widget.isActive || token != _activationToken) return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive || token != _activationToken) return;
      _measureTarget();
      _focusNode.requestFocus();
    });
  }

  void _measureTarget() {
    if (!mounted || !widget.isActive || widget.steps.isEmpty) return;
    if (_currentIndex < 0 || _currentIndex >= widget.steps.length) return;

    final step = widget.steps[_currentIndex];
    final targetContext = step.targetKey.currentContext;
    if (targetContext == null) {
      if (_targetRect != null) {
        setState(() => _targetRect = null);
      }
      return;
    }

    final renderBox = targetContext.findRenderObject() as RenderBox?;
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null ||
        !renderBox.hasSize ||
        !renderBox.attached ||
        overlayBox == null ||
        !overlayBox.hasSize ||
        !overlayBox.attached) {
      if (_targetRect != null) {
        setState(() => _targetRect = null);
      }
      return;
    }

    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final nextRect = (topLeft & renderBox.size).inflate(6);
    if (_targetRect != nextRect) {
      setState(() {
        _targetRect = nextRect;
      });
    }
  }

  void _nextStep() {
    if (_currentIndex + 1 < widget.steps.length) {
      _activateStep(_currentIndex + 1);
    } else {
      widget.onFinish();
    }
  }

  void _prevStep() {
    if (_currentIndex > 0) {
      _activateStep(_currentIndex - 1);
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onFinish();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _nextStep();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _prevStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive || widget.steps.isEmpty) {
      return widget.child;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = _TourPalette.fromBrightness(isDark: isDark);

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenSize = Size(
            constraints.maxWidth.isFinite ? constraints.maxWidth : 1280.0,
            constraints.maxHeight.isFinite ? constraints.maxHeight : 800.0,
          );
          if (_lastScreenSize != null && _lastScreenSize != screenSize) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && widget.isActive) {
                _measureTarget();
              }
            });
          }
          _lastScreenSize = screenSize;

          final safeIndex = _currentIndex.clamp(0, widget.steps.length - 1);
          final step = widget.steps[safeIndex];
          final isLast = safeIndex == widget.steps.length - 1;

          return SizedBox(
            width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
            height: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : null,
            child: Stack(
              children: [
                widget.child,
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: CustomPaint(
                      painter: _SpotlightPainter(
                        targetRect: _targetRect,
                        isDark: isDark,
                      ),
                    ),
                  ),
                ),
                _buildTooltipCard(
                  screenSize: screenSize,
                  step: step,
                  stepIndex: safeIndex,
                  isLast: isLast,
                  palette: palette,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  ({double left, double top, double width, double maxHeight})
  _computeCardBounds(Size screenSize) {
    const double preferredCardWidth = 360.0;
    const double estimatedCardHeight = 200.0;
    const double preferredMargin = 16.0;

    final double horizontalMargin = math.min(
      preferredMargin,
      math.max(0.0, (screenSize.width - 120.0) / 2.0),
    );
    final double verticalMargin = math.min(
      preferredMargin,
      math.max(0.0, (screenSize.height - 120.0) / 2.0),
    );

    final double availableWidth = math.max(
      0.0,
      screenSize.width - horizontalMargin * 2,
    );
    final double cardWidth = math.min(preferredCardWidth, availableWidth);
    final double availableHeight = math.max(
      0.0,
      screenSize.height - verticalMargin * 2,
    );
    final double clampedEstimatedHeight = math.min(
      estimatedCardHeight,
      availableHeight,
    );

    final double minLeft = horizontalMargin;
    final double maxLeft = math.max(
      minLeft,
      screenSize.width - cardWidth - horizontalMargin,
    );
    final double minTop = verticalMargin;
    final double maxTop = math.max(
      minTop,
      screenSize.height - clampedEstimatedHeight - verticalMargin,
    );

    double left = ((screenSize.width - cardWidth) / 2).clamp(minLeft, maxLeft);
    double top = ((screenSize.height - clampedEstimatedHeight) / 2).clamp(
      minTop,
      maxTop,
    );

    if (_targetRect != null) {
      final rect = _targetRect!;
      left = rect.left.clamp(minLeft, maxLeft);

      final spaceBelow = screenSize.height - rect.bottom;
      final spaceAbove = rect.top;

      if (spaceBelow >= clampedEstimatedHeight + verticalMargin) {
        top = (rect.bottom + 12).clamp(minTop, maxTop);
      } else if (spaceAbove >= clampedEstimatedHeight + verticalMargin) {
        top = (rect.top - clampedEstimatedHeight - 12).clamp(minTop, maxTop);
      } else {
        const double fallbackComfortHeight = 320.0;
        final double reservedHeight = math.min(
          fallbackComfortHeight,
          availableHeight,
        );
        final double elseMaxTop = math.max(
          minTop,
          screenSize.height - reservedHeight - verticalMargin,
        );
        final double preferredTopOffset = math.min(
          60.0,
          math.max(0.0, availableHeight - reservedHeight),
        );
        top = math
            .max(verticalMargin + preferredTopOffset, rect.top + 24)
            .clamp(minTop, elseMaxTop);
        left = math
            .min(rect.right - cardWidth - 24, maxLeft)
            .clamp(minLeft, maxLeft);
      }
    }

    final double maxHeight = math.max(
      0.0,
      screenSize.height - top - verticalMargin,
    );

    return (left: left, top: top, width: cardWidth, maxHeight: maxHeight);
  }

  Widget _buildTooltipCard({
    required Size screenSize,
    required GuidedTourStep step,
    required int stepIndex,
    required bool isLast,
    required _TourPalette palette,
  }) {
    final bounds = _computeCardBounds(screenSize);

    return Positioned(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: bounds.maxHeight),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.cardBorder, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: palette.badgeBackground,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: palette.badgeBorder),
                          ),
                          child: Text(
                            'DEMO WALKTHROUGH • STEP ${stepIndex + 1} OF ${widget.steps.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: palette.badgeText,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: widget.onFinish,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: palette.closeIcon,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    step.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: palette.title,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step.description,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: palette.body,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: widget.onFinish,
                          style: TextButton.styleFrom(
                            foregroundColor: palette.endDemoText,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'End Demo',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (stepIndex > 0)
                              OutlinedButton(
                                onPressed: _prevStep,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: palette.backText,
                                  side: BorderSide(color: palette.backBorder),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  minimumSize: const Size(0, 30),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Back',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            FilledButton.icon(
                              onPressed: _nextStep,
                              style: FilledButton.styleFrom(
                                backgroundColor: isLast
                                    ? palette.finishAccent
                                    : palette.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                minimumSize: const Size(0, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: Icon(
                                isLast
                                    ? Icons.check_circle_outline
                                    : Icons.arrow_forward,
                                size: 14,
                              ),
                              label: Text(
                                isLast ? 'Finish & Clear' : 'Next',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TourPalette {
  final Color surface;
  final Color cardBorder;
  final Color accent;
  final Color finishAccent;
  final Color title;
  final Color body;
  final Color badgeBackground;
  final Color badgeBorder;
  final Color badgeText;
  final Color closeIcon;
  final Color endDemoText;
  final Color backText;
  final Color backBorder;
  final Color shadow;

  const _TourPalette({
    required this.surface,
    required this.cardBorder,
    required this.accent,
    required this.finishAccent,
    required this.title,
    required this.body,
    required this.badgeBackground,
    required this.badgeBorder,
    required this.badgeText,
    required this.closeIcon,
    required this.endDemoText,
    required this.backText,
    required this.backBorder,
    required this.shadow,
  });

  factory _TourPalette.fromBrightness({required bool isDark}) {
    if (isDark) {
      return _TourPalette(
        surface: const Color(0xFF1E1E1E),
        cardBorder: const Color(0xFF007ACC),
        accent: const Color(0xFF007ACC),
        finishAccent: const Color(0xFF10B981),
        title: const Color(0xFFE0E0E0),
        body: const Color(0xFFD4D4D4),
        badgeBackground: const Color(0xFF007ACC).withValues(alpha: 0.2),
        badgeBorder: const Color(0xFF007ACC).withValues(alpha: 0.5),
        badgeText: const Color(0xFF38BDF8),
        closeIcon: Colors.white54,
        endDemoText: const Color(0xFFF59E0B),
        backText: Colors.white70,
        backBorder: const Color(0xFF3E3E42),
        shadow: Colors.black87,
      );
    }

    return _TourPalette(
      surface: const Color(0xFFFFFFFF),
      cardBorder: const Color(0xFFE5E7EB),
      accent: const Color(0xFF0284C7),
      finishAccent: const Color(0xFF059669),
      title: const Color(0xFF111827),
      body: const Color(0xFF4B5563),
      badgeBackground: const Color(0xFF0284C7).withValues(alpha: 0.1),
      badgeBorder: const Color(0xFF0284C7).withValues(alpha: 0.35),
      badgeText: const Color(0xFF0369A1),
      closeIcon: const Color(0xFF6B7280),
      endDemoText: const Color(0xFFD97706),
      backText: const Color(0xFF374151),
      backBorder: const Color(0xFFD1D5DB),
      shadow: Colors.black.withValues(alpha: 0.18),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final bool isDark;

  _SpotlightPainter({required this.targetRect, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final fullPath = Path()..addRect(Offset.zero & size);
    final dimPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.72 : 0.52)
      ..style = PaintingStyle.fill;

    if (targetRect == null) {
      canvas.drawPath(fullPath, dimPaint);
      return;
    }

    final rrect = RRect.fromRectAndRadius(
      targetRect!,
      const Radius.circular(8),
    );
    final cutoutPath = Path()..addRRect(rrect);
    final combinedPath = Path.combine(
      PathOperation.difference,
      fullPath,
      cutoutPath,
    );

    canvas.drawPath(combinedPath, dimPaint);

    final glowColor = isDark
        ? const Color(0xFF007ACC)
        : const Color(0xFF0284C7);
    final borderColor = isDark
        ? const Color(0xFF38BDF8)
        : const Color(0xFF0284C7);

    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: isDark ? 0.45 : 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(rrect, glowPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect || oldDelegate.isDark != isDark;
}
