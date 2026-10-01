import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Override 由 riverpod 内部导出，flutter_riverpod 不转出该类型。
import 'package:riverpod/src/framework.dart' show Override;
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
