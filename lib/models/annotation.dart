import 'dart:ui';

/// 마크업 편집 도구 종류
enum AnnotationTool {
  pen('펜', '자유 곡선 그리기'),
  highlighter('형광펜', '반투명 형광펜 강조'),
  rectangle('사각형', '사각형 테두리 박스'),
  arrow('화살표', '방향 지시 화살표'),
  text('텍스트', '클릭한 위치에 텍스트 삽입'),
  mosaic('모자이크', '민감 정보 블러/픽셀화 가리기');

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

  /// 사각형/모자이크용 시작점~끝점 Rect 반환
  Rect get boundingRect {
    if (points.isEmpty) return Rect.zero;
    if (points.length == 1) {
      return Rect.fromPoints(points.first, points.first);
    }
    return Rect.fromPoints(points.first, points.last);
  }
}
