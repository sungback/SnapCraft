import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/annotation.dart';
import '../models/capture_item.dart';
import '../services/export_service.dart';

class AnnotationCanvas extends StatefulWidget {
  final CaptureItem captureItem;
  final AnnotationTool selectedTool;
  final Color selectedColor;
  final double strokeWidth;
  final ValueChanged<AnnotationItem> onAddAnnotation;
  final bool isCropping;
  final Rect? cropRect;
  final ValueChanged<Rect?>? onCropRectChanged;
  final VoidCallback? onApplyCrop;
  final VoidCallback? onCancelCrop;

  const AnnotationCanvas({
    super.key,
    required this.captureItem,
    required this.selectedTool,
    required this.selectedColor,
    required this.strokeWidth,
    required this.onAddAnnotation,
    this.isCropping = false,
    this.cropRect,
    this.onCropRectChanged,
    this.onApplyCrop,
    this.onCancelCrop,
  });

  @override
  State<AnnotationCanvas> createState() => _AnnotationCanvasState();
}

class _AnnotationCanvasState extends State<AnnotationCanvas> {
  AnnotationItem? _activeDraft;
  Offset? _cropStartPoint;

  Offset _toImageCoordinates(Offset localPosition, double scale) {
    final x = (localPosition.dx / scale).clamp(
      0.0,
      widget.captureItem.width.toDouble(),
    );
    final y = (localPosition.dy / scale).clamp(
      0.0,
      widget.captureItem.height.toDouble(),
    );
    return Offset(x, y);
  }

  void _handlePanStart(DragStartDetails details, double scale) {
    if (widget.isCropping) {
      final startPt = _toImageCoordinates(details.localPosition, scale);
      _cropStartPoint = startPt;
      widget.onCropRectChanged?.call(Rect.fromPoints(startPt, startPt));
      return;
    }

    if (widget.selectedTool == AnnotationTool.text ||
        widget.selectedTool == AnnotationTool.stepCounter) {
      return;
    }

    final startPt = _toImageCoordinates(details.localPosition, scale);
    final effectiveStroke = widget.strokeWidth / scale.clamp(0.25, 1.5);

    setState(() {
      _activeDraft = AnnotationItem(
        id: 'ann_${DateTime.now().microsecondsSinceEpoch}',
        tool: widget.selectedTool,
        color: widget.selectedColor,
        strokeWidth: effectiveStroke,
        points: [startPt],
      );
    });
  }

