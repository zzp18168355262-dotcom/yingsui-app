import 'package:flutter/material.dart';

import '../../../../config/theme/app_theme.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import 'selection_translate_bar.dart';

/// 一行**可划选短语**的文本。
///
/// 封装了整套「长按词块 → 划过相邻词 → 拼出短语」的交互，供两处复用：
///   · 播放页字幕列表（PlayerSubtitleList）
///   · 影子跟读面板（ShadowingPracticePanel）
///
/// 为什么不用系统文本选择：外层通常是 ListView / 可滚动容器，
/// 且每个词块自身要响应点击（查词），两者与 SelectionArea
/// 在手势竞技场里的竞争不可靠 —— 实测长按无法稳定产生选中。
///
/// 交互要点（都是踩过坑才定下来的）：
///   · 长按放在 GestureDetector：InkWell 不支持 onLongPressMoveUpdate，
///     而拖动过程需要持续收到位置；
///   · 同时挂「长按拖动」与「横向拖动」两条路径：
///     手指用长按再划（避免与列表纵向滚动打架），
///     鼠标是按下就拖（不等 500ms，长按识别器会因超过 touch slop 直接失败）；
///   · 横向拖动先挂起，真的横向移开一段距离才落实为选择，
///     否则「只想滚列表」也会选中一个词。
class SelectablePhraseLine extends StatefulWidget {
  const SelectablePhraseLine({
    required this.text,
    required this.onTranslate,
    this.highlightIndex,
    this.active = false,
    this.lookupOnTap = true,
    this.onTapWord,
    this.onCollect,
    this.fontSize,
    this.textColor,
    this.scope = 'en',
    this.height = 1.4,
    this.showSelectionBar = true,
    super.key,
  });

  final String text;

  /// 点击「翻译选中」时回调（收到选中的短语与所在整句）。
  final void Function(String phrase, String contextSentence) onTranslate;

  /// 是否高亮某个词（跟随播放的当前词）。
  final int? highlightIndex;

  /// 该行是否为当前播放句。
  final bool active;

  /// 中文行只用于划选，不做逐词查词（离线词典是英汉词典）。
  final bool lookupOnTap;

  /// 点词查词回调。
  final void Function(BuildContext wordContext, String word, String tokenId)?
  onTapWord;

  /// 收藏短语；为空时不显示收藏按钮。
  final Future<void> Function(String phrase, String contextSentence)? onCollect;

  /// 覆盖字号（未乘缩放的基准值）。为空时用默认。
  final double? fontSize;

  /// 覆盖文字颜色。
  final Color? textColor;

  /// 词块 key 的作用域。同一行渲染多条文本流时必须不同，
  /// 否则会产生重复 GlobalKey。
  final String scope;

  final double height;

  /// 是否显示「翻译选中」提示条。子集场景（如仅展示一行）可关闭。
  final bool showSelectionBar;

  @override
  State<SelectablePhraseLine> createState() => _SelectablePhraseLineState();
}

class _SelectablePhraseLineState extends State<SelectablePhraseLine> {
  /// 当前选中的短语。用 ValueNotifier 单独驱动提示条重建，
  /// 避免每帧重建整行。
  final ValueNotifier<String> _selected = ValueNotifier<String>('');

  /// 词块的持久化 key。
  ///
  /// 必须持久：拖动时的命中判定靠 currentContext 拿位置，
  /// 而 setState 重建会让新 key 的 currentContext 变 null。
  final Map<String, GlobalKey> _keyCache = <String, GlobalKey>{};

  int? _dragStartTokenIndex;
  int? _dragEndTokenIndex;
  List<GlobalKey> _dragTokenKeys = const <GlobalKey>[];

  /// 「按下即拖」路径的待定状态。
  ///
  /// 横向拖动识别器在没有任何竞争者时会在抬手时直接判给它，
  /// 于是一次纯纵向滚动也会走到 onHorizontalDragStart，
  /// 表现为「只想滚列表却选中了一个词」。先挂起，等真的横向移开再落实。
  int? _pendingTokenIndex;
  double? _pendingStartX;
  static const double _dragCommitDistance = 24;

