/// 字幕列表：选中短语/整句后翻译。
///
/// 用户反馈：逐句精听里只能点单个单词查词，
/// 「有些短语没法进行选择」，希望对不懂的短语或整句也能翻译。
///
/// 列表本就包在 SelectionArea 里（可拖选），但选中后毫无反应。
/// 现在选中后出现「翻译选中」入口，点击即用该短语为词条、
/// 以所在整句为上下文弹出词义/翻译卡片。
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
      // 长句：在真实布局里会换行成两行，正是用户反馈选不中的场景。
      english:
          'FRANK: Lip, smart as a whip. Nobody is saying our '
          'neighborhood is the Garden of Eden.',
      chinese: '科学让我欲火焚身。',
      startMs: 1000,
      endMs: 5000,
    ),
    const PlayerSubtitleLine(
      startTime: '00:06',
      english: 'Line two for the selection test.',
      chinese: '没人说我们社区是伊甸园。',
      startMs: 6000,
      endMs: 11000,
    ),
  ];
}

/// 足够多的句子，让列表**真的可以滚动**。
///
/// 这一点很关键：列表内容不足一屏时 Scrollable 根本不会注册纵向拖动
/// 识别器，手势竞技场的裁决结果与真实使用场景不同。
List<PlayerSubtitleLine> manyLines() {
  return <PlayerSubtitleLine>[
    for (int i = 0; i < 24; i++)
      PlayerSubtitleLine(
        startTime: '00:${(i * 3).toString().padLeft(2, '0')}',
        english: 'Row number $i keeps the list scrollable for the test.',
        chinese: '第 $i 行，用来把列表撑到可以滚动。',
        startMs: i * 3000,
        endMs: i * 3000 + 2500,
      ),
  ];
}

/// 捕获查词入参，用于断言「短语 + 整句上下文」。
({String word, String context})? lastLookup;

/// 捕获收藏入参。
List<({String phrase, String context})> collectedPhrases =
    <({String phrase, String context})>[];

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

