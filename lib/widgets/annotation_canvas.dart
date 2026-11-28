import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/annotation.dart';
import '../models/capture_item.dart';
import '../services/export_service.dart';

class AnnotationCanvas extends StatefulWidget {
  final CaptureItem captureItem;
  final AnnotationTool selectedTool;
  final Color selectedColor;
  final double strokeWidth;
  final ValueChanged<AnnotationItem> onAddAnnotation;
  final String? selectedAnnotationId;
  final ValueChanged<String?>? onSelectAnnotation;
  final ValueChanged<AnnotationItem>? onUpdateAnnotation;
  final ValueChanged<String>? onDeleteAnnotation;
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
    this.selectedAnnotationId,
    this.onSelectAnnotation,
    this.onUpdateAnnotation,
    this.onDeleteAnnotation,
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
  static const double _minZoom = 0.5;
  static const double _maxZoom = 5.0;

  AnnotationItem? _activeDraft;
  AnnotationItem? _draggingAnnotationOriginal;
  AnnotationItem? _draggingAnnotationPreview;
  Offset? _dragStartImagePoint;
  bool _isPanningCanvas = false;
  Offset? _cropStartPoint;

  double _zoom = 1.0;
  Offset _panOffset = Offset.zero;

  @override
  void didUpdateWidget(covariant AnnotationCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.captureItem.id != widget.captureItem.id) {
      _zoom = 1.0;
      _panOffset = Offset.zero;
      _activeDraft = null;
      _draggingAnnotationOriginal = null;
      _draggingAnnotationPreview = null;
      _dragStartImagePoint = null;
      _isPanningCanvas = false;
      _cropStartPoint = null;
    }
  }

  double _baseScaleFor(BoxConstraints constraints) {
    final availW = math.max(100.0, constraints.maxWidth - 40);
    final availH = math.max(100.0, constraints.maxHeight - 40);
    return math.min(
      availW / widget.captureItem.width,
      availH / widget.captureItem.height,
    );
  }

  Offset _imageOriginInViewport(BoxConstraints constraints, double scale) {
    final scaledW = widget.captureItem.width * scale;
    final scaledH = widget.captureItem.height * scale;
    return Offset(
      (constraints.maxWidth - scaledW) / 2 + _panOffset.dx,
      (constraints.maxHeight - scaledH) / 2 + _panOffset.dy,
    );
  }

  Offset _clampPan(
    Offset pan,
    BoxConstraints constraints,
    double scale,
  ) {
    final scaledW = widget.captureItem.width * scale;
    final scaledH = widget.captureItem.height * scale;
    final maxPanX = math.max(0.0, scaledW * 0.5 + constraints.maxWidth * 0.25);
    final maxPanY = math.max(0.0, scaledH * 0.5 + constraints.maxHeight * 0.25);
    return Offset(
      pan.dx.clamp(-maxPanX, maxPanX),
      pan.dy.clamp(-maxPanY, maxPanY),
    );
  }

  void _setZoom(
    double nextZoom,
    BoxConstraints constraints, {
    Offset? focalViewportPoint,
  }) {
    final clampedZoom = nextZoom.clamp(_minZoom, _maxZoom);
    if ((clampedZoom - _zoom).abs() < 0.001) return;

    final baseScale = _baseScaleFor(constraints);
    final oldScale = baseScale * _zoom;
    final newScale = baseScale * clampedZoom;

    var nextPan = _panOffset;
    if (focalViewportPoint != null) {
      final oldOrigin = _imageOriginInViewport(constraints, oldScale);
      final imagePt = (focalViewportPoint - oldOrigin) / oldScale;
      final newCenterOrigin = Offset(
        (constraints.maxWidth - widget.captureItem.width * newScale) / 2,
        (constraints.maxHeight - widget.captureItem.height * newScale) / 2,
      );
      nextPan = focalViewportPoint - newCenterOrigin - imagePt * newScale;
    }

    setState(() {
      _zoom = clampedZoom;
      _panOffset = _clampPan(nextPan, constraints, newScale);
    });
  }

  void _resetZoom() {
    setState(() {
      _zoom = 1.0;
      _panOffset = Offset.zero;
    });
  }

  Offset _toImageCoordinates(
    Offset localPosition,
    Offset imageOrigin,
    double scale,
  ) {
    final x = ((localPosition.dx - imageOrigin.dx) / scale).clamp(
      0.0,
      widget.captureItem.width.toDouble(),
    );
    final y = ((localPosition.dy - imageOrigin.dy) / scale).clamp(
      0.0,
      widget.captureItem.height.toDouble(),
    );
    return Offset(x, y);
  }

  AnnotationItem? _hitTestTopAnnotation(Offset imagePoint, double scale) {
    final tolerance = 14.0 / scale.clamp(0.3, 2.0);
    final list = widget.captureItem.annotations;
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].hitTest(imagePoint, tolerance: tolerance)) {
        return list[i];
      }
    }
    return null;
  }

  void _handlePanStart(
    DragStartDetails details,
    Offset imageOrigin,
    double scale,
  ) {
    if (widget.isCropping) {
      final startPt = _toImageCoordinates(
        details.localPosition,
        imageOrigin,
        scale,
      );
      _cropStartPoint = startPt;
      widget.onCropRectChanged?.call(Rect.fromPoints(startPt, startPt));
      return;
    }

    if (widget.selectedTool == AnnotationTool.select) {
      final startPt = _toImageCoordinates(
        details.localPosition,
        imageOrigin,
        scale,
      );
      final hit = _hitTestTopAnnotation(startPt, scale);
      if (hit != null) {
        widget.onSelectAnnotation?.call(hit.id);
        setState(() {
          _draggingAnnotationOriginal = hit;
          _draggingAnnotationPreview = hit;
          _dragStartImagePoint = startPt;
          _isPanningCanvas = false;
        });
      } else {
        widget.onSelectAnnotation?.call(null);
        setState(() {
          _draggingAnnotationOriginal = null;
          _draggingAnnotationPreview = null;
          _dragStartImagePoint = null;
          _isPanningCanvas = true;
        });
      }
      return;
    }

    if (widget.selectedTool == AnnotationTool.text ||
        widget.selectedTool == AnnotationTool.stepCounter) {
      return;
    }

    final startPt = _toImageCoordinates(
      details.localPosition,
      imageOrigin,
      scale,
    );
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

  void _handlePanUpdate(
    DragUpdateDetails details,
    Offset imageOrigin,
    double scale,
    BoxConstraints constraints,
  ) {
    if (widget.isCropping) {
      final start = _cropStartPoint;
      if (start == null) return;
      final current = _toImageCoordinates(
        details.localPosition,
        imageOrigin,
        scale,
      );
      widget.onCropRectChanged?.call(Rect.fromPoints(start, current));
      return;
    }

    if (widget.selectedTool == AnnotationTool.select) {
      if (_draggingAnnotationOriginal != null && _dragStartImagePoint != null) {
        final current = _toImageCoordinates(
          details.localPosition,
          imageOrigin,
          scale,
        );
        final delta = current - _dragStartImagePoint!;
        setState(() {
          _draggingAnnotationPreview = _draggingAnnotationOriginal!.translated(
            delta,
          );
        });
      } else if (_isPanningCanvas) {
        setState(() {
          _panOffset = _clampPan(
            _panOffset + details.delta,
            constraints,
            scale,
          );
        });
      }
      return;
    }

    final draft = _activeDraft;
    if (draft == null) return;

    final pt = _toImageCoordinates(details.localPosition, imageOrigin, scale);
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

    if (widget.selectedTool == AnnotationTool.select) {
      final preview = _draggingAnnotationPreview;
      final original = _draggingAnnotationOriginal;
      setState(() {
        _draggingAnnotationOriginal = null;
        _draggingAnnotationPreview = null;
        _dragStartImagePoint = null;
        _isPanningCanvas = false;
      });
      if (preview != null && original != null) {
        widget.onUpdateAnnotation?.call(preview);
      }
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

  Future<void> _handleTapUp(
    TapUpDetails details,
    Offset imageOrigin,
    double scale,
  ) async {
    if (widget.isCropping) return;

    if (widget.selectedTool == AnnotationTool.select) {
      final imagePt = _toImageCoordinates(
        details.localPosition,
        imageOrigin,
        scale,
      );
      final hit = _hitTestTopAnnotation(imagePt, scale);
      widget.onSelectAnnotation?.call(hit?.id);
      return;
    }

    if (widget.selectedTool == AnnotationTool.stepCounter) {
      final imagePt = _toImageCoordinates(
        details.localPosition,
        imageOrigin,
        scale,
      );
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

    final imagePt = _toImageCoordinates(
      details.localPosition,
      imageOrigin,
      scale,
    );
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
      case AnnotationTool.select:
        return _draggingAnnotationPreview != null
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseScale = _baseScaleFor(constraints);
        final scale = baseScale * _zoom;
        final imageOrigin = _imageOriginInViewport(constraints, scale);

        return Stack(
          children: [
            Listener(
              onPointerSignal: (event) {
                if (event is! PointerScrollEvent) return;
                final keys = HardwareKeyboard.instance;
                if (keys.isControlPressed || keys.isMetaPressed) {
                  final factor = event.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12;
                  _setZoom(
                    _zoom * factor,
                    constraints,
                    focalViewportPoint: event.localPosition,
                  );
                } else if (_zoom > 1.0) {
                  setState(() {
                    _panOffset = _clampPan(
                      _panOffset - event.scrollDelta,
                      constraints,
                      scale,
                    );
                  });
                }
              },
              child: MouseRegion(
                cursor: _resolveCursor(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  onTapUp: (d) => _handleTapUp(d, imageOrigin, scale),
                  onPanStart: (d) => _handlePanStart(d, imageOrigin, scale),
                  onPanUpdate: (d) =>
                      _handlePanUpdate(d, imageOrigin, scale, constraints),
                  onPanEnd: _handlePanEnd,
                  child: ClipRect(
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: _CaptureCanvasPainter(
                        captureItem: widget.captureItem,
                        activeAnnotation: _activeDraft,
                        draggingPreview: _draggingAnnotationPreview,
                        selectedAnnotationId: widget.selectedAnnotationId,
                        imageOrigin: imageOrigin,
                        scale: scale,
                        isCropping: widget.isCropping,
                        cropRect: widget.cropRect,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!widget.isCropping)
              Positioned(
                right: 16,
                bottom: 16,
                child: _buildZoomControls(constraints),
              ),
            if (widget.isCropping)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(child: _buildCropBar()),
              ),
          ],
        );
      },
    );
  }

  Widget _buildZoomControls(BoxConstraints constraints) {
    final hasSelected =
        widget.selectedTool == AnnotationTool.select &&
        widget.selectedAnnotationId != null &&
        widget.onDeleteAnnotation != null;

    return Material(
      color: const Color(0xFF1E2028).withValues(alpha: 0.92),
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF323646)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasSelected) ...[
              _buildZoomControlButton(
                tooltip: '선택한 주석 삭제 (Delete)',
                onTap: () =>
                    widget.onDeleteAnnotation?.call(widget.selectedAnnotationId!),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                  color: Colors.redAccent,
                ),
              ),
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: const Color(0xFF323646),
              ),
            ],
            _buildZoomControlButton(
              tooltip: '축소',
              onTap: _zoom > _minZoom
                  ? () => _setZoom(_zoom / 1.25, constraints)
                  : null,
              child: Icon(
                Icons.zoom_out_rounded,
                size: 17,
                color: _zoom > _minZoom ? Colors.white70 : Colors.white24,
              ),
            ),
            _buildZoomControlButton(
              tooltip: '100%로 초기화',
              onTap: _resetZoom,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '${(_zoom * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            _buildZoomControlButton(
              tooltip: '확대',
              onTap: _zoom < _maxZoom
                  ? () => _setZoom(_zoom * 1.25, constraints)
                  : null,
              child: Icon(
                Icons.zoom_in_rounded,
                size: 17,
                color: _zoom < _maxZoom ? Colors.white70 : Colors.white24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Uses Listener instead of GestureDetector/IconButton so canvas drag tests
  // find a single drawing GestureDetector under AnnotationCanvas.
  Widget _buildZoomControlButton({
    required String tooltip,
    required VoidCallback? onTap,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(6),
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: onTap == null ? null : (_) => onTap(),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }

  Widget _buildCropBar() {
    return Material(
      color: const Color(0xFF1E2028),
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
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
    );
  }
}

class _CaptureCanvasPainter extends CustomPainter {
  final CaptureItem captureItem;
  final AnnotationItem? activeAnnotation;
  final AnnotationItem? draggingPreview;
  final String? selectedAnnotationId;
  final Offset imageOrigin;
  final double scale;
  final bool isCropping;
  final Rect? cropRect;

  _CaptureCanvasPainter({
    required this.captureItem,
    required this.activeAnnotation,
    required this.draggingPreview,
    required this.selectedAnnotationId,
    required this.imageOrigin,
    required this.scale,
    this.isCropping = false,
    this.cropRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaledRect = Rect.fromLTWH(
      imageOrigin.dx,
      imageOrigin.dy,
      captureItem.width * scale,
      captureItem.height * scale,
    );

    canvas.drawRect(
      scaledRect.shift(const Offset(0, 8)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    canvas.save();
    canvas.translate(imageOrigin.dx, imageOrigin.dy);
    canvas.scale(scale, scale);

    final renderedAnnotations = draggingPreview == null
        ? captureItem.annotations
        : captureItem.annotations
              .map((a) => a.id == draggingPreview!.id ? draggingPreview! : a)
              .toList(growable: false);

    ExportService.paintCaptureScene(
      canvas: canvas,
      image: captureItem.decodedImage,
      annotations: renderedAnnotations,
      activeAnnotation: activeAnnotation,
    );

    if (!isCropping && selectedAnnotationId != null) {
      AnnotationItem? selected;
      for (final a in renderedAnnotations) {
        if (a.id == selectedAnnotationId) {
          selected = a;
          break;
        }
      }
      if (selected != null) {
        final bounds = selected.hitBounds;
        final selectPaint = Paint()
          ..color = const Color(0xFF3B82F6)
          ..strokeWidth = 2.0 / scale
          ..style = PaintingStyle.stroke;
        canvas.drawRect(bounds, selectPaint);

        final handleSize = 6.0 / scale;
        final handlePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        for (final corner in [
          bounds.topLeft,
          bounds.topRight,
          bounds.bottomLeft,
          bounds.bottomRight,
        ]) {
          final handleRect = Rect.fromCenter(
            center: corner,
            width: handleSize,
            height: handleSize,
          );
          canvas.drawRect(handleRect, handlePaint);
          canvas.drawRect(handleRect, selectPaint);
        }
      }
    }

    if (isCropping && cropRect != null && !cropRect!.isEmpty) {
      final imageRect = Rect.fromLTWH(
        0,
        0,
        captureItem.width.toDouble(),
        captureItem.height.toDouble(),
      );
      final clamped = cropRect!.intersect(imageRect);
      if (!clamped.isEmpty) {
        final dimPath = Path.combine(
          PathOperation.difference,
          Path()..addRect(imageRect),
          Path()..addRect(clamped),
        );
        canvas.drawPath(
          dimPath,
          Paint()..color = Colors.black.withValues(alpha: 0.65),
        );

        final borderPaint = Paint()
          ..color = const Color(0xFF3B82F6)
          ..strokeWidth = 2.0 / scale
          ..style = PaintingStyle.stroke;
        canvas.drawRect(clamped, borderPaint);

        final handleLength = 16.0 / scale;
        final handlePaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 3.5 / scale
          ..strokeCap = StrokeCap.square
          ..style = PaintingStyle.stroke;

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

    canvas.drawRect(
      scaledRect,
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _CaptureCanvasPainter oldDelegate) {
    return true;
  }
}
