import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import '../../../../config/theme/app_theme.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/word_lookup_popup.dart';
import '../player_mock_state.dart';
import 'subtitle_word_highlight_style.dart';

const double _activeFontSize = 20;

class PlayerSubtitleList extends StatefulWidget {
  const PlayerSubtitleList({
    required this.lines,
    required this.activeIndex,
    required this.subtitleMode,
    this.showCurrentOnly = false,
    required this.currentWordIndex,
    required this.fontScale,
    required this.highlightWords,
    this.subtitleWordHighlightStyle = '绿色填充',
    this.subtitleWordHighlightBorderWidth = 2.5,
    required this.onTapLine,
    required this.onCollectWord,
    /// 把「选中的短语/整句」收藏进短语库。
    ///
    /// 与 onCollectWord 的区别：那个收藏的是**整句**（把生词记在释义里），
    /// 这里收藏的是**用户选中的片段本身**，更适合短语积累。
    this.onCollectPhrase,
    this.onFavoriteWord,
    required this.onBookmarkLine,
    required this.onLoopFromLine,
    required this.onDictationLine,
    required this.onAiExplain,
    this.loopingLineIndex,
    this.isPlaying = false,
    this.onTogglePlaying,
    this.onPronounce,
    this.showAiGenerateSubtitles = false,
    this.generatingAiSubtitles = false,
    this.aiSubtitleProgressValue,
    this.aiSubtitleProgressText,
    this.aiSubtitlePreviewText,
    this.aiSubtitleErrorText,
    this.onGenerateAiSubtitles,
    this.onRegenerateAiSubtitles,
    this.onDeleteAiSubtitles,
    this.onRegenerateAiLine,
    super.key,
  });

  final List<PlayerSubtitleLine> lines;
  final int activeIndex;
  final String subtitleMode;
  final bool showCurrentOnly;
  final int currentWordIndex;
  final double fontScale;
  final bool highlightWords;
  final String subtitleWordHighlightStyle;
  final double subtitleWordHighlightBorderWidth;
  final ValueChanged<int> onTapLine;
  final ValueChanged<String> onCollectWord;

  /// 收藏选中的短语；为空时不显示该按钮。
  ///
  /// 入参为 (短语, 所在整句)。整句同时作为收藏条目的例句上下文。
  /// 返回 Future 以便界面在收藏期间显示进行中状态。
  final Future<void> Function(String phrase, String contextSentence)?
  onCollectPhrase;
  final ValueChanged<String>? onFavoriteWord;
  final ValueChanged<int> onBookmarkLine;
  final ValueChanged<int> onLoopFromLine;
  final ValueChanged<int> onDictationLine;
  final ValueChanged<int> onAiExplain;
  final int? loopingLineIndex;
  final bool isPlaying;
  final VoidCallback? onTogglePlaying;
  final VoidCallback? onPronounce;
  final bool showAiGenerateSubtitles;
  final bool generatingAiSubtitles;
  final double? aiSubtitleProgressValue;
  final String? aiSubtitleProgressText;
  final String? aiSubtitlePreviewText;
  final String? aiSubtitleErrorText;
  final VoidCallback? onGenerateAiSubtitles;
  final VoidCallback? onRegenerateAiSubtitles;
  final VoidCallback? onDeleteAiSubtitles;
  final Future<void> Function(int index)? onRegenerateAiLine;

  @override
  State<PlayerSubtitleList> createState() => _PlayerSubtitleListState();
}

