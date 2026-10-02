import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_theme.dart';

/// 就地调整字幕大小的弹窗。
///
/// 放在播放页里，而不是只放在「设置」中：用户觉得字幕太大时，
/// 人正在看视频，不应该被要求离开当前页面去翻设置。
///
/// 触发方式：长按画面上的字幕。
/// （短按已经被「点词查词典」占用，因此用长按。）
Future<void> showSubtitleSizeSheet({
  required BuildContext context,
  required String current,
  required List<String> options,
  required ValueChanged<String> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final AppPalette palette = AppColors.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: StatefulBuilder(
              builder:
                  (
                    BuildContext context,
                    void Function(void Function()) setSheetState,
                  ) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.format_size_rounded,
                              size: 18,
                              color: palette.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '字幕大小',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '长按字幕可再次打开',
                              style: TextStyle(
                                fontSize: 11,
                                color: palette.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // 实时预览：让用户直接看到效果，而不是靠想象。
                        _PreviewBox(scale: _previewScaleFor(current)),
                        const SizedBox(height: 14),
                        Row(
                          children: <Widget>[
                            for (final String option in options) ...<Widget>[
                              Expanded(
                                child: _SizeOption(
                                  label: option,
                                  selected: option == current,
                                  palette: palette,
                                  onTap: () {
                                    onChanged(option);
                                    setSheetState(() {});
                                    Navigator.of(sheetContext).pop();
                                  },
                                ),
                              ),
                              if (option != options.last)
                                const SizedBox(width: 10),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
            ),
          ),
        ),
      );
    },
  );
}

/// 与 settings 中 fontScale 的映射保持一致（小 .92 / 中 1 / 大 1.18）。
double _previewScaleFor(String option) {
  switch (option) {
    case '小':
      return 0.92;
    case '大':
      return 1.18;
    default:
      return 1;
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF10161A),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: <Widget>[
          Text(
            'The best time to start is now.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22 * scale,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 6 * scale),
          Text(
            '开始的最佳时机就是现在。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14 * scale,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFF7F7F7),
            ),
          ),
        ],
      ),
    );
  }
}

class _SizeOption extends StatelessWidget {
  const _SizeOption({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? palette.brand.withValues(alpha: 0.10)
              : palette.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected
                ? palette.brand.withValues(alpha: 0.45)
                : palette.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w600,
              color: selected ? palette.brand : palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