  @override
  void dispose() {
    _selected.dispose();
    super.dispose();
  }

  /// 连续中文、或连续非中文非空白的片段。
  static final RegExp _runPattern = RegExp(
    r'[\u4e00-\u9fff\u3400-\u4dbf]+|[^\s\u4e00-\u9fff\u3400-\u4dbf]+',
  );

  /// 把文本切成可选词块。
  ///
  /// 英文按空白切；中文没有空格，按 2 字滑窗切
  /// （「科学让我欲火焚身」→ 科学 / 学让 / 让我 / …）。
  ///
  /// 先按空白切段再切块：中文句子也可能带空格（如「第 18 句中文内容」），
  /// 直接整句滑窗会让空格成为词块，污染选中结果。
  List<String> _tokens(String text) {
    final List<String> tokens = <String>[];

    void addRun(String run) {
      if (run.isEmpty) {
        return;
      }
      final bool isCjk = RegExp(
        r'^[\u4e00-\u9fff\u3400-\u4dbf]+$',
      ).hasMatch(run);
      if (!isCjk) {
        tokens.add(run);
        return;
      }
      if (run.length <= 2) {
        tokens.add(run);
        return;
      }
      for (int i = 0; i < run.length - 1; i += 1) {
        tokens.add(run.substring(i, i + 2));
      }
    }

    for (final String segment in text.split(RegExp(r'\s+'))) {
      if (segment.isEmpty) {
        continue;
      }
      for (final RegExpMatch match in _runPattern.allMatches(segment)) {
        addRun(match.group(0)!);
      }
    }
    return tokens;
  }

  GlobalKey _keyFor(int index) => _keyCache.putIfAbsent(
    '${widget.scope}-$index',
    () => GlobalKey(debugLabel: 'phrase-${widget.scope}-$index'),
  );

  void _beginDrag(int tokenIndex, List<GlobalKey> keys) {
    final List<String> tokens = _tokens(widget.text);
    if (tokenIndex >= tokens.length) {
      return;
    }
    setState(() {
      _dragStartTokenIndex = tokenIndex;
      _dragEndTokenIndex = tokenIndex;
      _dragTokenKeys = keys;
    });
    _selected.value = tokens[tokenIndex];
  }