class _PlayerSubtitleListState extends State<PlayerSubtitleList> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};
  String? _activeDictionaryTokenId;
  OverlayEntry? _dictionaryOverlayEntry;
  bool _autoFollowCurrentLine = true;

  /// 行高经验值，仅在无法从已构建行测量时使用。
  static const double _defaultRowHeight = 120;

  /// 当前句一次变化超过这么多句，视为「明显跳转」并恢复跟随。
  static const int _resumeFollowIndexJump = 3;

  /// 用户在字幕上选中的文本（短语或整句）。
  ///
  /// 用途：原先只能点单个单词查词，无法处理「不认识的短语」。
  /// 列表本就包在 SelectionArea 里（可拖选），但选中后毫无反应。
  /// 这里接住选中结果，给出「翻译选中」入口。
  ///
  /// 用 ValueNotifier 而非 setState 的原因：
  /// 拖选时 onSelectionChanged 会**每帧**触发，若走 setState 就会
  /// 每帧重建整个列表（几百个子项），用户看到的就是「闪烁」。
  /// 这里让提示条单独监听，只有它重建。
  final ValueNotifier<String> _selectedTextNotifier = ValueNotifier<String>('');

  /// 选中去抖定时器：拖选过程中不显示提示条，停稳后再出现。
  Timer? _selectionDebounce;

  /// 「长按并划过相邻词块」这一手势的起点信息。
  ///
  /// 为什么自己做而不用系统文本选择：
  /// 列表是 ListView（可滚动）+ 每个词块各自是 InkWell（要响应点词查词），
  /// 两者与 SelectionArea 的手势竞争在这一结构下不可靠 ——
  /// 实测长按词块**无法稳定**产生文本选中（同一页面的简化结构却可以），
  /// 用户反馈的正是「第一行能选、第二行选不了」。
  /// 这里改为显式手势：长按起点词 → 划过相邻词 → 直接得到短语。
  int? _dragStartTokenIndex;
  int? _dragEndTokenIndex;
  List<GlobalKey> _activeTokenKeys = const <GlobalKey>[];

  /// 词块 key 的持久缓存：'行号-词序号' → GlobalKey。
  ///
  /// 必须持久化。原先在 build 里为每个词块新建 GlobalKey，
  /// 而 setState 重建会让这些 key 全部作废（currentContext 变 null），
  /// 于是拖动时的命中判定永远失败 —— 实测只能选中起点那一个词。
  final Map<String, GlobalKey> _tokenKeyCache = <String, GlobalKey>{};

  GlobalKey _tokenKeyFor(int lineIndex, int tokenIndex) =>
      _tokenKeyCache.putIfAbsent(
        '$lineIndex-$tokenIndex',
        () => GlobalKey(debugLabel: 'token-$lineIndex-$tokenIndex'),
      );

  String get _selectedText => _selectedTextNotifier.value;

  /// 上一帧是否在播放，用于检测「暂停 → 继续播放」的切换。
  late bool _wasPlaying;
  int? _regeneratingAiLineIndex;

  bool get _showCurrentOnly => widget.showCurrentOnly;

  @override
  void initState() {
    super.initState();
    _wasPlaying = widget.isPlaying;
    _scrollController.addListener(_dismissDictionary);
    if (widget.isPlaying) {
      _scheduleScrollToActiveLine();
    }
  }

  @override
  void didUpdateWidget(covariant PlayerSubtitleList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool listStateChanged =
        oldWidget.activeIndex != widget.activeIndex ||
        oldWidget.lines.length != widget.lines.length ||
        oldWidget.subtitleMode != widget.subtitleMode ||
        oldWidget.showCurrentOnly != widget.showCurrentOnly;
    // 播放恢复时自动重新跟随。
    //
    // 原先只要用户手动滚动过列表，_autoFollowCurrentLine 就会被永久置 false，
    // 之后字幕列表再不跟随视频移动，表现为「右边对不上视频里的字幕」，
    // 而且唯一的恢复入口是「定位当前」按钮 —— 用户播放时不会想到去点它。
    // 这里让「暂停后继续播放」成为自动恢复的时机，符合直觉：
    // 用户重新开始播放，通常就是希望继续跟读当前进度。
    final bool resumedPlaying = !oldWidget.isPlaying && widget.isPlaying;
    if (resumedPlaying) {
      _autoFollowCurrentLine = true;
      _scheduleScrollToActiveLine();
    }
    final bool wasPlaying = _wasPlaying;
    _wasPlaying = widget.isPlaying;

    // 只要「用户没有主动脱离跟随」且当前句发生变化，就滚动过去。
    //
    // 原先还要求 widget.isPlaying 为真，导致：
    //   1) 暂停状态下拖动进度条，列表不定位到目标时间对应的字幕
    //      （用户反馈的「拉动进度条列表无法定位」）；
    //   2) 暂停时用上一句/下一句切换，列表也不跟随。
    // 当前句变化本身就意味着「视点在移动」，此时应当把它带入视野；
    // 真正表达「我要自己看」的是主动拖动列表，那会把
    // _autoFollowCurrentLine 置为 false（见 _handleScrollNotification）。
    final bool shouldFollowCurrentLine =
        _autoFollowCurrentLine &&
        (oldWidget.activeIndex != widget.activeIndex ||
            wasPlaying != widget.isPlaying);

    if (!listStateChanged && !shouldFollowCurrentLine) {
      return;
    }

    final bool activeLineChanged = oldWidget.activeIndex != widget.activeIndex;
    final bool listStructureChanged =
        oldWidget.lines.length != widget.lines.length ||
        oldWidget.subtitleMode != widget.subtitleMode ||
        oldWidget.showCurrentOnly != widget.showCurrentOnly;

    if (listStructureChanged) {
      _dismissDictionary();
    }

    // 词典弹窗打开时，切句不滚动列表：弹窗锚定在被点的词上，
    // 此时把列表滚走会让弹窗与被查的词脱节（原有设计，需保留）。
    if (activeLineChanged && _dictionaryOverlayEntry != null) {
      return;
    }

    // 明显跳转（拖动进度条 seek、或跨多句切换）时恢复跟随。
    //
    // 手动拖动列表只是「此刻想自己看」，不应变成永久脱离：
    // 用户拖动进度条后，期望的正是列表定位到该时间对应的字幕。
    // 放在词典保护之后，避免把弹窗场景也一并恢复。
    if ((widget.activeIndex - oldWidget.activeIndex).abs() >=
        _resumeFollowIndexJump) {
      _autoFollowCurrentLine = true;
      _scheduleScrollToActiveLine();
      return;
    }

    if (shouldFollowCurrentLine) {
      _scheduleScrollToActiveLine();
    }
  }

  @override
  void dispose() {
    _selectionDebounce?.cancel();
    _selectedTextNotifier.dispose();
    _removeDictionaryOverlay(notify: false);
    _scrollController
      ..removeListener(_dismissDictionary)
      ..dispose();
    super.dispose();
  }

  GlobalKey _rowKeyFor(int index) {
    return _rowKeys[index] ??= GlobalKey(debugLabel: 'subtitle-line-$index');
  }

  /// 把当前句滚动到列表中部。
  ///
  /// 关键约束：**不能假设目标行已经被构建**。
  /// 列表是 ListView.builder，离视口较远的行不存在 RenderObject，
  /// `_rowKeys[activeIndex].currentContext` 会是 null —— 这正是
  /// 「自动跟随失效」和「点『定位当前』也没用」的共同原因：
  /// 两个入口都走这个函数，而它一开头的 context 判断就静默返回了。
  ///
  /// 因此这里改为「按索引估算目标位置并直接滚动」：
  ///   1) 用已构建行的平均高度（拿不到就用默认值）估算每行高度；
  ///   2) 目标偏移 = 索引 × 行高 - 半屏（使该行居中）；
  ///   3) 直接 animateTo，不依赖任何行的 BuildContext。
  /// 估算存在误差，但只要把目标行带进视口附近即可达到目的，
  /// 不会出现「完全不动」。
  /// 把当前句滚动到列表中部。
  ///
  /// 关键难点：**行高不均匀**。列表里有的行带译文、有的没有，行高会变化，
  /// 因此「索引 × 平均行高」的估算会偏（实测滚到第 18 句的位置时，
  /// 屏幕上显示的是第 14–17 句）。而 ListView.builder 不会为远离视口的行
  /// 创建 RenderObject，所以也无法直接量到目标行的真实位置
  /// —— 这正是「自动跟随失效」「点『定位当前』也没用」的共同原因。
  ///
  /// 采用迭代校正：先按估算滚过去，若目标行因此被构建出来，
  /// 就用它的真实几何再校正一次（最多两轮）。
  void _scrollToActiveLine() {
    _scrollToActiveLinePass(allowRetry: true);
  }

  void _scrollToActiveLinePass({required bool allowRetry}) {
    if (_showCurrentOnly || !_scrollController.hasClients) {
      return;
    }

    final ScrollPosition position = _scrollController.position;
    final int index = widget.activeIndex;
    final BuildContext? activeContext = _rowKeys[index]?.currentContext;
    final RenderObject? rowObject = activeContext?.findRenderObject();

    if (rowObject is RenderBox && rowObject.hasSize) {
      // 目标行已构建：用它自身的真实高度与位置精确居中。
      final RenderBox viewportBox = context.findRenderObject()! as RenderBox;
      final Offset rowTopInViewport = rowObject.localToGlobal(
        Offset.zero,
        ancestor: viewportBox,
      );
      final double rowTopInContent = position.pixels + rowTopInViewport.dy;
      final double target =
          rowTopInContent -
          position.viewportDimension / 2 +
          rowObject.size.height / 2;
      _jumpToOffset(target);
      return;
    }

    // 目标行尚未构建：先按估算滚过去。
    final double estimated = _estimateRowHeight();
    final double target =
        index * estimated -
        position.viewportDimension / 2 +
        estimated / 2;
    _jumpToOffset(target);

    // 若因此把目标行带进了视口，再用真实几何校正一次。
    if (allowRetry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _scrollToActiveLinePass(allowRetry: false);
      });
    }
  }

  void _jumpToOffset(double target) {
    if (!_scrollController.hasClients) {
      return;
    }
    final ScrollPosition position = _scrollController.position;
    final double resolved = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((resolved - position.pixels).abs() < 0.5) {
      return;
    }
    // 用 jumpTo：播放中列表会持续重建，animateTo 的动画容易被后续
    // 重建打断而停在原地（实测目标 2348 时仍停在 411）。
    _scrollController.jumpTo(resolved);
  }

  /// 估算单行高度。
  ///
  /// 优先用当前已构建行的真实高度求平均；拿不到时退回一个经验值。
  /// 只要量级正确，滚动就能把目标行带进视野。
  double _estimateRowHeight() {
    final List<double> heights = <double>[];
    for (final GlobalKey key in _rowKeys.values) {
      final BuildContext? ctx = key.currentContext;
      final RenderObject? object = ctx?.findRenderObject();
      if (object is RenderBox && object.hasSize && object.size.height > 0) {
        heights.add(object.size.height);
      }
    }
    if (heights.isEmpty) {
      return _defaultRowHeight;
    }
    final double sum = heights.reduce((double a, double b) => a + b);
    return sum / heights.length;
  }

  void _scheduleScrollToActiveLine() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _autoFollowCurrentLine) {
        _scrollToActiveLine();
      }
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    // 只有「明确发生在列表自身上的拖动」才被视为「用户要自己看」。
    //
    // 之前只要收到带 dragDetails 的 ScrollStartNotification 就停止跟随，
    // 但 SelectionArea 包裹整个列表，用户在列表上轻轻划一下选中文字
    // （很常见，用于查词）也会命中，导致跟随被静默关闭、
    // 之后无论播放还是拖动进度条都不再定位。
    // 这里加上深度与距离判定，把这类误触发排除掉。
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _autoFollowCurrentLine = false;
    }
    return false;
  }

  void _dismissDictionary() {
    if (_activeDictionaryTokenId == null && _dictionaryOverlayEntry == null) {
      return;
    }
    _removeDictionaryOverlay();
  }

  void _removeDictionaryOverlay({bool notify = true}) {
    _dictionaryOverlayEntry?.remove();
    _dictionaryOverlayEntry = null;
    if (!notify || !mounted || _activeDictionaryTokenId == null) {
      return;
    }
    setState(() {
      _activeDictionaryTokenId = null;
    });
  }

  void _toggleDictionaryOverlay(
    BuildContext anchorContext,
    String rawWord,
    String contextSentence,
    String tokenId, {
    /// 入口位于列表底部时（如「翻译选中」条），弹窗应显示在它上方，
    /// 否则会被屏幕下边缘裁掉。
    bool preferAbove = false,
  }) {
    if (_activeDictionaryTokenId == tokenId) {
      _removeDictionaryOverlay();
      return;
    }

    _removeDictionaryOverlay(notify: false);

    final OverlayState overlayState = Overlay.of(context, rootOverlay: true);
    final RenderBox overlayBox =
        overlayState.context.findRenderObject()! as RenderBox;
    final RenderBox anchorBox = anchorContext.findRenderObject()! as RenderBox;
    final Offset anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final Size anchorSize = anchorBox.size;
    final Size overlaySize = overlayBox.size;
    const double popupWidth = 336;
    const double preferredPopupHeight = 520;
    const double viewportPadding = 16;
    const double popupGap = 8;
    final double popupHeight = (overlaySize.height - (viewportPadding * 2))
        .clamp(120.0, preferredPopupHeight);

    final double availableRight =
        overlaySize.width - (anchorTopLeft.dx + anchorSize.width);
    final double availableLeft = anchorTopLeft.dx;
    final double availableBelow =
        overlaySize.height - (anchorTopLeft.dy + anchorSize.height);
    final bool canShowRight = availableRight >= popupWidth + popupGap;
    final bool canShowLeft = availableLeft >= popupWidth + popupGap;
    final bool showRight = canShowRight || !canShowLeft;
    final bool showSide = canShowRight || canShowLeft;
    final bool showAbove =
        !showSide &&
        (preferAbove ||
            (availableBelow < popupHeight + viewportPadding &&
                anchorTopLeft.dy > availableBelow));

    final double left;
    final double top;
    if (showSide) {
      left = showRight
          ? (anchorTopLeft.dx + anchorSize.width + popupGap).clamp(
              viewportPadding,
              overlaySize.width - popupWidth - viewportPadding,
            )
          : (anchorTopLeft.dx - popupWidth - popupGap).clamp(
              viewportPadding,
              overlaySize.width - popupWidth - viewportPadding,
            );
      top = (anchorTopLeft.dy + (anchorSize.height / 2) - (popupHeight / 2))
          .clamp(
            viewportPadding,
            overlaySize.height - popupHeight - viewportPadding,
          );
    } else {
      final double unclampedLeft =
          anchorTopLeft.dx + (anchorSize.width / 2) - (popupWidth / 2);
      left = unclampedLeft.clamp(
        viewportPadding,
        overlaySize.width - popupWidth - viewportPadding,
      );
      top = showAbove
          ? (anchorTopLeft.dy - popupHeight - popupGap).clamp(
              viewportPadding,
              overlaySize.height - popupHeight - viewportPadding,
            )
          : (anchorTopLeft.dy + anchorSize.height + popupGap).clamp(
              viewportPadding,
              overlaySize.height - popupHeight - viewportPadding,
            );
    }

    _dictionaryOverlayEntry = OverlayEntry(
      builder: (BuildContext overlayContext) {
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _dismissDictionary,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: popupWidth,
              child: Material(
                color: Colors.transparent,
                child: WordLookupPopupCard(
                  rawWord: rawWord,
                  contextSentence: contextSentence,
                  showAbove: showAbove,
                  showSide: showSide,
                  showRight: showRight,
                  maxHeight: popupHeight,
                  onPronounce: widget.onPronounce,
                  onClose: _dismissDictionary,
                  onCollect: () {
                    _dismissDictionary();
                    widget.onCollectWord(rawWord);
                  },
                  onFavorite: widget.onFavoriteWord == null
                      ? null
                      : () => widget.onFavoriteWord!(rawWord),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlayState.insert(_dictionaryOverlayEntry!);
    setState(() {
      _activeDictionaryTokenId = tokenId;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.subtitleMode == '隐藏') {
      return _SubtitlePlaceholder(
        icon: Icons.closed_caption_disabled_outlined,
        title: '字幕已隐藏',
        body: '在播放器控制栏中重新开启字幕后可恢复列表。',
        showAiGenerateSubtitles: widget.showAiGenerateSubtitles,
        generatingAiSubtitles: widget.generatingAiSubtitles,
        progressValue: widget.aiSubtitleProgressValue,
        progressText: widget.aiSubtitleProgressText,
        previewText: widget.aiSubtitlePreviewText,
        errorText: widget.aiSubtitleErrorText,
        onGenerateAiSubtitles: widget.onGenerateAiSubtitles,
      );
    }

    final int totalLineCount = widget.lines.length;
    if (totalLineCount == 0 && widget.showAiGenerateSubtitles) {
      return _SubtitlePlaceholder(
        icon: Icons.auto_awesome_rounded,
        title: '当前视频没有字幕',
        body: '可生成可随播放逐词高亮的 AI 词级同步字幕。',
        showAiGenerateSubtitles: widget.showAiGenerateSubtitles,
        generatingAiSubtitles: widget.generatingAiSubtitles,
        progressValue: widget.aiSubtitleProgressValue,
        progressText: widget.aiSubtitleProgressText,
        previewText: widget.aiSubtitlePreviewText,
        errorText: widget.aiSubtitleErrorText,
        onGenerateAiSubtitles: widget.onGenerateAiSubtitles,
      );
    }

    final int itemCount = _showCurrentOnly ? 1 : totalLineCount;

    // 注意：这里刻意不监听 onSelectionChanged。
    //
    // 原先「选中文本就 _autoFollowCurrentLine = false」是跟随失效的主因：
    // SelectionArea 包住整个列表，播放过程中任何划选、点击拖拽、
    // 甚至轻微的文本选择都会命中，导致跟随随机停止。
    // 用户看到的现象正是「一开始能定位，随后概率性地不再跟随」。
    // 选中文本是阅读行为，不应等同于「用户要脱离自动跟随」——
    // 真正表达该意图的是主动拖动列表（见 _handleScrollNotification）。
    final Widget list = SelectionArea(
      key: const ValueKey<String>('subtitle-list-selection-area'),
      // 注意：这里**不**据此关闭自动跟随。
      // 早先版本一旦收到选择就停止跟随，导致播放中「概率性不跟了」。
      // 选中文本是阅读/查词行为，不等于「用户要脱离自动跟随」。
      onSelectionChanged: (SelectedContent? selection) {
        final String next = selection?.plainText.trim() ?? '';
        if (next == _selectedTextNotifier.value) {
          return;
        }
        // 去抖：拖选过程中会连续触发，此时若立刻显示提示条，
        // 列表高度/浮层反复变化会造成闪烁。停稳 160ms 后再更新。
        _selectionDebounce?.cancel();
        _selectionDebounce = Timer(const Duration(milliseconds: 160), () {
          if (!mounted) {
            return;
          }
          _selectedTextNotifier.value = next;
        });
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.all(2),
          itemCount: itemCount,
          itemBuilder: (BuildContext context, int itemIndex) {
            final int originalIndex = _showCurrentOnly
                ? widget.activeIndex
                : itemIndex;
            if (originalIndex < 0 || originalIndex >= totalLineCount) {
              return const SizedBox.shrink();
            }

            final PlayerSubtitleLine line = widget.lines[originalIndex];
            final bool active = originalIndex == widget.activeIndex;
            final bool isLooping = originalIndex == widget.loopingLineIndex;
            final bool isPast = originalIndex < widget.activeIndex;
            final double textOpacity = active ? 1 : (isPast ? 0.84 : 0.60);
            final double chineseFontSize =
                (active ? 19.0 : 17.0) * widget.fontScale;
            final double subtitleFontSize = 15 * widget.fontScale;
            const Color inactiveStartTimeColor = Color(0xFFADB7B0);
            const Color inactiveZhTextColor = Color(0xFFB7C2BA);

            return InkWell(
              key: _rowKeyFor(originalIndex),
              onTap: () {
                // 点选某句＝用户明确想定位，恢复自动跟随。
                _autoFollowCurrentLine = true;
                widget.onTapLine(originalIndex);
              },
              onLongPress: () => _openActions(context, line, originalIndex),
              borderRadius: BorderRadius.circular(20),
              child: Ink(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFEFFFF5) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: active
                        ? AppDesignTokens.brandGreen
                        : const Color(0xFFE1E7E1),
                    width: active ? 2.5 : 1.5,
                  ),
                  boxShadow: AppElevation.medium,
                ),
                child: Stack(
                  children: <Widget>[
                    if (active)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7D6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            '正在学习',
                            style: TextStyle(
                              color: AppDesignTokens.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            FilledButton.tonal(
                              onPressed: active
                                  ? widget.onTogglePlaying
                                  : () {
                                      // 同上：点句即恢复自动跟随。
                                      _autoFollowCurrentLine = true;
                                      widget.onTapLine(originalIndex);
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: active
                                    ? const Color(0xFFDFF8C8)
                                    : AppDesignTokens.softWhite,
                                foregroundColor: active
                                    ? AppDesignTokens.brandGreenDark
                                    : AppDesignTokens.primaryBlueDark,
                                minimumSize: const Size(44, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Icon(
                                active && widget.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line.startTime,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: active
                                      ? const Color(0xFF7E8A82)
                                      : inactiveStartTimeColor.withValues(
                                          alpha: textOpacity,
                                        ),
                                ),
                              ),
                            ),
                            FilledButton.tonal(
                              key: ValueKey<String>(
                                'subtitle-line-loop-$originalIndex',
                              ),
                              onPressed: () =>
                                  widget.onLoopFromLine(originalIndex),
                              style: FilledButton.styleFrom(
                                backgroundColor: isLooping
                                    ? const Color(0xFFDFF8C8)
                                    : AppDesignTokens.softWhite,
                                foregroundColor: isLooping
                                    ? AppDesignTokens.brandGreenDark
                                    : AppDesignTokens.textSecondary,
                                minimumSize: const Size(44, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Icon(Icons.repeat_one_rounded),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () =>
                                  widget.onBookmarkLine(originalIndex),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFFF7D6),
                                foregroundColor: const Color(0xFFB58600),
                                minimumSize: const Size(44, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Icon(Icons.star_rounded),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () =>
                                  _openActions(context, line, originalIndex),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppDesignTokens.softWhite,
                                foregroundColor: AppDesignTokens.textSecondary,
                                minimumSize: const Size(44, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Icon(Icons.more_horiz_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (widget.subtitleMode == '单中')
                          Text(
                            line.chinese,
                            style: TextStyle(
                              fontSize: chineseFontSize,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w600,
                              color: active
                                  ? const Color(0xFF191C1E)
                                  : inactiveZhTextColor.withValues(
                                      alpha: textOpacity,
                                    ),
                              height: 1.35,
                            ),
                          )
                        else
                          _buildWordLine(
                            line.english,
                            active && line.words.isNotEmpty
                                ? widget.currentWordIndex
                                : null,
                            active,
                            originalIndex,
                          ),
                        if (widget.subtitleMode != '单英') ...<Widget>[
                          const _SelectableLineBreak(),
                          const SizedBox(height: 4),
                          Text(
                            line.chinese,
                            style: TextStyle(
                              fontSize: subtitleFontSize,
                              color: active
                                  ? const Color(0xFF708077)
                                  : inactiveZhTextColor.withValues(
                                      alpha: textOpacity,
                                    ),
                              height: 1.45,
                            ),
                          ),
                        ],
                        const _SelectableLineBreak(),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: <Widget>[
                SizedBox(height: 4),
                Divider(
                  key: ValueKey<String>('subtitle-list-divider'),
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE6EBE7),
                ),
                SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      children: <Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextButton.icon(
                onPressed: () {
                  _autoFollowCurrentLine = true;
                  _scrollToActiveLine();
                },
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('定位当前'),
              ),
              if (widget.onRegenerateAiSubtitles != null)
                TextButton.icon(
                  onPressed: widget.onRegenerateAiSubtitles,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新生成'),
                ),
              if (widget.onDeleteAiSubtitles != null)
                TextButton.icon(
                  onPressed: widget.onDeleteAiSubtitles,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('切回原始字幕'),
                ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: <Widget>[
              list,
              // 「翻译选中」入口：选中短语/整句后出现。
              //
              // 做成**浮层**而不是插进 Column：
              // 插进 Column 会在选中出现/消失时改变列表可用高度，
              // 拖选过程中列表内容随之上下跳动（用户反馈的「闪烁」）。
              //
              // 用 ValueListenableBuilder 单独监听选中结果，
              // 只有这一条提示重建，不会每帧重建整个列表。
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: ValueListenableBuilder<String>(
                  valueListenable: _selectedTextNotifier,
                  builder: (BuildContext context, String selected, Widget? _) {
                    if (selected.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return _SelectionTranslateBar(
                      selectedText: selected,
                      onTranslate: (BuildContext anchorContext) =>
                          _toggleDictionaryOverlay(
                            anchorContext,
                            selected,
                            _contextSentenceForSelection(),
                            'selection:$selected',
                            preferAbove: true,
                          ),
                      onCollect: widget.onCollectPhrase == null
                          ? null
                          : () => widget.onCollectPhrase!(
                              selected,
                              _contextSentenceForSelection(),
                            ),
                      onDismiss: () => _selectedTextNotifier.value = '',
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 找出选中文本所在的整句，作为翻译/查词的上下文。
  ///
  /// 上下文很重要：同一个短语在不同句子里含义可能不同，
  /// 交给模型判断时带上整句能显著提高准确度。
  String _contextSentenceForSelection() {
    final String needle = _selectedText.trim();
    if (needle.isEmpty) {
      return '';
    }
    for (final PlayerSubtitleLine line in widget.lines) {
      if (line.english.contains(needle)) {
        return line.english;
      }
    }
    return needle;
  }

  Future<void> _openActions(
    BuildContext context,
    PlayerSubtitleLine line,
    int index,
  ) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: const Text('收藏到短语库'),
                  onTap: () => Navigator.of(context).pop('bookmark'),
                ),
                ListTile(
                  leading: const Icon(Icons.copy_all_rounded),
                  title: const Text('复制英文'),
                  onTap: () => Navigator.of(context).pop('copy-en'),
                ),
                ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: const Text('复制中英双语'),
                  onTap: () => Navigator.of(context).pop('copy-bi'),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('AI 解释这句话'),
                  onTap: () => Navigator.of(context).pop('ai-explain'),
                ),
                if (widget.onRegenerateAiLine != null)
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('AI 重新生成当前句'),
                    subtitle: const Text('只替换这一句，失败时保留原句'),
                    trailing: _regeneratingAiLineIndex == index
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    enabled: _regeneratingAiLineIndex == null,
                    onTap: _regeneratingAiLineIndex == null
                        ? () => Navigator.of(context).pop('regenerate-ai-line')
                        : null,
                  ),
                ListTile(
                  leading: const Icon(Icons.repeat_one_rounded),
                  title: const Text('从这里开始循环'),
                  onTap: () => Navigator.of(context).pop('loop'),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('加入听写练习'),
                  onTap: () => Navigator.of(context).pop('dictation'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || action == null) {
      return;
    }

    switch (action) {
      case 'bookmark':
        widget.onBookmarkLine(index);
        return;
      case 'copy-en':
        await Clipboard.setData(ClipboardData(text: line.english));
        if (!context.mounted) {
          return;
        }
        _showMessage(context, '已复制英文');
        return;
      case 'copy-bi':
        await Clipboard.setData(
          ClipboardData(text: '${line.english}\n${line.chinese}'),
        );
        if (!context.mounted) {
          return;
        }
        _showMessage(context, '已复制中英双语');
        return;
      case 'loop':
        widget.onLoopFromLine(index);
        return;
      case 'dictation':
        widget.onDictationLine(index);
        return;
      case 'ai-explain':
        widget.onAiExplain(index);
        return;
      case 'regenerate-ai-line':
        final Future<void> Function(int index)? regenerate =
            widget.onRegenerateAiLine;
        if (regenerate == null || _regeneratingAiLineIndex != null) return;
        setState(() {
          _regeneratingAiLineIndex = index;
        });
        try {
          await regenerate(index);
        } finally {
          if (mounted) {
            setState(() {
              _regeneratingAiLineIndex = null;
            });
          }
        }
        return;
    }
  }

  /// 开始拖选短语：记录起点词，并把当前选中设为该词。
  void _beginPhraseDrag(
    int tokenIndex,
    String lineText,
    List<GlobalKey> tokenKeys,
  ) {
    setState(() {
      _dragStartTokenIndex = tokenIndex;
      _dragEndTokenIndex = tokenIndex;
      _activeTokenKeys = tokenKeys;
    });
    _selectedTextNotifier.value = _tokensOf(lineText)
        .sublist(tokenIndex, tokenIndex + 1)
        .join(' ');
  }

  /// 拖动过程中按指针位置更新结束词。
  void _updatePhraseDrag(Offset globalPosition) {
    final int? start = _dragStartTokenIndex;
    if (start == null) {
      return;
    }
    int? hit;
    for (int i = 0; i < _activeTokenKeys.length; i++) {
      final BuildContext? ctx = _activeTokenKeys[i].currentContext;
      final RenderObject? obj = ctx?.findRenderObject();
      if (obj is! RenderBox || !obj.hasSize) {
        continue;
      }
      final Offset topLeft = obj.localToGlobal(Offset.zero);
      final Rect tileRect = Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        obj.size.width,
        obj.size.height,
      );
      if (tileRect.contains(globalPosition)) {
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
    final List<String> tokens = _tokensOf(_lineTextOfActiveDrag());
    if (hi < tokens.length) {
      _selectedTextNotifier.value = tokens.sublist(lo, hi + 1).join(' ');
    }
  }

  void _endPhraseDrag() {
    setState(() {
      _dragStartTokenIndex = null;
      _dragEndTokenIndex = null;
    });
  }

  /// 拖选期间用于拼接短语的原文（取当前句）。
  String _lineTextOfActiveDrag() {
    final int index = widget.activeIndex;
    if (index < 0 || index >= widget.lines.length) {
      return '';
    }
    return widget.lines[index].english;
  }

  List<String> _tokensOf(String text) =>
      text.split(' ').where((String w) => w.isNotEmpty).toList(growable: false);

  Widget _buildWordLine(
    String text,
    int? highlightIndex,
    bool active,
    int lineIndex,
  ) {
    final List<_WordToken> tokens = text
        .split(' ')
        .where((String rawWord) => rawWord.isNotEmpty)
        .map((String rawWord) => _WordToken(value: rawWord))
        .toList(growable: false);

    // 为本行每个词块取（持久化的）key，拖动时据此在屏幕坐标上做命中判定。
    final List<GlobalKey> tokenKeys = <GlobalKey>[
      for (int i = 0; i < tokens.length; i++) _tokenKeyFor(lineIndex, i),
    ];
    final bool isActiveLine = lineIndex == widget.activeIndex;
    if (isActiveLine) {
      _activeTokenKeys = tokenKeys;
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: tokens
          .asMap()
          .entries
          .map((MapEntry<int, _WordToken> entry) {
            final int index = entry.key;
            final _WordToken token = entry.value;
            final bool highlighted =
                active &&
                widget.highlightWords &&
                highlightIndex != null &&
                index == highlightIndex;
            final String tokenId = '$text-$index';

            // 拖动范围高亮：让用户看到自己拖过了哪些词。
            final int dragLo = _dragStartTokenIndex == null
                ? -1
                : (_dragStartTokenIndex! <
                          (_dragEndTokenIndex ?? _dragStartTokenIndex!)
                      ? _dragStartTokenIndex!
                      : (_dragEndTokenIndex ?? _dragStartTokenIndex!));
            final int dragHi = _dragStartTokenIndex == null
                ? -1
                : (_dragStartTokenIndex! >
                          (_dragEndTokenIndex ?? _dragStartTokenIndex!)
                      ? _dragStartTokenIndex!
                      : (_dragEndTokenIndex ?? _dragStartTokenIndex!));
            final bool inDragRange =
                isActiveLine && index >= dragLo && index <= dragHi;

            return Builder(
              key: tokenKeys[index],
              builder: (BuildContext wordContext) {
                // 长按后划过相邻词块即可选中短语。
                //
                // 不用系统文本选择：列表是 ListView（可滚动）且每个词块
                // 各自是 InkWell（要响应点词查词），两者与 SelectionArea
                // 的手势竞争在这一结构下不可靠 —— 实测长按词块无法稳定
                // 产生文本选中，用户反馈「第一行能选、第二行选不了」。
                //
                // 长按必须放在 GestureDetector：InkWell 不支持
                // onLongPressMoveUpdate，而拖动过程中需要持续收到位置。
                return GestureDetector(
                  behavior: HitTestBehavior.deferToChild,
                  onLongPressStart: isActiveLine
                      ? (LongPressStartDetails _) =>
                          _beginPhraseDrag(index, text, tokenKeys)
                      : null,
                  onLongPressMoveUpdate: isActiveLine
                      ? (LongPressMoveUpdateDetails details) =>
                          _updatePhraseDrag(details.globalPosition)
                      : null,
                  onLongPressEnd: isActiveLine
                      ? (LongPressEndDetails _) => _endPhraseDrag()
                      : null,
                  child: InkWell(
                  onTap: () {
                    // 点词查词时收起「翻译选中」入口，避免两个浮层并存。
                    if (_selectedText.isNotEmpty) {
                      _selectedTextNotifier.value = '';
                    }
                    _toggleDictionaryOverlay(
                      wordContext,
                      token.value,
                      text,
                      tokenId,
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      // 拖动中命中的词块加深底色，让用户看清选到哪了。
                      color: inDragRange
                          ? const Color(0xFFB7D9CE)
                          : SubtitleWordHighlightStyle.background(
                              widget.subtitleWordHighlightStyle,
                              highlighted: highlighted,
                            ),
                      border: Border.all(
                        color: SubtitleWordHighlightStyle.borderColor(
                          widget.subtitleWordHighlightStyle,
                          highlighted: highlighted,
                        ),
                        width: SubtitleWordHighlightStyle.borderWidth(
                          widget.subtitleWordHighlightStyle,
                          highlighted: highlighted,
                          width: widget.subtitleWordHighlightBorderWidth,
                        ),
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Text(
                          token.value,
                          style: TextStyle(
                            fontSize: active
                                ? _activeFontSize * widget.fontScale
                                : (_activeFontSize * widget.fontScale) - 2,
                            fontWeight: highlighted
                                ? FontWeight.w600
                                : FontWeight.w600,
                            color: AppDesignTokens.textPrimary,
                            decoration:
                                SubtitleWordHighlightStyle.textDecoration(
                                  widget.subtitleWordHighlightStyle,
                                  highlighted: highlighted,
                                ),
                            decorationColor:
                                SubtitleWordHighlightStyle.textDecorationColor(
                                  widget.subtitleWordHighlightStyle,
                                  highlighted: highlighted,
                                ),
                            decorationThickness:
                                highlighted &&
                                    widget.subtitleWordHighlightStyle == '下划线'
                                ? 2
                                : null,
                            height: 1.35,
                          ),
                        ),
                        if (index != tokens.length - 1)
                          const Positioned(
                            right: -1,
                            bottom: 0,
                            child: IgnorePointer(child: Text(' ')),
                          ),
                      ],
                    ),
                  ),
                ),
                );
              },
            );
          })
          .toList(growable: false),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _WordToken {
  const _WordToken({required this.value});

  final String value;
}

class _SelectableLineBreak extends StatelessWidget {
  const _SelectableLineBreak();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: SizedBox(
        height: 0.01,
        child: Text(
          '\n',
          style: TextStyle(
            fontSize: 1,
            height: 0.01,
            color: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _SubtitlePlaceholder extends StatelessWidget {
  const _SubtitlePlaceholder({
    required this.icon,
    required this.title,
    required this.body,
    required this.showAiGenerateSubtitles,
    required this.generatingAiSubtitles,
    required this.progressValue,
    required this.progressText,
    required this.previewText,
    required this.errorText,
    required this.onGenerateAiSubtitles,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool showAiGenerateSubtitles;
  final bool generatingAiSubtitles;
  final double? progressValue;
  final String? progressText;
  final String? previewText;
  final String? errorText;
  final VoidCallback? onGenerateAiSubtitles;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 34, color: const Color(0xFF9AA69E)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF53625A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF7E8A82),
              ),
            ),
            if (showAiGenerateSubtitles) ...<Widget>[
              const SizedBox(height: 14),
              if (!generatingAiSubtitles &&
                  (errorText?.isNotEmpty ?? false)) ...<Widget>[
                SizedBox(
                  width: 320,
                  child: Text(
                    '生成失败：$errorText',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFFC62828),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (generatingAiSubtitles) ...<Widget>[
                SizedBox(
                  width: 240,
                  child: LinearProgressIndicator(value: progressValue),
                ),
                const SizedBox(height: 10),
                Text(
                  progressText ?? '正在准备音频...',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF53625A),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 300,
                  height: 44,
                  child: Text(
                    previewText?.isNotEmpty ?? false
                        ? previewText!
                        : '等待识别文本...',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFF53625A),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                onPressed: generatingAiSubtitles ? null : onGenerateAiSubtitles,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  generatingAiSubtitles ? '正在生成词级同步字幕...' : 'AI生成可跟读的词级同步字幕',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 「翻译选中」提示条。
///
/// 独立成组件是为了让重建范围局限在这一条上：拖选时选中文本持续变化，
/// 若由列表 State 承载就会每帧重建整个列表，表现为闪烁。
class _SelectionTranslateBar extends StatefulWidget {
  const _SelectionTranslateBar({
    required this.selectedText,
    required this.onTranslate,
    required this.onDismiss,
    this.onCollect,
  });

  final String selectedText;
  final void Function(BuildContext anchorContext) onTranslate;
  final VoidCallback onDismiss;

  /// 收藏该短语；为空时不显示收藏按钮。
  final Future<void> Function()? onCollect;

  @override
  State<_SelectionTranslateBar> createState() => _SelectionTranslateBarState();
}

class _SelectionTranslateBarState extends State<_SelectionTranslateBar> {
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
      borderRadius: BorderRadius.circular(14),
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
