/// 逐词全文在**独立整页**形态下是否跟随视频进度。
///
/// 用户提问：全文阅读是否跟着视频走。
///
/// 链路：播放页把 state.activeLineIndex 推给
/// TranscriptReaderSession.progress（一个 ValueNotifier），
/// 阅读器监听它并在变化时滚动到当前词。
///
/// 此前阅读器内部的滚动有缺陷：目标行未被构建时用「按行索引比例」
/// 估算位置，而行高不均匀，估算偏小会让目标行仍落在视口外，
/// 随后的真实几何校正因 key 拿不到 context 而失效
/// —— 表现为「阅读区和视频对不上」。
/// 本测试验证该滚动确实发生。
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Override 由 riverpod 内部导出，flutter_riverpod 不转出该类型。
import 'package:riverpod/src/framework.dart' show Override;
import 'package:yingsui/features/player/presentation/full_transcript_reader.dart';
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/shared/data/word_lookup_service.dart';

/// 构造**行高不均匀**的字幕数据。
///
/// 关键：只有部分句子有中文译文（真实数据里就是这样，
/// 翻译未完成的句子没有译文），行高因此不同。
/// 若测试数据行高完全均匀，「按行索引比例」的估算恰好准确，
/// 就测不出真实场景下的偏差（先前的测试正是因此失效）。
List<PlayerSubtitleLine> manyLines(int count) {
  return List<PlayerSubtitleLine>.generate(
    count,
    (int i) => PlayerSubtitleLine(
      startTime: '00:${i.toString().padLeft(2, '0')}',
      english: 'line $i english text that is reasonably long here',
      // 每三句才有一句译文，制造高度差。
      chinese: i % 3 == 0 ? '第 $i 句中文译文内容' : '',
      startMs: i * 5000,
      endMs: i * 5000 + 4000,
      // 部分句子带词级时间轴，同样影响行高。
      words: i.isEven
          ? <PlayerSubtitleWord>[
              PlayerSubtitleWord(
                text: 'line',
                startMs: i * 5000,
                endMs: i * 5000 + 2000,
              ),
            ]
          : const <PlayerSubtitleWord>[],
    ),
  );
}

Widget page(
  ValueNotifier<TranscriptReaderProgress> progress, {
  required int total,
}) {
  return ProviderScope(
    overrides: <Override>[
      // 阅读器内的逐句翻译会自动请求接口，测试需覆盖以免真的联网。
      wordLookupServiceProvider.overrideWithValue(
        WordLookupService(
          httpRequestOverride:
              ({
                required BaseOptions options,
                required String method,
                required String path,
                Map<String, dynamic>? queryParameters,
                Object? data,
              }) async => Response<dynamic>(
                requestOptions: RequestOptions(path: path),
                statusCode: 200,
                data: <String, dynamic>{
                  'choices': <dynamic>[
                    <String, dynamic>{
                      'message': <String, dynamic>{'content': '译文'},
                    },
                  ],
                },
              ),
        ),
      ),
    ],
    child: MaterialApp(
      home: FullTranscriptReaderScreen(
        snapshot: TranscriptReaderSnapshot(
          courseTitle: 'S01',
          episodeTitle: '第 01 集',
          lines: manyLines(total),
          meanings: const <String, String>{},
          progress: const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
        ),
        progressListenable: progress,
        onClose: () {},
      ),
    ),
  );
}

void main() {
  testWidgets('进度推进时阅读器会滚动到当前句', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
        );
    addTearDown(progress.dispose);

    await tester.pumpWidget(page(progress, total: 40));
    await tester.pumpAndSettle();

    final Finder listView = find.byType(ListView);
    expect(listView, findsOneWidget);
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.descendant(of: listView, matching: find.byType(Scrollable)),
    );
    final double before = scrollable.position.pixels;

    // 模拟视频推进到较靠后的一句。
    progress.value = const TranscriptReaderProgress(
      lineIndex: 25,
      wordIndex: 0,
    );
    await tester.pumpAndSettle();

    final double after = scrollable.position.pixels;
    expect(
      after,
      greaterThan(before + 100),
      reason: '进度推进后阅读器应滚动，而不是停在原地',
    );

    // 关键断言：目标句必须真的进入视口。
    //
    // 只断言「滚动位置变大了」并不够 —— 位置动了但目标行仍在视口外，
    // 正是用户看到的「阅读区和视频对不上」。
    // 注意：阅读器把句子拆成**独立单词 widget**（逐词释义），
    // 因此不能按整句查找；这里用每行唯一的时间戳判定该行已渲染。
    expect(
      find.text('00:25'),
      findsWidgets,
      reason: '跟随之后第 25 句应进入视口',
    );

    // 再推进一次，仍应继续跟随，且同样要真的可见。
    final double secondBefore = after;
    progress.value = const TranscriptReaderProgress(
      lineIndex: 32,
      wordIndex: 0,
    );
    await tester.pumpAndSettle();
    expect(
      scrollable.position.pixels,
      greaterThan(secondBefore),
      reason: '连续推进时应持续跟随',
    );
    expect(
      find.text('00:32'),
      findsWidgets,
      reason: '连续推进后第 32 句也应进入视口',
    );
  });

  testWidgets('页面上选中过文本后，进度推进仍会跟随', (WidgetTester tester) async {
    // 用户实际使用中常常在阅读区点选/划选文字（查词、复制）。
    // 原先只要「有文本被选中」就跳过跟随，表现为
    // 「一开始能跟，选中一次之后就对不上了」。
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
        );
    addTearDown(progress.dispose);

    await tester.pumpWidget(page(progress, total: 40));
    await tester.pumpAndSettle();

    // 在阅读区上划选一段文字。
    final Finder listView = find.byType(ListView);
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(listView),
    );
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.descendant(of: listView, matching: find.byType(Scrollable)),
    );
    final double before = scrollable.position.pixels;

    progress.value = const TranscriptReaderProgress(
      lineIndex: 28,
      wordIndex: 0,
    );
    await tester.pumpAndSettle();

    expect(
      scrollable.position.pixels,
      greaterThan(before + 100),
      reason: '选中过文本后，进度推进仍应带动阅读区滚动',
    );
    expect(
      find.text('00:28'),
      findsWidgets,
      reason: '目标句应进入视口',
    );
  });
}
