import 'dart:math' as math;
import 'dart:ui';

/// 마크업 편집 도구 종류
enum AnnotationTool {
  select('선택', '주석 선택·이동·삭제'),
  pen('펜', '자유 곡선 그리기'),
  highlighter('형광펜', '반투명 형광펜 강조'),
  rectangle('사각형', '사각형 테두리 박스'),
  arrow('화살표', '방향 지시 화살표'),
  text('텍스트', '클릭한 위치에 텍스트 삽입'),
  stepCounter('번호', '클릭한 위치에 순차적 번호(①, ②, ③) 스탬프 삽입'),
  redaction('보안 가림', '드래그한 영역을 불투명 검정색으로 가리고 자동 복사 (색상·굵기 무관)');

  final String label;
  final String tooltip;
  const AnnotationTool(this.label, this.tooltip);
}

/// 단일 마크업(주석) 요소 데이터 모델
/// 모든 좌표(points)는 원본 이미지 픽셀 좌표계(0..imageWidth, 0..imageHeight)로 저장됩니다.
class AnnotationItem {
  final String id;
  final AnnotationTool tool;
  final Color color;
  final double strokeWidth;
  final List<Offset> points;
  final String? text;

  const AnnotationItem({
    required this.id,
    required this.tool,
    required this.color,
    required this.strokeWidth,
    required this.points,
    this.text,
  });

  AnnotationItem copyWith({
    String? id,
    AnnotationTool? tool,
    Color? color,
    double? strokeWidth,
    List<Offset>? points,
    String? text,
  }) {
    return AnnotationItem(
      id: id ?? this.id,
      tool: tool ?? this.tool,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      points: points ?? this.points,
      text: text ?? this.text,
    );
  }

  /// 모든 좌표를 지정된 오프셋만큼 이동한 복사본을 반환합니다.
  AnnotationItem translated(Offset delta) {
    return copyWith(
      points: points.map((pt) => pt + delta).toList(growable: false),
    );
  }

  /// 사각형/보안 가림용 시작점~끝점 Rect 반환
  Rect get boundingRect {
    if (points.isEmpty) return Rect.zero;
    if (points.length == 1) {
      return Rect.fromPoints(points.first, points.first);
    }
    return Rect.fromPoints(points.first, points.last);
  }

  /// 선택 하이라이트 및 히트 테스트용 바운딩 박스(원본 이미지 좌표계)
  Rect get hitBounds {
    if (points.isEmpty) return Rect.zero;

    switch (tool) {
      case AnnotationTool.stepCounter:
        final radius = (strokeWidth * 2.6).clamp(14.0, 32.0);
        return Rect.fromCircle(center: points.first, radius: radius + 6);
      case AnnotationTool.text:
        final origin = points.first;
        final fontSize = (strokeWidth * 3.8).clamp(16.0, 44.0);
        final lines = (text ?? '').split('\n');
        final maxChars = lines.fold<int>(
          1,
          (m, line) => math.max(m, line.length),
        );
        final width = math.max(60.0, maxChars * fontSize * 0.65) + 16;
        final height = math.max(1, lines.length) * fontSize * 1.3 + 16;
        return Rect.fromLTWH(origin.dx - 8, origin.dy - 8, width, height);
      case AnnotationTool.rectangle:
      case AnnotationTool.redaction:
        return boundingRect.inflate(strokeWidth / 2 + 8);
      case AnnotationTool.select:
      case AnnotationTool.pen:
      case AnnotationTool.highlighter:
      case AnnotationTool.arrow:
        var minX = points.first.dx;
        var minY = points.first.dy;
        var maxX = points.first.dx;
        var maxY = points.first.dy;
        for (final pt in points) {
          minX = math.min(minX, pt.dx);
          minY = math.min(minY, pt.dy);
          maxX = math.max(maxX, pt.dx);
          maxY = math.max(maxY, pt.dy);
        }
        final pad = (tool == AnnotationTool.highlighter
                ? strokeWidth * 1.6
                : strokeWidth / 2) +
            8;
        return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(pad);
    }
  }

  /// 지정된 이미지 좌표가 이 주석을 선택하는 범위 안에 있는지 판별합니다.
  bool hitTest(Offset imagePoint, {double tolerance = 14.0}) {
    if (points.isEmpty) return false;

    switch (tool) {
      case AnnotationTool.select:
        return false;
      case AnnotationTool.stepCounter:
        final radius = (strokeWidth * 2.6).clamp(14.0, 32.0);
        return (imagePoint - points.first).distance <= radius + tolerance;
      case AnnotationTool.text:
        return hitBounds.inflate(tolerance).contains(imagePoint);
      case AnnotationTool.rectangle:
      case AnnotationTool.redaction:
        return boundingRect.inflate(tolerance).contains(imagePoint);
      case AnnotationTool.arrow:
        if (points.length == 1) {
          return (imagePoint - points.first).distance <= tolerance;
        }
        return _distanceToSegment(imagePoint, points.first, points.last) <=
            tolerance + strokeWidth;
      case AnnotationTool.pen:
      case AnnotationTool.highlighter:
        final threshold = tolerance +
            (tool == AnnotationTool.highlighter
                ? strokeWidth * 1.6
                : strokeWidth / 2);
        if (points.length == 1) {
          return (imagePoint - points.first).distance <= threshold;
        }
        for (var i = 1; i < points.length; i++) {
          if (_distanceToSegment(imagePoint, points[i - 1], points[i]) <=
              threshold) {
            return true;
          }
        }
        return false;
    }
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq)
        .clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - proj).distance;
  }
}
