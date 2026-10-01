import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Override 由 riverpod 内部导出，flutter_riverpod 不转出该类型。
import 'package:riverpod/src/framework.dart' show Override;
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/player/presentation/shadowing_recorder.dart';
import 'package:yingsui/features/player/presentation/widgets/shadowing_practice_panel.dart';

/// 覆盖「跟读后能听到自己」这条链路的界面层：
/// 录制 → 出现「听听我的跟读」→ 点击后进入播放态。
///
/// 说明：这里无法验证真实音频解码（测试环境没有 media_kit 的原生库），
/// 但可以验证按钮存在、可达、以及状态机切换是否正确。
class _FakeRecorder extends ShadowingRecorder {
  _FakeRecorder(this._initial);

  final ShadowingRecordState _initial;

  @override
  ShadowingRecordState build() => _initial;
}

Widget _wrap(Widget child, ShadowingRecordState state) {
  return ProviderScope(
    overrides: <Override>[
      shadowingRecorderProvider.overrideWith(() => _FakeRecorder(state)),
    ],
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  const ShadowingPracticePanel panel = ShadowingPracticePanel(
    lineKey: '1000#0',
    onPlayOriginal: _noop,
    onStopOriginal: _noop,
  );

  group('面板内展示当前句', () {
    const ShadowingPracticePanel withLine = ShadowingPracticePanel(
      lineKey: '1000#0',
      english: 'Let me make sure I understand.',
      chinese: '让我确认一下我理解得对不对。',
      onPlayOriginal: _noop,
      onStopOriginal: _noop,
    );

    testWidgets('同时显示原文与译文，无需回头看视频字幕', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(withLine, const ShadowingRecordState()));
      await tester.pump();

      expect(find.text('跟读这一句'), findsOneWidget);
      expect(find.text('Let me make sure I understand.'), findsOneWidget);
      expect(find.text('让我确认一下我理解得对不对。'), findsOneWidget);
    });

    testWidgets('字幕模式为「隐藏」时不显示译文', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const ShadowingPracticePanel(
            lineKey: '1000#0',
            english: 'Let me make sure I understand.',
            chinese: '让我确认一下我理解得对不对。',
            subtitleMode: '隐藏',
            onPlayOriginal: _noop,
            onStopOriginal: _noop,
          ),
          const ShadowingRecordState(),
        ),
      );
      await tester.pump();

      expect(find.text('Let me make sure I understand.'), findsOneWidget);
      expect(find.text('让我确认一下我理解得对不对。'), findsNothing);
    });

    testWidgets('未传句子时不显示该区块（避免出现空卡片）', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(panel, const ShadowingRecordState()));
      await tester.pump();

      expect(find.text('跟读这一句'), findsNothing);
    });

    testWidgets('显示句子序号，并可切换上一句/下一句', (WidgetTester tester) async {
      int previousTaps = 0;
      int nextTaps = 0;
      await tester.pumpWidget(
        _wrap(
          ShadowingPracticePanel(
            lineKey: '5000#1',
            english: 'second line',
            chinese: '第二句',
            lineIndex: 1,
            totalLines: 3,
            onPreviousLine: () => previousTaps += 1,
            onNextLine: () => nextTaps += 1,
            onPlayOriginal: _noop,
            onStopOriginal: _noop,
          ),
          const ShadowingRecordState(),
        ),
      );
      await tester.pump();

      expect(find.textContaining('第 2 / 3 句'), findsOneWidget);

      await tester.tap(find.byTooltip('上一句'));
      await tester.tap(find.byTooltip('下一句'));
      await tester.pump();

      expect(previousTaps, 1);
      expect(nextTaps, 1);
    });

    testWidgets('第一句时「上一句」不可用，最后一句时「下一句」不可用', (WidgetTester tester) async {
      // 第一句：上一句应无效，点击不应有任何副作用。
      int taps = 0;
      await tester.pumpWidget(
        _wrap(
          ShadowingPracticePanel(
            lineKey: 'k0',
            english: 'first line',
            lineIndex: 0,
            totalLines: 3,
            onPreviousLine: () => taps += 1,
            onNextLine: () => taps += 1,
            onPlayOriginal: _noop,
            onStopOriginal: _noop,
          ),
          const ShadowingRecordState(),
        ),
      );
      await tester.pump();
      expect(find.textContaining('第 1 / 3 句'), findsOneWidget);

      // 禁用的按钮点击不会触发回调（warnIfMissed 关闭：禁用态本就不可命中）。
      await tester.tap(find.byTooltip('上一句'), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0, reason: '第一句不应能切到上一句');

      await tester.tap(find.byTooltip('下一句'));
      await tester.pump();
      expect(taps, 1, reason: '第一句应能切到下一句');

      // 最后一句：下一句应无效。
      int lastTaps = 0;
      await tester.pumpWidget(
        _wrap(
          ShadowingPracticePanel(
            lineKey: 'k2',
            english: 'last line',
            lineIndex: 2,
            totalLines: 3,
            onPreviousLine: () => lastTaps += 1,
            onNextLine: () => lastTaps += 1,
            onPlayOriginal: _noop,
            onStopOriginal: _noop,
          ),
          const ShadowingRecordState(),
        ),
      );
      await tester.pump();
      expect(find.textContaining('第 3 / 3 句'), findsOneWidget);

      await tester.tap(find.byTooltip('上一句'));
      await tester.pump();
      expect(lastTaps, 1, reason: '最后一句应能切到上一句');

      await tester.tap(find.byTooltip('下一句'), warnIfMissed: false);
      await tester.pump();
      expect(lastTaps, 1, reason: '最后一句不应能再往后');
    });
  });

  group('选择句子列表（可折叠）', () {
    List<PlayerSubtitleLine> sampleLines() => <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'first line',
        chinese: '第一句',
        startMs: 1000,
        endMs: 3000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:05',
        english: 'second line',
        chinese: '第二句',
        startMs: 5000,
        endMs: 8000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:09',
        english: 'third line',
        chinese: '第三句',
        startMs: 9000,
        endMs: 12000,
      ),
    ];

    testWidgets('默认收起，只显示入口；展开后可见句子并可点选', (WidgetTester tester) async {
      int? selected;
      await tester.pumpWidget(
        _wrap(
          ShadowingPracticePanel(
            lineKey: '5000#1',
            english: 'second line',
            chinese: '第二句',
            lineIndex: 1,
            totalLines: 3,
            lines: sampleLines(),
            onSelectLine: (int index) => selected = index,
            onPlayOriginal: _noop,
            onStopOriginal: _noop,
          ),
          const ShadowingRecordState(),
        ),
      );
      await tester.pump();

      // 收起状态：入口在，但列表内容不在。
      expect(find.text('选择句子'), findsOneWidget);
      expect(find.textContaining('共 3 句'), findsOneWidget);
      expect(find.text('third line'), findsNothing);

      // 展开。
      await tester.tap(find.text('选择句子'));
      await tester.pumpAndSettle();
      expect(find.text('first line'), findsOneWidget);
      expect(find.text('third line'), findsOneWidget);
      expect(find.text('第一句'), findsOneWidget);

      // 点选第三句：回调收到正确索引，并且列表自动收起。
      await tester.tap(find.text('third line'));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(find.text('third line'), findsNothing, reason: '点选后应收起列表');
    });

    testWidgets('未提供句子列表时不显示该入口', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const ShadowingPracticePanel(
            lineKey: '1000#0',
            english: 'only line',
            onPlayOriginal: _noop,
            onStopOriginal: _noop,
          ),
          const ShadowingRecordState(),
        ),
      );
      await tester.pump();

      expect(find.text('选择句子'), findsNothing);
    });

    testWidgets('字幕模式为「隐藏」时列表中不显示译文', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          ShadowingPracticePanel(
            lineKey: '1000#0',
            english: 'first line',
            chinese: '第一句',
            subtitleMode: '隐藏',
            lineIndex: 0,
            totalLines: 3,
            lines: sampleLines(),
            onSelectLine: (_) {},
            onPlayOriginal: _noop,
            onStopOriginal: _noop,
          ),
          const ShadowingRecordState(),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('选择句子'));
      await tester.pumpAndSettle();

      expect(find.text('first line'), findsWidgets);
      expect(find.text('第一句'), findsNothing);
    });
  });

  testWidgets('未录音时只显示录制入口，不显示回放按钮', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(panel, const ShadowingRecordState()));
    await tester.pump();

    expect(find.text('按下开始跟读'), findsOneWidget);
    expect(find.text('听听我的跟读'), findsNothing);
    expect(find.text('再听原声'), findsNothing);
  });

  testWidgets('录完后出现「听听我的跟读」入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        panel,
        const ShadowingRecordState(
          status: ShadowingRecordStatus.recorded,
          filePath: '/tmp/fake.m4a',
          lineKey: '1000#0',
        ),
      ),
    );
    await tester.pump();

    // 这是本次需求的核心：用户要能听到自己的跟读。
    expect(find.text('听听我的跟读'), findsOneWidget);
    expect(find.text('再听原声'), findsOneWidget);
    expect(find.text('重录一遍'), findsOneWidget);
    // 已有录音时录制按钮让位，显示「已录好」且不可点。
    expect(find.text('已录好'), findsOneWidget);
  });

  testWidgets('录音中显示计时与结束入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        panel,
        const ShadowingRecordState(
          status: ShadowingRecordStatus.recording,
          filePath: '/tmp/fake.m4a',
          lineKey: '1000#0',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('结束这一遍'), findsOneWidget);
    expect(find.text('放弃这一遍'), findsOneWidget);
    expect(find.text('听听我的跟读'), findsNothing);
  });

  testWidgets('暂停后可以继续录音', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        panel,
        const ShadowingRecordState(
          status: ShadowingRecordStatus.paused,
          filePath: '/tmp/fake.m4a',
          lineKey: '1000#0',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('继续录'), findsOneWidget);
  });

  testWidgets('录音缺少文件时不出现回放入口（避免点了没反应）',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        panel,
        const ShadowingRecordState(
          status: ShadowingRecordStatus.recorded,
          lineKey: '1000#0',
          // filePath 为空
        ),
      ),
    );
    await tester.pump();

    expect(find.text('听听我的跟读'), findsNothing);
  });
}

void _noop() {}
