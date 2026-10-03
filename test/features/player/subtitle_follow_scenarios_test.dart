/// 字幕列表跟随视频的两个真实场景。
///
/// 用户反馈：
///   1) 拖动进度条后，列表不定位到该时间对应的字幕；
///   2) 播放中「一开始能定位，随后概率性出现当前句不在视野里」。
///
/// 根因分别是：
///   1) 跟随条件里带了 `widget.isPlaying`，暂停拖进度条时不跟随；
///   2) SelectionArea 的 onSelectionChanged 一旦有选中文本就把跟随关掉，
///      而它包住整个列表，播放中任何划选/点击拖拽都会命中。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/player/presentation/widgets/player_subtitle_list.dart';

List<PlayerSubtitleLine> manyLines(int count) {
  return List<PlayerSubtitleLine>.generate(
    count,
    (int i) => PlayerSubtitleLine(
      startTime: '00:${i.toString().padLeft(2, '0')}',
      english: 'line $i english text here',
      chinese: '第 $i 句中文内容',
      startMs: i * 5000,
      endMs: i * 5000 + 4000,
    ),
  );
}

Widget page({
  required int activeIndex,
  required bool isPlaying,
  double height = 420,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: PlayerSubtitleList(
          lines: manyLines(30),
          activeIndex: activeIndex,
          subtitleMode: '双语',
          currentWordIndex: 0,
          fontScale: 1,
          highlightWords: true,
          onTapLine: (_) {},
          onCollectWord: (_) {},
          onBookmarkLine: (_) {},
          onLoopFromLine: (_) {},
          onDictationLine: (_) {},
          onAiExplain: (_) {},
          isPlaying: isPlaying,
          onTogglePlaying: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('暂停状态下换句（等价于拖动进度条）列表仍会跟到当前句', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 播放中先建立位置（暂停状态下初始挂载不会触发跟随，
    // 需要一次真实的索引变化来模拟拖动进度条）。
    await tester.pumpWidget(page(activeIndex: 2, isPlaying: true));
    await tester.pumpAndSettle();

    // 先切到暂停，再把当前句由 2 跳到 18：
    // 等价于「暂停后拖动进度条」。
    await tester.pumpWidget(page(activeIndex: 2, isPlaying: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page(activeIndex: 18, isPlaying: false));
    await tester.pumpAndSettle();

    // 修复前：因为 isPlaying 为 false，不触发跟随，第 18 句根本不在视口内。
    // 中文已改为可选词块（逐句精听里可划选短语），
    // 因此不能再按整句文本查找，改用该行的稳定 key。
    final Finder row18 = find.byKey(
      const ValueKey<String>('subtitle-zh-18'),
      skipOffstage: false,
    );
    expect(row18, findsOneWidget);
    // 断言「在视口内」而非「精确居中」：列表行高随字幕长度变化，
    // 滚动过程中内容尺寸也会变化，精确居中不可靠；
    // 真正要保证的是当前句可靠可见。
    final Rect listRect = tester.getRect(find.byType(ListView));
    final Rect rowRect = tester.getRect(
      find
          .ancestor(of: row18, matching: find.byType(InkWell))
          .first,
    );
    expect(
      rowRect.top,
      greaterThanOrEqualTo(listRect.top - 1),
      reason: '当前句不应被裁在列表上方之外',
    );
    expect(
      rowRect.bottom,
      lessThanOrEqualTo(listRect.bottom + 1),
      reason: '当前句应完整落在列表可视区域内',
    );
  });

  testWidgets('选中文本不会停止后续跟随', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(activeIndex: 2, isPlaying: true));
    await tester.pumpAndSettle();

    // 播放中在列表上划一下，产生文本选择。
    final Finder listFinder = find.byType(ListView);
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(listFinder),
    );
    await gesture.moveBy(const Offset(30, -30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 之后当前句继续前进（分两步，模拟连续推进）。
    // 修复前：上面的划选会触发 SelectionArea 的 onSelectionChanged，
    // 把跟随永久关掉，导致后续当前句滚出视野、列表停在原地。
    await tester.pumpWidget(page(activeIndex: 12, isPlaying: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page(activeIndex: 22, isPlaying: true));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('subtitle-zh-22'),
        skipOffstage: false,
      ),
      findsOneWidget,
      reason: '选中文本后仍应继续跟随当前句',
    );
  });

  testWidgets('主动拖动列表后不再强行拉回（保留原有设计）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(activeIndex: 10, isPlaying: true));
    await tester.pumpAndSettle();

    // 用户主动拖动列表 → 表达「我要自己看」。
    final Finder listFinder = find.byType(ListView);
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(listFinder),
    );
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final double before = tester
        .state<ScrollableState>(
          find.descendant(
            of: listFinder,
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;

    // 当前句前进：此时不应把用户拉回。
    await tester.pumpWidget(page(activeIndex: 11, isPlaying: true));
    await tester.pumpAndSettle();

    final double after = tester
        .state<ScrollableState>(
          find.descendant(
            of: listFinder,
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;

    expect(
      (after - before).abs(),
      lessThan(60),
      reason: '用户主动拖动后，不应因当前句前进而被强行拉回',
    );
  });
}
