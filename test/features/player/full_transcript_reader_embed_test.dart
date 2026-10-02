import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Override 由 riverpod 内部导出，flutter_riverpod 不转出该类型。
import 'package:riverpod/src/framework.dart' show Override;
import 'package:yingsui/features/player/presentation/full_transcript_reader.dart';
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/shared/data/word_lookup_service.dart';

/// 「逐词全文」必须以**面板**形式呈现，而不是整页跳转。
///
/// 回归背景：该页面最初在桌面端另开一个原生窗口，后来改成应用内全屏路由。
/// 两种形态都会让**视频完全不可见**，而用户看逐词全文时仍然需要视频画面。
/// 因此新增 embedded 模式：不套 Scaffold，由播放页放在内容区，
/// 视频始终留在上方/左侧。
/// 测试用快照。提为顶层常量，避免在函数内反复构造，
/// 也避开 const 相关的 lint 互相冲突。
const TranscriptReaderSnapshot _snapshot = TranscriptReaderSnapshot(
  courseTitle: 'S01',
  episodeTitle: '第 01 集',
  lines: <PlayerSubtitleLine>[
    PlayerSubtitleLine(
      startTime: '00:10',
      english: 'Hell, some people say God avoids this place.',
      chinese: '见鬼，有人说上帝完全避开这个地方。',
      startMs: 10000,
      endMs: 14000,
    ),
  ],
  meanings: <String, String>{'hell': 'n. 地狱'},
  progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
);

void main() {
  Widget wrap({required bool embedded}) {
    return ProviderScope(
      overrides: <Override>[
        // 阅读器内的逐句翻译会自动请求接口；测试必须覆盖，
        // 否则会真的发网络请求（表现为测试长时间挂起）。
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
                        'message': <String, dynamic>{
                          'content': '见鬼，有人说上帝完全避开这个地方。',
                        },
                      },
                    ],
                  },
                ),
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              // 用一个可识别的占位块代表「视频区」。
              const SizedBox(
                key: ValueKey<String>('fake-video'),
                height: 120,
                child: ColoredBox(color: Color(0xFF000000)),
              ),
              Expanded(
                child: FullTranscriptReaderScreen(
                  embedded: embedded,
                  snapshot: _snapshot,
                  progressListenable: ValueNotifier<TranscriptReaderProgress>(
                    const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
                  ),
                  onClose: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('嵌入模式不产生额外的 Scaffold（不会整页覆盖视频）', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(embedded: true));
    await tester.pumpAndSettle();

    // 外层只有一个 Scaffold；嵌入模式不应再套一层。
    expect(find.byType(Scaffold), findsOneWidget);
    // 代表视频的占位块仍然存在 —— 视频没有被全屏页面顶掉。
    expect(find.byKey(const ValueKey<String>('fake-video')), findsOneWidget);
    // 阅读器确实渲染了：时间戳来自 snapshot 里的那一句。
    // （逐词是按 Wrap 拆成多个小 Widget 渲染的，断言整句或单词都不可靠，
    //  这里用时间戳作为「该句已呈现」的稳定标志。）
    expect(find.text('00:10'), findsWidgets, reason: '逐词全文应正常显示');
  });

  testWidgets('非嵌入模式自成一个 Scaffold（独立页面形态仍可用）', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(embedded: false));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsNWidgets(2));
  });
}
