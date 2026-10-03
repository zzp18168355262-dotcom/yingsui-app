/// 影子跟读面板里也要能划选短语看翻译。
///
/// 用户反馈「提示条根本不出现」——播放页在跟读时用面板**替换**了字幕列表，
/// 而划选能力原先只实现在列表里，面板完全没有。
/// 本测试锁定面板侧的划选行为。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/widgets/shadowing_practice_panel.dart';

Widget wrap(ShadowingPracticePanel panel) {
  return ProviderScope(
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: panel))),
  );
}

void main() {
  testWidgets('长按英文词块并划过相邻词，出现「翻译选中」提示条', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    String? translatedPhrase;
    await tester.pumpWidget(
      wrap(
        ShadowingPracticePanel(
          lineKey: '1000#0',
          english: 'turns me on right now',
          chinese: '让我兴奋',
          onPlayOriginal: () {},
          onStopOriginal: () {},
          onTranslatePhrase: (String phrase, String sentence) {
            translatedPhrase = phrase;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Rect first = tester.getRect(find.text('turns').first);
    final Rect third = tester.getRect(find.text('on').first);

    // 严格模拟手指：按下 → 停住触发长按 → 移到第三个词 → 抬起。
    final TestGesture gesture = await tester.startGesture(first.center);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(third.center);
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '跟读面板里划选后应出现「翻译选中」提示条',
    );
    expect(find.text('turns me on'), findsWidgets, reason: '应选中多个词');

    await tester.tap(find.text('翻译选中'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(translatedPhrase, 'turns me on');
  });
}
