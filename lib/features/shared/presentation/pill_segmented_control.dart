import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../config/theme/app_theme.dart';

class SegmentOption<T> {
  const SegmentOption({required this.value, required this.label});

  final T value;
  final String label;
}

class PillSegmentedControl<T extends Object> extends StatelessWidget {
  const PillSegmentedControl({
    required this.value,
    required this.options,
    required this.onValueChanged,
    super.key,
  });

  final T value;
  final List<SegmentOption<T>> options;
  final ValueChanged<T> onValueChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFD9D8DE),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        // 自适应：原先每个选项固定 horizontal: 18 内边距，
        // 三个选项（如「待复习 12 / 全部 30 / 已掌握 5」）在 390 宽手机上
        // 会超出屏幕、右侧被裁掉。
        //
        // 注意：**只减小内边距不够** —— CupertinoSlidingSegmentedControl
        // 每个分段的最小宽度由内容决定，实际总宽仍可能超过可用宽度。
        // 因此这里额外套一层横向滚动：窄屏时用户可以横滑看到全部选项，
        // 不会再被裁掉（列表页的同类控件也是这么处理的）。
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            // 按可用宽度反推内边距。上限刻意压到 10：
            // 原先固定 18，三项（待复习/全部/已掌握 + 计数）在 390 宽上
            // 放不下、右侧被裁。实测 10 可完整显示且不显拥挤。
            final double hPad = (c.maxWidth / (options.length * 8)).clamp(
              6.0,
              10.0,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: CupertinoSlidingSegmentedControl<T>(
              groupValue: value,
              backgroundColor: Colors.transparent,
              thumbColor: Colors.white,
              children: <T, Widget>{
                for (final SegmentOption<T> option in options)
                  option.value: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: hPad,
                      vertical: 10,
                    ),
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: option.value == value
                            ? const Color(0xFF00695C)
                            : const Color(0xFF222226),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              },
              onValueChanged: (T? nextValue) {
                if (nextValue != null) {
                  onValueChanged(nextValue);
                }
              },
              ),
            );
          },
        ),
      ),
    );
  }
}
