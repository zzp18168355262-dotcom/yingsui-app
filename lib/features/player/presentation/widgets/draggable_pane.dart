import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_theme.dart';

/// 可拖动、可缩放的浮动窗格。
///
/// 用于「逐词全文」：用户要求它与视频**并存**，而不是整页盖住播放页。
/// 窗格有标题栏，可拖动改变位置；右下角把手可缩放尺寸。
///
/// 实现要点：
/// - 位置用 Offset 记录，拖动结束后夹取到可视区内，避免被拖出屏幕后找不回来。
/// - 尺寸有上下限，既保证内容可读，也不会大到遮住整个视频。
/// - 关闭由 [onClose] 交回宿主处理。
class DraggablePane extends StatefulWidget {
  const DraggablePane({
    super.key,
    required this.title,
    required this.child,
    required this.onClose,
    this.initialSize = const Size(620, 460),
    this.initialOffset,
    this.minSize = const Size(360, 260),
  });

  /// 标题栏文字。
  final String title;

  /// 窗格内容。
  final Widget child;

  /// 关闭回调。
  final VoidCallback onClose;

  final Size initialSize;

  /// 初始位置；为空时放在右上角附近。
  final Offset? initialOffset;

  final Size minSize;

  @override
  State<DraggablePane> createState() => _DraggablePaneState();
}

class _DraggablePaneState extends State<DraggablePane> {
  late Size _size = widget.initialSize;
  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    // 尺寸夹取：不超过屏幕的九成，也不小于最小值。
    final double maxWidth = screen.width * 0.9;
    final double maxHeight = screen.height * 0.9;
    final double width = _size.width.clamp(
      widget.minSize.width > maxWidth ? maxWidth : widget.minSize.width,
      maxWidth,
    );
    final double height = _size.height.clamp(
      widget.minSize.height > maxHeight ? maxHeight : widget.minSize.height,
      maxHeight,
    );

    // 默认位置：右上角留出边距。
    final Offset position =
        _offset ??
        widget.initialOffset ??
        Offset(screen.width - width - 24, 72);

    // 夹取到可视区内，保证标题栏始终可点到（否则拖出去就找不回来了）。
    final double clampedLeft = position.dx.clamp(
      -width + 120,
      screen.width - 120,
    );
    final double clampedTop = position.dy.clamp(0, screen.height - 48);

    final AppPalette palette = AppColors.of(context);

    return Stack(
      children: <Widget>[
        Positioned(
          left: clampedLeft,
          top: clampedTop,
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              height: height,
              child: Column(
                children: <Widget>[
                  // 标题栏：拖动区域。
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (DragUpdateDetails details) {
                      setState(() {
                        final Offset base = _offset ?? position;
                        _offset = base + details.delta;
                      });
                    },
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      decoration: BoxDecoration(
                        color: palette.surfaceAlt,
                        border: Border(
                          bottom: BorderSide(color: palette.border),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.drag_indicator_rounded,
                            size: 16,
                            color: palette.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: widget.onClose,
                            tooltip: '关闭',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 内容区。
                  Expanded(child: widget.child),
                ],
              ),
            ),
          ),
        ),
        // 右下角缩放把手。
        Positioned(
          left: clampedLeft + width - 22,
          top: clampedTop + height - 22,
          child: GestureDetector(
            onPanUpdate: (DragUpdateDetails details) {
              setState(() {
                _size = Size(
                  _size.width + details.delta.dx,
                  _size.height + details.delta.dy,
                );
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeDownRight,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                child: Icon(
                  Icons.signal_cellular_4_bar_rounded,
                  size: 14,
                  color: palette.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