Widget page({
  int activeIndex = 0,
  List<PlayerSubtitleLine>? subtitleLines,
  String subtitleMode = '双语',
}) {
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
            lines: subtitleLines ?? lines(),
            activeIndex: activeIndex,
            subtitleMode: subtitleMode,
            currentWordIndex: 0,
            fontScale: 1,
            highlightWords: true,
            onTapLine: (_) {},
            onCollectWord: (_) {},
            onCollectPhrase: (String phrase, String context) async {
              collectedPhrases.add((phrase: phrase, context: context));
            },
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
      lastLookup!.context.contains('turns me on'),
      isTrue,
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

  testWidgets('提示条上有收藏按钮，点击收藏所选短语', (WidgetTester tester) async {
    // 用户要求：选出的短语可以添加到短语库，在「翻译选中」边上加收藏按钮。
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    collectedPhrases = <({String phrase, String context})>[];

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    simulateSelection(tester, 'turns me on');
    await settleSelection(tester);

    final Finder collectButton = find.byKey(
      const ValueKey<String>('subtitle-collect-selection'),
    );
    expect(collectButton, findsOneWidget, reason: '应有收藏按钮');

    await tester.tap(collectButton);
    await tester.pumpAndSettle();

    expect(collectedPhrases, hasLength(1), reason: '应触发一次收藏');
    expect(
      collectedPhrases.first.phrase,
      'turns me on',
      reason: '收藏的应是所选短语本身，而不是整句',
    );
    expect(
      collectedPhrases.first.context.contains('turns me on'),
      isTrue,
      reason: '应带上所在整句作为出处',
    );
  });

  testWidgets('未提供收藏回调时不显示收藏按钮', (WidgetTester tester) async {
    // 某些入口（如全屏播放页的字幕）不提供短语库，此时不该出现按钮。
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          learningSettingsProvider.overrideWith(
            _ConfiguredLearningSettingsNotifier.new,
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
      ),
    );
    await tester.pumpAndSettle();

    simulateSelection(tester, 'turns me on');
    await settleSelection(tester);

    expect(
      find.byKey(const ValueKey<String>('subtitle-collect-selection')),
      findsNothing,
      reason: '没有收藏回调时不应显示收藏按钮',
    );
    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '翻译按钮仍应存在',
    );
  });

  testWidgets('长按词块并划过相邻词即可选中短语', (WidgetTester tester) async {
    // 用户反馈：「第一行的字幕比较容易被选择，但第二行的字幕进行短语选择
    // 的时候选择不了」。
    //
    // 根因：列表是 ListView（可滚动）、每个词块各自是 InkWell（要点词查词），
    // 两者与 SelectionArea 的手势竞争在这一结构下不可靠 —— 实测长按词块
    // 无法稳定产生系统文本选中。
    // 因此改为显式手势：长按起点词 → 划过相邻词 → 直接得到短语。
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    // 从第二句里的 "saying" 划到 "neighborhood"
    final Rect startRect = tester.getRect(find.text('saying').first);
    final Rect endRect = tester.getRect(find.text('neighborhood').first);

    final TestGesture gesture = await tester.startGesture(startRect.center);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(endRect.center);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '拖选后应出现提示条',
    );
    expect(
      find.text('saying our neighborhood'),
      findsWidgets,
      reason: '应选中从起点到终点的完整短语',
    );
  });

  testWidgets('触屏：长按后向右划（Android 式触摸拖动）也能选中短语', (WidgetTester tester) async {
    // 前面的测试用单步 moveTo 直接跳到终点；
    // 真机手指滑动是**多步**移动，这里用分步移动复现触屏事件序列，
    // 确认逐步移动时命中判定依然有效（steps 少会漏判中间词块）。
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final Rect startRect = tester.getRect(find.text('saying').first);
    final Rect endRect = tester.getRect(find.text('neighborhood').first);

    final TestGesture gesture = await tester.startGesture(startRect.center);
    // 触屏长按需要超过 longPress 超时
    await tester.pump(const Duration(milliseconds: 700));
    // 分 5 步移动到终点，模拟手指滑动
    final Offset delta = endRect.center - startRect.center;
    for (int i = 1; i <= 5; i++) {
      await gesture.moveTo(startRect.center + delta * (i / 5));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '触屏长按拖动后应出现提示条',
    );
    expect(
      find.byKey(const ValueKey<String>('subtitle-collect-selection')),
      findsOneWidget,
      reason: '收藏按钮也应出现',
    );
  });

  testWidgets('非当前句（列表里的第二行）也能长按划过选中短语', (WidgetTester tester) async {
    // 用户反馈（0.3.4 之后）：逐句精读里选择短语时，
    //「第二行的翻译选择不了」。
    //
    // 根因：手势只在**当前播放句**上挂载 ——
    //   onLongPressStart: isActiveLine ? ... : null
    // 列表默认显示全部句子（showCurrentOnly = false），
    // 于是除当前句以外的每一行（用户眼里的「第二行」）长按毫无反应。
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 当前播放句是第一行；用户在第二行上做短语选择。
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final Rect startRect = tester.getRect(find.text('selection').first);
    final Rect endRect = tester.getRect(find.text('test.').first);

    final TestGesture gesture = await tester.startGesture(startRect.center);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(endRect.center);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '非当前句上也应能选短语并出现提示条',
    );
    expect(
      find.text('selection test.'),
      findsWidgets,
      reason: '应选中第二行里的短语',
    );
  });

  testWidgets('非当前句上选中的短语，翻译上下文用的是该句而不是当前播放句', (
    WidgetTester tester,
  ) async {
    // 与上一条同源：允许在任意行选择之后，
    // 「翻译选中」带的上下文必须是所选短语所在的句子，
    // 否则同一个短语会被放到错误的语境里解释。
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(activeIndex: 1));
    await tester.pumpAndSettle();

    final Rect startRect = tester.getRect(find.text('saying').first);
    final Rect endRect = tester.getRect(find.text('neighborhood').first);

    final TestGesture gesture = await tester.startGesture(startRect.center);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(endRect.center);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
    );
    await tester.pumpAndSettle();

    expect(lastLookup?.word, 'saying our neighborhood');
    expect(
      lastLookup?.context,
      contains('Garden of Eden'),
      reason: '上下文必须是短语所在的第一行，而不是当前播放的第二行',
    );
  });

  testWidgets('macOS：鼠标长按并划过（第二行）同样能选中短语', (WidgetTester tester) async {
    // 桌面端用的是鼠标，不是手指。这里用 PointerDeviceKind.mouse
    // 走一遍同样的手势，确认 macOS 上这条路径真的通
    // —— 用户报的正是「mac 版本」选不中第二行。
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final Rect startRect = tester.getRect(find.text('selection').first);
    final Rect endRect = tester.getRect(find.text('test.').first);

    final TestGesture gesture = await tester.startGesture(
      startRect.center,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(endRect.center);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '鼠标长按拖动后也应出现提示条',
    );
    expect(find.text('selection test.'), findsWidgets);
  });

  testWidgets('macOS：鼠标「按下即拖」（不先按住 0.5 秒）也应能选中短语', (
    WidgetTester tester,
  ) async {
    // 真实鼠标操作是「按下 → 立刻横向拖」，不会先在原地停 0.5 秒。
    // 长按手势在这种情况下会因为超过 touch slop 而被判失败。
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final Rect startRect = tester.getRect(find.text('selection').first);
    final Rect endRect = tester.getRect(find.text('test.').first);

    final TestGesture gesture = await tester.startGesture(
      startRect.center,
      kind: PointerDeviceKind.mouse,
    );
    // 只过一帧就开始拖，模拟「按下即拖」。
    await tester.pump(const Duration(milliseconds: 16));
    final Offset delta = endRect.center - startRect.center;
    for (int i = 1; i <= 6; i++) {
      await gesture.moveTo(startRect.center + delta * (i / 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '鼠标按下即拖（桌面式选择）也应出现提示条',
    );
    expect(find.text('selection test.'), findsWidgets);
  });

  testWidgets('macOS：在可滚动的列表上纵向拖动是滚动，横向拖动才是划词', (
    WidgetTester tester,
  ) async {
    // 加了横向拖动识别器之后必须确认没把列表滚动抢掉：
    // 手势竞技场按方向裁决，纵向拖动应归 ListView。
    //
    // 注意列表必须**真的能滚**（内容超过一屏）。列表装得下时
    // Scrollable 压根不注册纵向拖动识别器，测不出真实行为。
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(subtitleLines: manyLines()));
    await tester.pumpAndSettle();

    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final double before = scrollable.position.pixels;

    final Rect startRect = tester.getRect(find.text('Row').first);
    // 用触摸指针：Flutter 的 MaterialScrollBehavior 默认不把鼠标算进
    // dragDevices（桌面用滚轮滚动），鼠标拖动本来就不该滚动列表。
    final TestGesture gesture = await tester.startGesture(startRect.center);
    await tester.pump(const Duration(milliseconds: 16));
    // 纯纵向拖动。
    for (int i = 1; i <= 6; i++) {
      await gesture.moveTo(startRect.center + Offset(0, -12.0 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      scrollable.position.pixels,
      isNot(before),
      reason: '纵向拖动应该滚动列表，而不是被横向拖动识别器抢走',
    );
  });

  testWidgets('macOS：可滚动的长列表上，横向划过同样能选中短语', (
    WidgetTester tester,
  ) async {
    // 真实使用场景就是长列表（很多句字幕）。在**能滚动**的前提下，
    // 横向拖动要能赢下手势竞技场，否则用户还是选不中。
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(subtitleLines: manyLines()));
    await tester.pumpAndSettle();

    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final double before = scrollable.position.pixels;

    final Rect startRect = tester.getRect(find.text('scrollable').first);
    final Rect endRect = tester.getRect(find.text('for').first);

    final TestGesture gesture = await tester.startGesture(
      startRect.center,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    final Offset delta = endRect.center - startRect.center;
    for (int i = 1; i <= 6; i++) {
      await gesture.moveTo(startRect.center + delta * (i / 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '长列表上横向划过也应出现提示条',
    );
    expect(find.text('scrollable for'), findsWidgets);
    expect(
      scrollable.position.pixels,
      before,
      reason: '横向划词不应把列表滚动掉',
    );
  });
  testWidgets('单中模式下长按中文也能选短语（原先中文完全不可选）', (
    WidgetTester tester,
  ) async {
    // 用户反馈：「逐句精听的情况下，想选择句子里的短语看翻译」选不了。
    //
    // 根因：英文走 _buildWordLine（每个词块挂手势，可选），
    // 而**中文在任何模式下都是普通 Text**；单中模式下连英文也只是
    // 普通 Text —— 于是整句都没有可选区域。
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(subtitleMode: '单中'));
    await tester.pumpAndSettle();

    // 中文句子应当被切成可选词块。
    // 这里用「科学」与「让」两个词做长按拖动。
    final Rect startRect = tester.getRect(find.text('科学').first);
    final Rect endRect = tester.getRect(find.text('让我').first);

    final TestGesture gesture = await tester.startGesture(startRect.center);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(endRect.center);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '单中模式下也应当能选中中文短语并出现提示条',
    );
  });

  testWidgets('双语模式下长按中文短语也能选中', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    // 中文按 2 字滑窗分词：没人 / 人说 / 说我们 / 我们 / 们社 / …
    final Rect startRect = tester.getRect(find.text('没人').first);
    final Rect endRect = tester.getRect(find.text('人说').first);

    final TestGesture gesture = await tester.startGesture(startRect.center);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(endRect.center);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('subtitle-translate-selection')),
      findsOneWidget,
      reason: '双语模式下的中文行也应可选择',
    );
  });
}
