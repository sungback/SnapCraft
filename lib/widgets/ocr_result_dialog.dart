import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OcrResultDialog extends StatefulWidget {
  final String initialText;

  const OcrResultDialog({super.key, required this.initialText});

  @override
  State<OcrResultDialog> createState() => _OcrResultDialogState();
}

class _OcrResultDialogState extends State<OcrResultDialog> {
  late final TextEditingController _controller;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copyText() async {
    final text = _controller.text;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('추출된 텍스트가 클립보드에 복사되었습니다!'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 360,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final length = _controller.text.length;

    return AlertDialog(
      backgroundColor: const Color(0xFF222530),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF3B4154), width: 1),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.document_scanner_rounded,
              color: Color(0xFF60A5FA),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '화면 텍스트 추출 (OCR)',
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          Text(
            '$length자',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 280,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF181A22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2E323E)),
          ),
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: Color(0xFFE2E8F0),
              fontFamily: 'monospace',
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '추출된 텍스트가 없습니다.',
              hintStyle: TextStyle(color: Colors.white30),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton.icon(
          onPressed: _copyText,
          icon: Icon(
            _copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 16,
          ),
          label: Text(_copied ? '복사됨' : '클립보드 복사'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
