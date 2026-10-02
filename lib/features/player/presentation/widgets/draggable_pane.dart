import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_theme.dart';

/// 可拖动、可从**四边与四角**缩放的浮动窗格。
///
/// 用于「逐词全文」：与播放页并存，而不是整页盖住。
///
/// 设计取舍（来自用户反馈）：
/// - 缩放把手做成八方向（上/下/左/右 + 四角），而不是只有一个右下角
///   ——「只能按住右下角那个图标缩放，不方便」。
/// - 尺寸上限放开到接近满窗、下限收到 240×160
///   ——「可以调节的大小范围还是有限」。原先上限是屏幕九成，
///   窗格接近上限时就几乎无法再调。
/// - 位置夹取在可视区内，保证标题栏始终可点到。
class DraggablePane extends StatefulWidget {
  const DraggablePane({
    super.key,
    required this.title,
    required this.child,
    required this.onClose,
    this.initialSize = const Size(640, 480),
    this.initialOffset,
    this.minSize = const Size(240, 160),
  });

  final String title;
  final Widget child;
  final VoidCallback onClose;
  final Size initialSize;
  final Offset? initialOffset;
  final Size minSize;

  @override
  State<DraggablePane> createState() => _DraggablePaneState();
}

class _DraggablePaneState extends State<DraggablePane> {
  late Size _size = widget.initialSize;
  Offset? _offset;

  /// 边与角的命中厚度。
  static const double _handleThickness = 14;

  /// 角块尺寸（比边略大，便于抓取）。
  static const double _cornerSize = 22;