  void _updateDrag(Offset globalPosition) {
    final int? start = _dragStartTokenIndex;
    if (start == null) {
      return;
    }
    int? hit;
    for (int i = 0; i < _dragTokenKeys.length; i += 1) {
      final BuildContext? ctx = _dragTokenKeys[i].currentContext;
      final RenderObject? obj = ctx?.findRenderObject();
      if (obj is! RenderBox || !obj.hasSize) {
        continue;
      }
      final Offset topLeft = obj.localToGlobal(Offset.zero);
      if (Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        obj.size.width,
        obj.size.height,
      ).contains(globalPosition)) {
        hit = i;
        break;
      }
    }
    if (hit == null || hit == _dragEndTokenIndex) {
      return;
    }
    setState(() => _dragEndTokenIndex = hit);
    final int lo = start < hit ? start : hit;
    final int hi = start < hit ? hit : start;
    final List<String> tokens = _tokens(widget.text);
    if (hi < tokens.length) {
      _selected.value = tokens.sublist(lo, hi + 1).join(' ');
    }
  }

  void _endDrag() {
    if (_dragStartTokenIndex == null && _pendingTokenIndex == null) {
      return;
    }
    setState(() {
      _dragStartTokenIndex = null;
      _dragEndTokenIndex = null;
      _pendingTokenIndex = null;
      _pendingStartX = null;
    });
  }

  void _beginPending(int tokenIndex, double globalX) {
    _pendingTokenIndex = tokenIndex;
    _pendingStartX = globalX;
  }

  void _updatePending(double globalX) {
    final int? index = _pendingTokenIndex;
    final double? startX = _pendingStartX;
    if (index == null || startX == null) {
      return;
    }
    if ((globalX - startX).abs() < _dragCommitDistance) {
      return;
    }
    _pendingTokenIndex = null;
    _pendingStartX = null;
    final List<GlobalKey> keys = <GlobalKey>[
      for (int i = 0; i < _tokens(widget.text).length; i += 1) _keyFor(i),
    ];
    _beginDrag(index, keys);
  }

  @override
  Widget build(BuildContext context) {
    final List<String> tokens = _tokens(widget.text);
    if (tokens.isEmpty) {
      return const SizedBox.shrink();
    }
    final List<GlobalKey> keys = <GlobalKey>[
      for (int i = 0; i < tokens.length; i += 1) _keyFor(i),
    ];

    final int dragLo = _dragStartTokenIndex == null
        ? -1
        : (_dragStartTokenIndex! < (_dragEndTokenIndex ?? _dragStartTokenIndex!)
              ? _dragStartTokenIndex!
              : (_dragEndTokenIndex ?? _dragStartTokenIndex!));
    final int dragHi = _dragStartTokenIndex == null
        ? -1
        : (_dragStartTokenIndex! > (_dragEndTokenIndex ?? _dragStartTokenIndex!)
              ? _dragStartTokenIndex!
              : (_dragEndTokenIndex ?? _dragStartTokenIndex!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[
            for (int index = 0; index < tokens.length; index += 1)
              Builder(
                key: keys[index],
                builder: (BuildContext wordContext) {
                  final bool inDragRange = index >= dragLo && index <= dragHi;
                  final bool highlighted =
                      widget.active &&
                      widget.highlightIndex != null &&
                      index == widget.highlightIndex;
                  final String tokenId = '${widget.scope}-$index';
                  return GestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    onLongPressStart: (LongPressStartDetails _) =>
                        _beginDrag(index, keys),
                    onLongPressMoveUpdate: (LongPressMoveUpdateDetails details) =>
                        _updateDrag(details.globalPosition),
                    onLongPressEnd: (LongPressEndDetails _) => _endDrag(),
                    onLongPressCancel: _endDrag,
                    onHorizontalDragStart: (DragStartDetails details) =>
                        _beginPending(index, details.globalPosition.dx),
                    onHorizontalDragUpdate: (DragUpdateDetails details) =>
                        _updatePending(details.globalPosition.dx),
                    onHorizontalDragEnd: (DragEndDetails _) => _endDrag(),
                    onHorizontalDragCancel: _endDrag,
                    child: InkWell(
                      onTap: widget.lookupOnTap
                          ? () {
                              if (_selected.value.isNotEmpty) {
                                _selected.value = '';
                              }
                              widget.onTapWord?.call(
                                wordContext,
                                tokens[index],
                                tokenId,
                              );
                            }
                          : null,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          color: inDragRange
                              ? const Color(0xFFB7D9CE)
                              : (highlighted
                                    ? AppDesignTokens.brandGreen.withValues(
                                        alpha: 0.22,
                                      )
                                    : Colors.transparent),
                        ),
                        child: Text(
                          tokens[index],
                          style: TextStyle(
                            fontSize: widget.fontSize,
                            height: widget.height,
                            fontWeight: highlighted
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color:
                                widget.textColor ??
                                AppDesignTokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        // 提示条放在**正常流**里（不再是 Stack 里的 Positioned）。
        //
        // 原因：Positioned 会溢出 Stack 的边界，导致提示条虽然可见，
        // 但超出部分**不可点击**（按钮点不动）。放在流里既能点击，
        // 也不会像字幕列表那样造成「选中时列表跳动」的问题 ——
        // 这里只是面板内的一行文本，高度变化不影响滚动位置。
        if (widget.showSelectionBar)
          ValueListenableBuilder<String>(
            valueListenable: _selected,
            builder: (BuildContext context, String selected, Widget? _) {
              if (selected.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectionTranslateBar(
                  selectedText: selected,
                  onTranslate: (_) =>
                      widget.onTranslate(selected, widget.text),
                  onCollect: widget.onCollect == null
                      ? null
                      : () => widget.onCollect!(selected, widget.text),
                  onDismiss: () => _selected.value = '',
                ),
              );
            },
          ),
      ],
    );
  }
}
