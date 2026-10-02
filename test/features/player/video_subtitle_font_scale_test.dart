import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/player/presentation/widgets/player_video_panel.dart';

/// 画面字幕的字号。
///
/// 回归背景：
///   1) 画面字幕此前是写死字号（普通 28、全屏 34），
///      设置里的「字幕字体大小」只影响下方字幕列表，对画面字幕无效；
///   2) 默认字号偏大，一句话占三行、遮住大半个画面。
/// 现在画面字幕由 fontScale 驱动，且默认值已下调。
void main() {
  Widget wrap({required double fontScale}) {
    return MaterialApp(
      home: Scaffold(
        body: PlayerVideoPanel(
          line: PlayerMockState.fallbackLines.first,
          isPlaying: false,
          subtitleMode: '双语',
          subtitleModes: const <String>['双语'],
          speed: '1.0×',
          isShadowing: false,
          isLooping: false,
          isMuted: false,
          volumeLevel: 1,
          fontScale: fontScale,
          onTogglePlaying: () {},
          onPreviousLine: () {},
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
          onSubtitleLookupOpen: () {},
          onCollectWord: (_) {},
          onFavoriteWord: (_) {},
          onPronounce: () {},
        ),
      ),
    );
  }

  double englishFontSize(WidgetTester tester) {
    final Iterable<Text> texts = tester.widgetList<Text>(find.byType(Text));
    // 取英文原句那个 Text（fallbackLines.first 的英文）。
    final String english = PlayerMockState.fallbackLines.first.english;
    final Text target = texts.firstWhere(
      (Text t) => (t.data ?? '').contains(english.split(' ').first),
    );
    return target.style?.fontSize ?? 0;
  }

  testWidgets('默认字号已下调（不再占三行遮住画面）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(fontScale: 1));
    await tester.pumpAndSettle();

    final double size = englishFontSize(tester);
    expect(size, lessThanOrEqualTo(22), reason: '默认英文画面字幕不应超过 22');
    expect(size, greaterThan(10));
  });

  testWidgets('字号随 fontScale 变化', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(fontScale: 1));
    await tester.pumpAndSettle();
    final double normal = englishFontSize(tester);

    await tester.pumpWidget(wrap(fontScale: 1.18));
    await tester.pumpAndSettle();
    final double large = englishFontSize(tester);

    await tester.pumpWidget(wrap(fontScale: 0.92));
    await tester.pumpAndSettle();
    final double small = englishFontSize(tester);

    expect(large, greaterThan(normal), reason: '「大」应比「中」更大');
    expect(small, lessThan(normal), reason: '「小」应比「中」更小');
  });
}
