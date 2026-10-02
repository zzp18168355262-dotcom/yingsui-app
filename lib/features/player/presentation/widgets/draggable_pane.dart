import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_theme.dart';

/// 可拖动、可缩放的浮动窗格（用于「逐词全文」，与播放页并存）。
///
/// 缩放行为依据用户反馈逐步定型：
/// - **四角 = 等比例缩放**：宽高同比变化，一次拖动即可整体放大/缩小。
///   用户反馈过「放大为什么不能按比例进行，只能先放大高度再放大宽度」。
/// - **四边 = 单向缩放**：只改一个维度，保留精确控制。
/// - 尺寸下限 240×160；上限接近满窗（不设「九成」上限，
///   否则窗格接近上限时就几乎调不动）。
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

  /// 拖动/缩放的起点快照。
  ///
  /// 必须记录起点，而不是在每次回调里用「当前位置 + 本次增量」：
  /// 后者在连续拖动时会把中间若干次位移丢掉
  /// （实测拖动累计 (-100, +150)，结果只应用了最后一个增量）。
  Offset? _dragStartPointer;
  Offset? _dragStartOffset;
  Size? _dragStartSize;

  /// 边与角的命中厚度。
  static const double _handleThickness = 14;

  /// 角块尺寸（比边略大，便于抓取）。
  static const double _cornerSize = 22;

  static const double _titleBarHeight = 40;

  /// 标题栏至少要留在屏幕内的可抓高度。
  static const double _titleBarSafeMargin = 16;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);

    final double maxWidth = screen.width - 16;
    final double maxHeight = screen.height - 16;
    final double minWidth = widget.minSize.width.clamp(120, maxWidth);
    final double minHeight = widget.minSize.height.clamp(100, maxHeight);

    final double width = _size.width.clamp(minWidth, maxWidth);
    final double height = _size.height.clamp(minHeight, maxHeight);

    final Offset base = _offset ?? Offset(screen.width - width - 24, 72);
    // 位置夹取：允许窗格大部分移出屏幕，只保证**标题栏**仍有足够部分
    // 留在可视区内（可以抓到并拖回来）。
    //
    // 原先左右各留 140、上边完全不能出屏，导致窗格默认位置偏右时
    // 往右/往上几乎拖不动，感觉像「不能随意移动」。
    final double left = base.dx.clamp(-width + 180, screen.width - 180);
    // 上边最多露出 _titleBarSafeMargin 的标题栏，保证还能抓回来。
    final double top = base.dy.clamp(
      -_titleBarHeight + _titleBarSafeMargin,
      screen.height - 48,
    );

    final AppPalette palette = AppColors.of(context);

    /// 缩放共用的换算：以**拖动起点**为基准计算总位移。
    void resize(
      Offset totalDelta,
      _Direction direction, {
      required bool proportional,
    }) {
      final Size startSize = _dragStartSize ?? _size;
      final Offset startOffset = _dragStartOffset ?? Offset(left, top);

      // 朝该方向为正的位移。
      final double dx = direction.movesLeft ? -totalDelta.dx : totalDelta.dx;
      final double dy = direction.movesTop ? -totalDelta.dy : totalDelta.dy;

      double nextWidth = startSize.width;
      double nextHeight = startSize.height;

      if (proportional && direction.extendsWidth && direction.extendsHeight) {
        // 四角：等比例。取主导方向，避免斜向拖动过于敏感。
        final double dominant = dx.abs() >= dy.abs() ? dx : dy;
        final double factor = (startSize.width + dominant) / startSize.width;
        nextWidth = (startSize.width * factor).clamp(minWidth, maxWidth);
        final double applied = nextWidth / startSize.width;
        nextHeight = (startSize.height * applied).clamp(minHeight, maxHeight);
      } else {
        if (direction.extendsWidth) {
          nextWidth = (startSize.width + dx).clamp(minWidth, maxWidth);
        }
        if (direction.extendsHeight) {
          nextHeight = (startSize.height + dy).clamp(minHeight, maxHeight);
        }
      }

      final double appliedDx = nextWidth - startSize.width;
      final double appliedDy = nextHeight - startSize.height;

      setState(() {
        _size = Size(nextWidth, nextHeight);
        _offset = Offset(
          startOffset.dx + (direction.movesLeft ? -appliedDx : 0),
          startOffset.dy + (direction.movesTop ? -appliedDy : 0),
        );
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
                    onPanStart: (DragStartDetails details) {
                      _dragStartPointer = details.globalPosition;
                      _dragStartOffset = Offset(left, top);
                    },
                    onPanUpdate: (DragUpdateDetails details) {
                      final Offset? startPointer = _dragStartPointer;
                      final Offset? startOffset = _dragStartOffset;
                      if (startPointer == null || startOffset == null) {
                        return;
                      }
                      // 以起点为基准：全程跟随指针的总位移。
                      // 若用「当前位置 + 本次增量」，连续拖动会丢掉中间位移。
                      final Offset total = details.globalPosition - startPointer;
                      setState(() {
                        _offset = startOffset + total;
                      });
                    },
                    onPanEnd: (DragEndDetails details) {
                      _dragStartPointer = null;
                      _dragStartOffset = null;
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

        // ── 四边：单向缩放 ──
        for (final _Direction d in <_Direction>[
          _Direction.top,
          _Direction.bottom,
          _Direction.left,
          _Direction.right,
        ])
          _handle(
            direction: d,
            isCorner: false,
            left: left,
            top: top,
            width: width,
            height: height,
            onDrag: (Offset d, _Direction dir) =>
                resize(d, dir, proportional: false),
          ),

        // ── 四角：等比例缩放 ──
        for (final _Direction d in <_Direction>[
          _Direction.topLeft,
          _Direction.topRight,
          _Direction.bottomLeft,
          _Direction.bottomRight,
        ])
          _handle(
            direction: d,
            isCorner: true,
            left: left,
            top: top,
            width: width,
            height: height,
            onDrag: (Offset d, _Direction dir) =>
                resize(d, dir, proportional: true),
          ),

        // 右下角可视提示：说明「这里可以缩放」。
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
    required _Direction direction,
    required bool isCorner,
    required double left,
    required double top,
    required double width,
    required double height,
    required void Function(Offset, _Direction) onDrag,
  }) {
    const double t = _handleThickness;
    const double c = _cornerSize;

    final double hLeft;
    final double hTop;
    final double hWidth;
    final double hHeight;

    switch (direction) {
      case _Direction.top:
        hLeft = left + c;
        hTop = top - t / 2;
        hWidth = width - c * 2;
        hHeight = t;
      case _Direction.bottom:
        hLeft = left + c;
        hTop = top + height - t / 2;
        hWidth = width - c * 2;
        hHeight = t;
      case _Direction.left:
        hLeft = left - t / 2;
        hTop = top + c;
        hWidth = t;
        hHeight = height - c * 2;
      case _Direction.right:
        hLeft = left + width - t / 2;
        hTop = top + c;
        hWidth = t;
        hHeight = height - c * 2;
      case _Direction.topLeft:
        hLeft = left - t / 2;
        hTop = top - t / 2;
        hWidth = c;
        hHeight = c;
      case _Direction.topRight:
        hLeft = left + width - c + t / 2;
        hTop = top - t / 2;
        hWidth = c;
        hHeight = c;
      case _Direction.bottomLeft:
        hLeft = left - t / 2;
        hTop = top + height - c + t / 2;
        hWidth = c;
        hHeight = c;
      case _Direction.bottomRight:
        hLeft = left + width - c + t / 2;
        hTop = top + height - c + t / 2;
        hWidth = c;
        hHeight = c;
    }

    return Positioned(
      left: hLeft,
      top: hTop,
      child: MouseRegion(
        cursor: _cursorFor(direction),
        child: GestureDetector(
          key: ValueKey<String>(
            'pane-resize-${isCorner ? 'corner-' : ''}${direction.name}',
          ),
          behavior: HitTestBehavior.opaque,
          onPanStart: (DragStartDetails details) {
            _dragStartPointer = details.globalPosition;
            _dragStartOffset = Offset(left, top);
            _dragStartSize = Size(width, height);
          },
          onPanUpdate: (DragUpdateDetails details) {
            final Offset? startPointer = _dragStartPointer;
            if (startPointer == null) {
              return;
            }
            onDrag(details.globalPosition - startPointer, direction);
          },
          onPanEnd: (DragEndDetails details) {
            _dragStartPointer = null;
            _dragStartOffset = null;
            _dragStartSize = null;
          },
          child: SizedBox(width: hWidth, height: hHeight),
        ),
      ),
    );
  }

  MouseCursor _cursorFor(_Direction d) {
    switch (d) {
      case _Direction.top:
      case _Direction.bottom:
        return SystemMouseCursors.resizeUpDown;
      case _Direction.left:
      case _Direction.right:
        return SystemMouseCursors.resizeLeftRight;
      case _Direction.topLeft:
        return SystemMouseCursors.resizeUpLeft;
      case _Direction.topRight:
        return SystemMouseCursors.resizeUpRight;
      case _Direction.bottomLeft:
        return SystemMouseCursors.resizeDownLeft;
      case _Direction.bottomRight:
        return SystemMouseCursors.resizeDownRight;
    }
  }
}

/// 缩放方向。
enum _Direction {
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get extendsWidth =>
      this == left ||
      this == right ||
      this == topLeft ||
      this == topRight ||
      this == bottomLeft ||
      this == bottomRight;

  bool get extendsHeight =>
      this == top ||
      this == bottom ||
      this == topLeft ||
      this == topRight ||
      this == bottomLeft ||
      this == bottomRight;

  /// 拉动该方向时窗格左边缘是否需要移动（保持对角固定）。
  bool get movesLeft => this == left || this == topLeft || this == bottomLeft;

  /// 拉动该方向时窗格上边缘是否需要移动（保持对角固定）。
  bool get movesTop => this == top || this == topLeft || this == topRight;
}
