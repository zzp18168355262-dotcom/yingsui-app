/// 长按词块后**划过相邻词**必须能把选区扩展成短语。
///
/// 用户反馈「也没办法选择短语，只能选择单个单词」：
/// 长按能选中起点那一个词，但拖动过程中收不到更新，选区不扩展。
/// 本测试严格走「长按 → 保持按下 → 移到相邻词 → 抬起」这条路径，
/// 并断言最终选中的是**多个词**。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/player/presentation/widgets/player_subtitle_list.dart';

List<PlayerSubtitleLine> lines() {
  return const <PlayerSubtitleLine>[
    PlayerSubtitleLine(
      startTime: '00:01',
      english: 'turns me on right now',
      chinese: '让我兴奋',
      startMs: 1000,
      endMs: 5000,
    ),
  ];
}

Future<void> pumpList(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 500,
          child: PlayerSubtitleList(
            lines: lines(),
            activeIndex: 0,
            subtitleMode: '双语',
            currentWordIndex: 0,
            fontScale: 1,
            highlightWords: false,
            onTapLine: (_) {},
            onCollectWord: (_) {},
            onCollectPhrase: (String phrase, String sentence) async {},
            onFavoriteWord: (_) {},
            onBookmarkLine: (_) {},
            onLoopFromLine: (_) {},
            onDictationLine: (_) {},
            onAiExplain: (_) {},
            isPlaying: false,
            onTogglePlaying: () {},
            onPronounce: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return;
}

void main() {
  testWidgets('长按后划过相邻词，选中结果应包含多个词', (WidgetTester tester) async {
    await pumpList(tester);

    final Rect first = tester.getRect(find.text('turns').first);
    final Rect third = tester.getRect(find.text('on').first);

    // 严格模拟手指：按下 → 停住触发长按 → 再移动到第三个词 → 抬起。
    final TestGesture gesture = await tester.startGesture(first.center);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(third.center);
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // 提示条上应显示跨多个词的短语。
    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '应出现「翻译选中」提示条',
    );
    expect(
      find.text('turns me on'),
      findsWidgets,
      reason: '长按拖动后应选中 turns me on 三个词，而不是只有 turns',
    );
  });
}
