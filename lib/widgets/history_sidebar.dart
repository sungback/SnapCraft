import 'package:flutter/material.dart';

import '../models/capture_item.dart';

class HistorySidebar extends StatelessWidget {
  final List<CaptureItem> items;
  final CaptureItem? selectedItem;
  final ValueChanged<CaptureItem> onSelectItem;
  final ValueChanged<CaptureItem> onDeleteItem;

  const HistorySidebar({
    super.key,
    required this.items,
    required this.selectedItem,
    required this.onSelectItem,
    required this.onDeleteItem,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: Color(0xFF191B22),
        border: Border(right: BorderSide(color: Color(0xFF2B2E3B), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.history_rounded,
                  size: 17,
                  color: Colors.white70,
                ),
                const SizedBox(width: 7),
                const Text(
                  '최근 캡쳐 목록',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF282B36),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2B2E3B)),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        '아직 캡쳐한 화면이 없습니다.\n상단 버튼이나 단축키로\n캡쳐를 시작해보세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white38,
                          height: 1.5,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = selectedItem?.id == item.id;
                      final timeStr =
                          '${item.capturedAt.hour.toString().padLeft(2, '0')}:'
                          '${item.capturedAt.minute.toString().padLeft(2, '0')}:'
                          '${item.capturedAt.second.toString().padLeft(2, '0')}';

                      return InkWell(
                        onTap: () => onSelectItem(item),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF29324A)
                                : const Color(0xFF222530),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF60A5FA)
                                  : const Color(0xFF2E3240),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  height: 105,
                                  color: Colors.black38,
                                  child: RawImage(
                                    image: item.decodedImage,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.modeLabel,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item.resolutionLabel,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white54,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => onDeleteItem(item),
                                    borderRadius: BorderRadius.circular(4),
                                    child: const Padding(
                                      padding: EdgeInsets.all(2),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 15,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Text(
                                    timeStr,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.white38,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (item.annotations.isNotEmpty)
                                    Text(
                                      '마크업 ${item.annotations.length}개',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: Color(0xFF60A5FA),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
