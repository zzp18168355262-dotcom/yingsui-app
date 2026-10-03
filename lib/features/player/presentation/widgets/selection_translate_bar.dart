import 'package:flutter/material.dart';

import '../../../../config/theme/app_theme.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';

/// 「已选中一段文本」时出现的操作条：翻译选中 / 收藏 / 取消。
///
/// 从播放页字幕列表里抽出来，让**跟读面板**也能复用同一套划选交互。
///
/// 独立成 StatefulWidget 是为了把重建范围局限在这一条上：
/// 拖选时选中文本持续变化，若由外层承载就会每帧重建整个列表/面板。
class SelectionTranslateBar extends StatefulWidget {
  const SelectionTranslateBar({
    required this.selectedText,
    required this.onTranslate,
    required this.onDismiss,
    this.onCollect,
    super.key,
  });

  final String selectedText;

  /// 翻译入口。回调收到的是本条的身份锚点上下文，
  /// 调用方可据此把结果弹层定位在它旁边。
  final void Function(BuildContext anchorContext) onTranslate;

  final VoidCallback onDismiss;

  /// 收藏该短语；为空时不显示收藏按钮。
  final Future<void> Function()? onCollect;

  @override
  State<SelectionTranslateBar> createState() => _SelectionTranslateBarState();
}

class _SelectionTranslateBarState extends State<SelectionTranslateBar> {
  /// 收藏进行中（可能需要先取译文），期间禁用按钮避免重复提交。
  bool _collecting = false;

  Future<void> _handleCollect() async {
    final Future<void> Function()? collect = widget.onCollect;
    if (collect == null || _collecting) {
      return;
    }
    setState(() => _collecting = true);
    try {
      await collect();
    } finally {
      if (mounted) {
        setState(() => _collecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(AppRadius.md),
      color: AppDesignTokens.appWhite,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Builder(
          builder: (BuildContext anchorContext) {
            return Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.selectedText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const ValueKey<String>('subtitle-translate-selection'),
                  onPressed: () => widget.onTranslate(anchorContext),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: const Icon(Icons.translate_rounded, size: 16),
                  label: const Text('翻译选中'),
                ),
                if (widget.onCollect != null) ...<Widget>[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    key: const ValueKey<String>('subtitle-collect-selection'),
                    onPressed: _collecting ? null : _handleCollect,
                    tooltip: '收藏到短语库',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 34,
                    ),
                    icon: _collecting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bookmark_add_outlined),
                  ),
                ],
                IconButton(
                  onPressed: widget.onDismiss,
                  tooltip: '取消选择',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
