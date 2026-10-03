/// 播放页视频面板在手机窄屏（360dp）下的布局。
///
/// 背景：用户实测安卓机（1080×2400 @3x = 360×800）反馈
/// 「学习时上面的页面把视频全部挡住了」。
///
/// 原因是控制栏叠在视频之上，而 16:9 的视频在 360dp 宽下只有约 200dp 高。
/// 控制栏里 9 个按钮按 40dp + 6dp 间距需要约 500dp，可用宽度只有约 324dp，
/// 于是 Wrap 换行成 2–3 行，控制栏高度超过视频高度，整块画面被盖住。
///
/// 本测试锁定两点：
///   1. 视频面板渲染不抛溢出异常；
///   2. **控制栏本身的高度明显小于视频面板高度**，
///      确保它不会把画面盖满。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/player/presentation/widgets/player_video_panel.dart';

const Size _phone = Size(1080, 2400);
const double _dpr = 3;

Future<void> _pumpPanel(
  WidgetTester tester, {
  Size size = _phone,
  double dpr = _dpr,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            PlayerVideoPanel(
              line: const PlayerSubtitleLine(
                startTime: '00:35',
                english: 'It is raining today.',
                chinese: '今天在下雨。',
                startMs: 35000,
                endMs: 38000,
              ),
              isPlaying: true,
              subtitleMode: '双语',
              subtitleModes: const <String>['隐藏', '英文', '双语'],
              speed: '0.8×',
              isShadowing: false,
              isLooping: false,
              onTogglePlaying: () {},
              onPreviousLine: () {},
              onReplayLine: () {},
              onNextLine: () {},
              onSeekBackward: () {},
              onSeekForward: () {},
              activeIndex: 0,
              totalLines: 12,
              onSelectLine: (int index) {},
              onSeek: (double value) {},
              onSpeedSelected: (String value) {},
              onSelectSubtitleMode: (String value) {},
              onToggleShadowing: () {},
              onToggleLoop: () {},
              isMuted: false,
              volumeLevel: 0.8,
              onToggleMuted: () {},
              onVolumeChanged: (double value) {},
              onToggleFullscreen: () {},
              videoDuration: const Duration(seconds: 156),
              videoPosition: const Duration(seconds: 35),
              videoReady: true,
              showAiGenerateSubtitles: true,
              onGenerateAiSubtitles: () {},
            ),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ),
    ),
  );
  // 固定次数 pump：控制栏有淡入动画，pumpAndSettle 在持续动画下不返回。
  for (int i = 0; i < 6; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('播放页视频面板 · 360dp 手机', () {
    testWidgets('渲染不抛布局溢出', (WidgetTester tester) async {
      await _pumpPanel(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: '360dp 下渲染播放面板不应抛布局异常',
      );
    });

    testWidgets('视频面板保持 16:9 且高度可测', (WidgetTester tester) async {
      await _pumpPanel(tester);
      final Rect panel = tester.getRect(find.byType(PlayerVideoPanel));
      // 360dp 宽、16:9 → 约 202dp 高；这里只断言它确实拿到了合理高度，
      // 避免出现「被控制栏挤到几乎为零」的情况。
      expect(
        panel.height,
        greaterThan(150),
        reason: '视频面板高度 ${panel.height} 过小，画面会被控件盖掉',
      );
    });

    testWidgets('控制栏保持单行且不盖满视频区', (WidgetTester tester) async {
      await _pumpPanel(tester);

      final Finder dockText = find.text('00:35');
      expect(dockText, findsWidgets, reason: '控制栏应已显示（含时间标签）');

      final double panelHeight = tester
          .getRect(find.byType(PlayerVideoPanel))
          .height;
      final double dockHeight =
          panelHeight - tester.getRect(dockText.first).top;

      // 实测：修复前尾部控件换成 3 行，控制栏区域高约 71dp；
      // 修复后单行约 33dp。这里用 55% 作为上限，
      // 既留出余量，又能在重新出现换行时立刻失败。
      expect(
        dockHeight,
        lessThan(panelHeight * 0.55),
        reason: '控制栏高度 $dockHeight / 面板 $panelHeight 过大，可能又换行了。',
      );
    });

    testWidgets('手机窄屏隐藏次要控件以免控制栏换行', (WidgetTester tester) async {
      await _pumpPanel(tester);
      // 画面比例 / 静音在手机上隐藏（音量用硬件键，比例可在全屏调整）。
      // 这些控件在 360dp 上会把尾部挤成 2–3 行，导致画面被盖住。
      expect(find.byTooltip('画面比例'), findsNothing, reason: '手机上应隐藏画面比例');
      expect(find.byTooltip('静音'), findsNothing, reason: '手机上应隐藏静音');
      // 核心操作必须保留。
      expect(find.byTooltip('字幕模式'), findsOneWidget, reason: '字幕模式应保留');
      expect(find.byTooltip('播放速度'), findsOneWidget, reason: '播放速度应保留');
    });
  });
}
