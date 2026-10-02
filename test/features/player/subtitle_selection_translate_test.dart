/// 字幕列表：选中短语/整句后翻译。
///
/// 用户反馈：逐句精听里只能点单个单词查词，
/// 「有些短语没法进行选择」，希望对不懂的短语或整句也能翻译。
///
/// 列表本就包在 SelectionArea 里（可拖选），但选中后毫无反应。
/// 现在选中后出现「翻译选中」入口，点击即用该短语为词条、
/// 以所在整句为上下文弹出词义/翻译卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart' show Override;
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/player/presentation/widgets/player_subtitle_list.dart';
import 'package:yingsui/features/settings/presentation/settings_provider.dart';
import 'package:yingsui/features/shared/data/word_lookup_service.dart';
import 'package:yingsui/features/shared/domain/word_lookup_entry.dart';

/// 带固定句子的字幕数据，便于断言「整句作为上下文」。
List<PlayerSubtitleLine> lines() {
  return <PlayerSubtitleLine>[
    const PlayerSubtitleLine(
      startTime: '00:01',
      english: 'Science just turns me on.',
      chinese: '科学让我欲火焚身。',
      startMs: 1000,
      endMs: 5000,
    ),
    const PlayerSubtitleLine(
      startTime: '00:06',
      english: 'Nobody is saying our neighborhood is the Garden of Eden.',
      chinese: '没人说我们社区是伊甸园。',
      startMs: 6000,
      endMs: 11000,
    ),
  ];
}

/// 捕获查词入参，用于断言「短语 + 整句上下文」。
({String word, String context})? lastLookup;

/// 已配置翻译 API 的设置。
///
/// 必须提供：未配置时 WordLookupService 会直接返回「请先配置翻译 API」，
/// 根本不会走到 remoteLookupOverride，测试也就捕获不到入参。
class _ConfiguredLearningSettingsNotifier extends LearningSettingsNotifier {
  @override
  LearningSettingsState build() {
    return LearningSettingsState.defaults().copyWith(
      translationProvider: 'OpenAI',
      translationApiKey: 'demo-key',
      translationBaseUrl: 'https://api.openai.com/v1',
      translationModel: 'gpt-4o-mini',
    );
  }
}

Widget page() {
  return ProviderScope(
    overrides: <Override>[
      learningSettingsProvider.overrideWith(
        _ConfiguredLearningSettingsNotifier.new,
      ),
      wordLookupServiceProvider.overrideWithValue(
        WordLookupService(
          remoteLookupOverride:
              ({
                required String rawWord,
                String? contextSentence,
                required LearningSettingsState settings,
              }) async {
                lastLookup = (
                  word: rawWord,
                  context: contextSentence ?? '',
                );
                return WordLookupEntry(
                  word: rawWord,
                  phonetic: '',
                  type: '英文短语',
                  definitionEn: '',
                  usageEn: '',
                  exampleSentenceEn: '',
                  definitionCn: '让我兴奋',
                  sourceLabel: '测试',
                );
              },
        ),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 520,
          child: PlayerSubtitleList(
            lines: lines(),
            activeIndex: 0,
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
            onTogglePlaying: () {},
          ),
        ),
      ),
    ),
  );
}

/// 直接触发 SelectionArea 的选中回调，模拟用户拖选。
void simulateSelection(WidgetTester tester, String text) {
  final SelectionArea area = tester.widget<SelectionArea>(
    find.byKey(const ValueKey<String>('subtitle-list-selection-area')),
  );
  area.onSelectionChanged?.call(SelectedContent(plainText: text));
}

/// 等待选中去抖窗口过去（实现里为 160ms，留出余量）。
Future<void> settleSelection(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('未选中时不显示「翻译选中」入口', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsNothing,
    );
  });

  testWidgets('选中短语后出现「翻译选中」入口，并显示所选内容', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    simulateSelection(tester, 'turns me on');
    await settleSelection(tester);

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '选中短语后应出现翻译入口',
    );
    expect(find.text('turns me on'), findsWidgets, reason: '应显示所选内容');
  });

  testWidgets('点「翻译选中」会为短语弹出词义卡片', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    simulateSelection(tester, 'turns me on');
    await settleSelection(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('word-lookup-popup-card')),
      findsOneWidget,
      reason: '应弹出词义/翻译卡片',
    );
  });

  testWidgets('取消选择后入口消失', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    simulateSelection(tester, 'turns me on');
    await settleSelection(tester);
    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsNothing,
      reason: '取消选择后入口应消失',
    );
  });

  testWidgets('翻译短语时会带上所在整句作为上下文', (WidgetTester tester) async {
    // 同一个短语在不同句子里含义可能不同，上下文能显著提高准确度。
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    lastLookup = null;

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    simulateSelection(tester, 'turns me on');
    await settleSelection(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
    );
    await tester.pumpAndSettle();

    expect(lastLookup, isNotNull, reason: '应确实发起了查词/翻译');
    expect(
      lastLookup!.word,
      'turns me on',
      reason: '词条应为所选短语本身（而不是某个单词）',
    );
    expect(
      lastLookup!.context,
      'Science just turns me on.',
      reason: '应带上该短语所在的整句作为上下文',
    );
  });

  testWidgets('提示条出现不会改变列表几何（防闪烁）', (WidgetTester tester) async {
    // 用户反馈：选中短语时页面闪烁、不稳定。
    //
    // 根因一：选中回调每帧触发 setState，整个列表每帧重建。
    // 根因二：提示条原先插在 Column 里，出现/消失会改变列表可用高度，
    //         拖选过程中列表内容随之上下跳动。
    //
    // 现改为：选中结果用 ValueNotifier 承载（只有提示条自己重建），
    // 提示条改为 Stack 浮层（不参与列表布局），并加 160ms 去抖。
    // 这里断言「提示条出现前后列表几何完全一致」。
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    Rect listRect() => tester.getRect(find.byType(ListView));
    final Rect before = listRect();

    simulateSelection(tester, 'turns me on');
    await settleSelection(tester);

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '提示条应已出现',
    );
    final Rect after = listRect();
    expect(
      after,
      before,
      reason: '提示条出现不应改变列表位置或尺寸，否则拖选时会跳动',
    );

    // 取消后再确认一次。
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(listRect(), before, reason: '提示条消失同样不应改变列表几何');
  });

  testWidgets('拖选过程中的中间状态不会立即显示提示条（去抖）', (WidgetTester tester) async {
    // 拖选会连续产生多个中间选中状态；若每个都立刻显示提示条，
    // 界面会持续抖动。去抖窗口内不应出现提示条。
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    simulateSelection(tester, 'turns');
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsNothing,
      reason: '去抖窗口内不应显示提示条',
    );

    // 停稳后出现
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '停稳后应显示提示条',
    );
  });
}
