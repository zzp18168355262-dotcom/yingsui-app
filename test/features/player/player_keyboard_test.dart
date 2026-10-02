/// 播放页键盘快捷键。
///
/// 用户反馈：无法用键盘控制字幕与视频进度
/// （希望用上下键做句子跳转、以及按句精听）。
///
/// 原实现只在视频画面控件上监听键盘，虽然设了 autofocus，
/// 实际焦点常被同一焦点作用域内的其他控件拿走，于是
/// 「不先点一下画面，按方向键没反应」。现提升为页面级键盘层。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/player/presentation/widgets/player_video_panel.dart';

Widget build({required VoidCallback onPrev, bool withTextField = false}) {
  return MaterialApp(
    home: Scaffold(
      body: Row(
        children: <Widget>[
          Expanded(
            child: PlayerVideoPanel(
              line: PlayerMockState.fallbackLines.first,
              isPlaying: false,
              subtitleMode: '双语',
              subtitleModes: const <String>['双语'],
              speed: '1.0×',
              isShadowing: false,
              isLooping: false,
              isMuted: false,
              volumeLevel: 1,
              onTogglePlaying: () {},
              onPreviousLine: onPrev,
              onReplayLine: () {},
              onNextLine: () {},
              onSeekBackward: () {},
              onSeekForward: () {},
              activeIndex: 0,
              totalLines: 1,
              onSelectLine: (_) {},
              onSeek: (_) {},
              onSpeedSelected: (_) {},
              onSelectSubtitleMode: (_) {},
              onToggleShadowing: () {},
              onToggleLoop: () {},
              onToggleMuted: () {},
              onVolumeChanged: (_) {},
              onToggleFullscreen: () {},
            ),
          ),
          if (withTextField)
            const SizedBox(
              width: 200,
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(hintText: '搜索'),
              ),
            ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('无需先点击画面，方向键即可跳句', (WidgetTester tester) async {
    int prev = 0;
    await tester.pumpWidget(build(onPrev: () => prev++));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(prev, 1);
  });

  testWidgets('文本输入时方向键让路给输入法', (WidgetTester tester) async {
    int prev = 0;
    await tester.pumpWidget(build(onPrev: () => prev++, withTextField: true));
    await tester.pumpAndSettle();
    // 明确让文本框取得焦点（两个 autofocus 会互相竞争，必须手动指定）。
    tester.state<EditableTextState>(find.byType(EditableText)).requestKeyboard();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(prev, 0, reason: '文本输入时不应被播放快捷键拦截');
  });
}
