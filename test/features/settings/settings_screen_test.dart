import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart' show Override;
import 'package:yingsui/features/settings/presentation/settings_provider.dart';
import 'package:yingsui/features/settings/presentation/settings_screen.dart';
import 'package:yingsui/features/settings/presentation/widgets/settings_group_card.dart';

void main() {
  _narrowLayoutTests();
  _noFakeCloudSyncTests();
  testWidgets('settings screen shows prototype sections', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsWidgets);
    expect(find.text('播放'), findsOneWidget);
    expect(find.text('学习').last, findsOneWidget);
    expect(find.text('默认字幕模式'), findsOneWidget);
    expect(find.text('单词高亮样式'), findsOneWidget);
    expect(find.text('单词高亮边框粗细'), findsOneWidget);
    expect(find.text('每日打卡提醒'), findsOneWidget);
    expect(find.text('词典来源'), findsNothing);

    await _scrollToTranslationSettings(tester);

    expect(find.text('翻译'), findsOneWidget);
    expect(find.text('翻译来源'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('获取模型'), findsWidgets);
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('API Secret'), findsNothing);
    expect(find.text('App ID'), findsNothing);
    expect(find.text('AccessKey ID'), findsNothing);
  });

  testWidgets('settings screen shows AI translation fields for OpenAI', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);
    await tester.tap(_translationProviderDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI').last);
    await tester.pumpAndSettle();

    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('获取模型'), findsWidgets);
    expect(find.text('Model'), findsOneWidget);
  });

  testWidgets('settings screen shows DeepSeek as AI provider option', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);
    await tester.tap(_translationProviderDropdown());
    await tester.pumpAndSettle();

    expect(find.text('DeepSeek').last, findsOneWidget);
  });

  testWidgets('settings screen shows direct translation fields for baidu', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);
    await tester.tap(_translationProviderDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.text('百度翻译').last);
    await tester.pumpAndSettle();

    expect(find.text('App ID'), findsOneWidget);
    expect(find.text('Secret'), findsOneWidget);
  });

  testWidgets('settings screen shows fetched models dropdown for AI provider', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          learningSettingsProvider.overrideWith(
            () => _TestLearningSettingsNotifier(
              LearningSettingsState.defaults().copyWith(
                translationProvider: 'DeepSeek',
                translationModel: 'deepseek-v4-flash',
                availableTranslationModels: const <String>[
                  'deepseek-v4-flash',
                  'deepseek-v4-pro',
                ],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);

    expect(find.text('模型选择'), findsOneWidget);
    expect(find.text('deepseek-v4-flash'), findsWidgets);
  });

  testWidgets('settings links to AI subtitle management', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
    for (
      int index = 0;
      index < 8 && find.text('管理 AI 字幕').evaluate().isEmpty;
      index++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
    }

    expect(find.text('管理 AI 字幕'), findsOneWidget);
    expect(find.text('导出 AI 字幕'), findsNothing);
  });
}

Future<void> _scrollToTranslationSettings(WidgetTester tester) async {
  for (
    int index = 0;
    index < 4 && find.text('翻译来源').evaluate().isEmpty;
    index++
  ) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
  }
}

Finder _translationProviderDropdown() {
  return find.descendant(
    of: find.ancestor(
      of: find.text('翻译来源'),
      matching: find.byType(SettingsGroupCard),
    ),
    matching: find.byType(DropdownButton<String>),
  );
}

class _TestLearningSettingsNotifier extends LearningSettingsNotifier {
  _TestLearningSettingsNotifier(this._state);

  final LearningSettingsState _state;

  @override
  LearningSettingsState build() => _state;
}

/// 未实现的功能必须如实说明，不得提示「成功」。
///
/// 回归背景：设置页曾有一个「备份同步云端数据」入口，
/// 描述里显示写死的「142 个词汇」，点击后提示「备份同步成功」，
/// 但实际不会同步任何数据 —— 用户会以为数据已上云，
/// 换设备时才发现丢失。对付费产品而言这种误导不可接受。
void _noFakeCloudSyncTests() {
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          learningSettingsProvider.overrideWith(
            () => _TestLearningSettingsNotifier(
              LearningSettingsState.defaults(),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    // 该入口在设置页底部，需要滚动到可见处。
    for (
      int index = 0;
      index < 10 && find.textContaining('云端备份').evaluate().isEmpty;
      index++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
  }

  group('设置页不提供假的云端同步', () {
    testWidgets('不再出现「同步成功」这类误导提示', (WidgetTester tester) async {
      await pumpSettings(tester);

      final Finder entry = find.textContaining('云端备份');
      expect(entry, findsOneWidget, reason: '应保留入口但如实标注为即将推出');
      await tester.tap(entry, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.textContaining('同步成功'), findsNothing);
      // 也不应出现写死的假数据量。
      expect(find.textContaining('142'), findsNothing);
    });

    testWidgets('如实说明当前不会上传数据', (WidgetTester tester) async {
      await pumpSettings(tester);

      expect(find.textContaining('尚在开发中'), findsOneWidget);
      expect(find.textContaining('不会上传任何数据'), findsOneWidget);
    });
  });
}

/// 窄屏布局：设置页有大量 Row，手机竖屏宽度下容易横向溢出。
///
/// 这是实测驱动的检查 —— 上一轮逐词全文就在 390 逻辑像素下溢出 25px，
/// 真机上表现为黄黑条纹警告。
void _narrowLayoutTests() {
  group('设置页窄屏不溢出', () {
    for (final double width in <double>[320, 390, 412, 480, 600]) {
      testWidgets('宽度 $width 下无溢出', (WidgetTester tester) async {
        tester.view.physicalSize = Size(width * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: SettingsScreen())),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: '$width 宽度发生布局异常');

        // 滚到底部，让下半部分也参与布局。
        for (int i = 0; i < 12; i += 1) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$width 宽度滚动中出现异常');
        }
      });
    }
  });
}
