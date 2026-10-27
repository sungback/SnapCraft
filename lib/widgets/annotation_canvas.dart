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

  const AnnotationCanvas({
    super.key,
    required this.captureItem,
    required this.selectedTool,
    required this.selectedColor,
    required this.strokeWidth,
    required this.onAddAnnotation,
  });

  @override
  State<AnnotationCanvas> createState() => _AnnotationCanvasState();
}

class _AnnotationCanvasState extends State<AnnotationCanvas> {
  AnnotationItem? _activeDraft;

  Offset _toImageCoordinates(Offset localPosition, double scale) {
    final x = (localPosition.dx / scale)
        .clamp(0.0, widget.captureItem.width.toDouble());
    final y = (localPosition.dy / scale)
        .clamp(0.0, widget.captureItem.height.toDouble());
    return Offset(x, y);
  }

  void _handlePanStart(DragStartDetails details, double scale) {
    if (widget.selectedTool == AnnotationTool.text) return;

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
          child: Container(
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
              cursor: widget.selectedTool == AnnotationTool.text
                  ? SystemMouseCursors.text
                  : SystemMouseCursors.precise,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
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
                    ),
                  ),
                ),
              ),
            ),
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

  _CaptureCanvasPainter({
    required this.captureItem,
    required this.activeAnnotation,
    required this.scale,
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

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CaptureCanvasPainter oldDelegate) {
    return true;
  }
}