  void _handlePanUpdate(DragUpdateDetails details, double scale) {
    if (widget.isCropping) {
      final start = _cropStartPoint;
      if (start == null) return;
      final current = _toImageCoordinates(details.localPosition, scale);
      widget.onCropRectChanged?.call(Rect.fromPoints(start, current));
      return;
    }

    final draft = _activeDraft;
    if (draft == null) return;

    final pt = _toImageCoordinates(details.localPosition, scale);
    setState(() {
      if (draft.tool == AnnotationTool.pen ||
          draft.tool == AnnotationTool.highlighter) {
        _activeDraft = draft.copyWith(points: [...draft.points, pt]);
      } else {
        _activeDraft = draft.copyWith(points: [draft.points.first, pt]);
      }
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (widget.isCropping) {
      _cropStartPoint = null;
      return;
    }

    final draft = _activeDraft;
    if (draft == null) return;

    setState(() {
      _activeDraft = null;
    });

    if (draft.points.isNotEmpty) {
      widget.onAddAnnotation(draft);
    }
  }

  Future<void> _handleTapUp(TapUpDetails details, double scale) async {
    if (widget.isCropping) return;

    if (widget.selectedTool == AnnotationTool.stepCounter) {
      final imagePt = _toImageCoordinates(details.localPosition, scale);
      final effectiveStroke = widget.strokeWidth / scale.clamp(0.25, 1.5);
      final count = widget.captureItem.annotations
          .where((a) => a.tool == AnnotationTool.stepCounter)
          .length;

      widget.onAddAnnotation(
        AnnotationItem(
          id: 'ann_${DateTime.now().microsecondsSinceEpoch}',
          tool: AnnotationTool.stepCounter,
          color: widget.selectedColor,
          strokeWidth: effectiveStroke,
          points: [imagePt],
          text: '${count + 1}',
        ),
      );
      return;
    }

    if (widget.selectedTool != AnnotationTool.text) return;

    final imagePt = _toImageCoordinates(details.localPosition, scale);
    final effectiveStroke = widget.strokeWidth / scale.clamp(0.25, 1.5);

    final controller = TextEditingController();
    final enteredText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222530),
        title: const Text(
          '텍스트 주석 추가',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: '이미지에 표시할 텍스트를 입력하세요',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    // Wait for the dialog route to release its text field before disposal.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (!mounted) return;
    if (enteredText != null && enteredText.trim().isNotEmpty) {
      widget.onAddAnnotation(
        AnnotationItem(
          id: 'ann_${DateTime.now().microsecondsSinceEpoch}',
          tool: AnnotationTool.text,
          color: widget.selectedColor,
          strokeWidth: effectiveStroke,
          points: [imagePt],
          text: enteredText.trim(),
        ),
      );
    }
  }

  MouseCursor _resolveCursor() {
    if (widget.isCropping) {
      return SystemMouseCursors.precise;
    }
    switch (widget.selectedTool) {
      case AnnotationTool.stepCounter:
        return SystemMouseCursors.click;
      case AnnotationTool.text:
        return SystemMouseCursors.text;
      case AnnotationTool.pen:
      case AnnotationTool.highlighter:
      case AnnotationTool.rectangle:
      case AnnotationTool.arrow:
      case AnnotationTool.redaction:
        return SystemMouseCursors.precise;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imgW = widget.captureItem.width.toDouble();
    final imgH = widget.captureItem.height.toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = math.max(100.0, constraints.maxWidth - 40);
        final availH = math.max(100.0, constraints.maxHeight - 40);
        final scale = math.min(availW / imgW, availH / imgH);
        final displayW = imgW * scale;
        final displayH = imgH * scale;

        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: displayW,
                height: displayH,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: MouseRegion(
                  cursor: _resolveCursor(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    onTapUp: (d) => _handleTapUp(d, scale),
                    onPanStart: (d) => _handlePanStart(d, scale),
                    onPanUpdate: (d) => _handlePanUpdate(d, scale),
                    onPanEnd: _handlePanEnd,
                    child: ClipRect(
                      child: CustomPaint(
                        size: Size(displayW, displayH),
                        painter: _CaptureCanvasPainter(
                          captureItem: widget.captureItem,
                          activeAnnotation: _activeDraft,
                          scale: scale,
                          isCropping: widget.isCropping,
                          cropRect: widget.cropRect,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.isCropping)
                Positioned(
                  bottom: 16,
                  child: Material(
                    color: const Color(0xFF1E2028),
                    elevation: 12,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF3B82F6), width: 1.2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.cropRect != null &&
                              widget.cropRect!.width >= 1 &&
                              widget.cropRect!.height >= 1) ...[
                            Text(
                              '${widget.cropRect!.width.round()} x ${widget.cropRect!.height.round()} px',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 14),
                          ] else ...[
                            const Text(
                              '자르고자 하는 영역을 드래그하세요',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(width: 14),
                          ],
                          OutlinedButton.icon(
                            onPressed: widget.onCancelCrop,
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: const Text('취소 (ESC)'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: (widget.cropRect != null &&
                                    widget.cropRect!.width >= 10 &&
                                    widget.cropRect!.height >= 10)
                                ? widget.onApplyCrop
                                : null,
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('자르기 적용 (Enter)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CaptureCanvasPainter extends CustomPainter {
  final CaptureItem captureItem;
  final AnnotationItem? activeAnnotation;
  final double scale;
  final bool isCropping;
  final Rect? cropRect;

  _CaptureCanvasPainter({
    required this.captureItem,
    required this.activeAnnotation,
    required this.scale,
    this.isCropping = false,
    this.cropRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale, scale);

    ExportService.paintCaptureScene(
      canvas: canvas,
      image: captureItem.decodedImage,
      annotations: captureItem.annotations,
      activeAnnotation: activeAnnotation,
    );

    if (isCropping && cropRect != null && !cropRect!.isEmpty) {
      final imageRect = Rect.fromLTWH(
        0,
        0,
        captureItem.width.toDouble(),
        captureItem.height.toDouble(),
      );
      final clamped = cropRect!.intersect(imageRect);
      if (!clamped.isEmpty) {
        // 1. 외곽 어둡게 처리 (Dim overlay)
        final dimPath = Path.combine(
          PathOperation.difference,
          Path()..addRect(imageRect),
          Path()..addRect(clamped),
        );
        canvas.drawPath(
          dimPath,
          Paint()..color = Colors.black.withValues(alpha: 0.65),
        );

        // 2. 크롭 영역 경계선
        final borderPaint = Paint()
          ..color = const Color(0xFF3B82F6)
          ..strokeWidth = 2.0 / scale
          ..style = PaintingStyle.stroke;
        canvas.drawRect(clamped, borderPaint);

        // 3. 네 모서리 L자형 핸들
        final handleLength = 16.0 / scale;
        final handlePaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 3.5 / scale
          ..strokeCap = StrokeCap.square
          ..style = PaintingStyle.stroke;

        // Top-Left
        canvas.drawLine(
          clamped.topLeft,
          clamped.topLeft + Offset(handleLength, 0),
          handlePaint,
        );
        canvas.drawLine(
          clamped.topLeft,
          clamped.topLeft + Offset(0, handleLength),
          handlePaint,
        );
        // Top-Right
        canvas.drawLine(
          clamped.topRight,
          clamped.topRight - Offset(handleLength, 0),
          handlePaint,
        );
        canvas.drawLine(
          clamped.topRight,
          clamped.topRight + Offset(0, handleLength),
          handlePaint,
        );
        // Bottom-Left
        canvas.drawLine(
          clamped.bottomLeft,
          clamped.bottomLeft + Offset(handleLength, 0),
          handlePaint,
        );
        canvas.drawLine(
          clamped.bottomLeft,
          clamped.bottomLeft - Offset(0, handleLength),
          handlePaint,
        );
        // Bottom-Right
        canvas.drawLine(
          clamped.bottomRight,
          clamped.bottomRight - Offset(handleLength, 0),
          handlePaint,
        );
        canvas.drawLine(
          clamped.bottomRight,
          clamped.bottomRight - Offset(0, handleLength),
          handlePaint,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CaptureCanvasPainter oldDelegate) {
    return true;
  }
}