  /// 标题栏高度。
  static const double _titleBarHeight = 40;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);

    // 上限：允许几乎铺满整个窗口，只留一点点边距便于再拖回。
    final double maxWidth = screen.width - 16;
    final double maxHeight = screen.height - 16;

    // 下限不超过上限，否则 clamp 参数非法。
    final double minWidth = widget.minSize.width.clamp(120, maxWidth);
    final double minHeight = widget.minSize.height.clamp(100, maxHeight);

    final double width = _size.width.clamp(minWidth, maxWidth);
    final double height = _size.height.clamp(minHeight, maxHeight);

    final Offset base = _offset ?? Offset(screen.width - width - 24, 72);

    // 夹取位置：标题栏始终可点到（否则拖出屏幕就找不回来了）。
    final double left = base.dx.clamp(-width + 140, screen.width - 140);
    final double top = base.dy.clamp(0, screen.height - _titleBarHeight);

    final AppPalette palette = AppColors.of(context);

    void resize(Offset delta, {required bool fromLeft, required bool fromTop}) {
      setState(() {
        final double nextWidth = (_size.width + (fromLeft ? -delta.dx : delta.dx))
            .clamp(minWidth, maxWidth);
        final double nextHeight =
            (_size.height + (fromTop ? -delta.dy : delta.dy)).clamp(
              minHeight,
              maxHeight,
            );
        final double appliedDx = nextWidth - _size.width;
        final double appliedDy = nextHeight - _size.height;
        _size = Size(nextWidth, nextHeight);
        // 从左边/上边缩放时窗格位置同步移动，视觉上才是「边被拉动」。
        if (fromLeft || fromTop) {
          _offset = Offset(
            left + (fromLeft ? -appliedDx : 0),
            top + (fromTop ? -appliedDy : 0),
          );
        }
      });
    }

    return Stack(
      children: <Widget>[
        Positioned(
          left: left,
          top: top,
          child: Material(
            key: const ValueKey<String>('pane-surface'),
            elevation: 12,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              height: height,
              child: Column(
                children: <Widget>[
                  // 标题栏：拖动移动窗格。
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (DragUpdateDetails details) {
                      setState(() {
                        _offset = Offset(left, top) + details.delta;
                      });
                    },
                    child: Container(
                      height: _titleBarHeight,
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
                  Expanded(child: widget.child),
                ],
              ),
            ),
          ),
        ),

        // ── 缩放把手：四边 + 四角，共八处 ──
        _handle(
          key: const ValueKey<String>('pane-resize-top'),
          left: left,
          top: top,
          width: width,
          height: height,
          cursor: SystemMouseCursors.resizeUpDown,
          position: _HandlePosition.top,
          onDrag: (Offset d) => resize(d, fromLeft: false, fromTop: true),
        ),
        _handle(
          key: const ValueKey<String>('pane-resize-bottom'),
          left: left,
          top: top,
          width: width,
          height: height,
          cursor: SystemMouseCursors.resizeUpDown,
          position: _HandlePosition.bottom,
          onDrag: (Offset d) => resize(d, fromLeft: false, fromTop: false),
        ),
        _handle(
          key: const ValueKey<String>('pane-resize-left'),
          left: left,
          top: top,
          width: width,
          height: height,
          cursor: SystemMouseCursors.resizeLeftRight,
          position: _HandlePosition.left,
          onDrag: (Offset d) => resize(d, fromLeft: true, fromTop: false),
        ),
        _handle(
          key: const ValueKey<String>('pane-resize-right'),
          left: left,
          top: top,
          width: width,
          height: height,
          cursor: SystemMouseCursors.resizeLeftRight,
          position: _HandlePosition.right,
          onDrag: (Offset d) => resize(d, fromLeft: false, fromTop: false),
        ),
        _handle(
          key: const ValueKey<String>('pane-resize-topLeft'),
          left: left,
          top: top,
          width: width,
          height: height,
          cursor: SystemMouseCursors.resizeUpLeft,
          position: _HandlePosition.topLeft,
          onDrag: (Offset d) => resize(d, fromLeft: true, fromTop: true),
        ),
        _handle(
          key: const ValueKey<String>('pane-resize-topRight'),
          left: left,
          top: top,
          width: width,
          height: height,
          cursor: SystemMouseCursors.resizeUpRight,
          position: _HandlePosition.topRight,
          onDrag: (Offset d) => resize(d, fromLeft: false, fromTop: true),
        ),
        _handle(
          key: const ValueKey<String>('pane-resize-bottomLeft'),
          left: left,
          top: top,
          width: width,
          height: height,
          cursor: SystemMouseCursors.resizeDownLeft,
          position: _HandlePosition.bottomLeft,
          onDrag: (Offset d) => resize(d, fromLeft: true, fromTop: false),
        ),
        _handle(
          key: const ValueKey<String>('pane-resize-bottomRight'),
          left: left,
          top: top,
          width: width,
          height: height,
          cursor: SystemMouseCursors.resizeDownRight,
          position: _HandlePosition.bottomRight,
          onDrag: (Offset d) => resize(d, fromLeft: false, fromTop: false),
        ),

        // 右下角可视提示：明确告诉用户「这里可以缩放」。
        Positioned(
          left: left + width - 26,
          top: top + height - 26,
          child: const IgnorePointer(
            child: Icon(
              Icons.open_in_full_rounded,
              size: 16,
              color: Color(0xFF8A9691),
            ),
          ),
        ),
      ],
    );
  }

  Widget _handle({
    Key? key,
    required double left,
    required double top,
    required double width,
    required double height,
    required MouseCursor cursor,
    required _HandlePosition position,
    required ValueChanged<Offset> onDrag,
  }) {
    const double t = _handleThickness;
    const double corner = _cornerSize;

    final double hLeft;
    final double hTop;
    final double hWidth;
    final double hHeight;

    switch (position) {
      case _HandlePosition.top:
        hLeft = left + corner;
        hTop = top - t / 2;
        hWidth = width - corner * 2;
        hHeight = t;
      case _HandlePosition.bottom:
        hLeft = left + corner;
        hTop = top + height - t / 2;
        hWidth = width - corner * 2;
        hHeight = t;
      case _HandlePosition.left:
        hLeft = left - t / 2;
        hTop = top + corner;
        hWidth = t;
        hHeight = height - corner * 2;
      case _HandlePosition.right:
        hLeft = left + width - t / 2;
        hTop = top + corner;
        hWidth = t;
        hHeight = height - corner * 2;
      case _HandlePosition.topLeft:
        hLeft = left - t / 2;
        hTop = top - t / 2;
        hWidth = corner;
        hHeight = corner;
      case _HandlePosition.topRight:
        hLeft = left + width - corner + t / 2;
        hTop = top - t / 2;
        hWidth = corner;
        hHeight = corner;
      case _HandlePosition.bottomLeft:
        hLeft = left - t / 2;
        hTop = top + height - corner + t / 2;
        hWidth = corner;
        hHeight = corner;
      case _HandlePosition.bottomRight:
        hLeft = left + width - corner + t / 2;
        hTop = top + height - corner + t / 2;
        hWidth = corner;
        hHeight = corner;
    }

    return Positioned(
      key: key,
      left: hLeft,
      top: hTop,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (DragUpdateDetails details) => onDrag(details.delta),
          child: SizedBox(width: hWidth, height: hHeight),
        ),
      ),
    );
  }
}

enum _HandlePosition {
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}
