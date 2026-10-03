/// 手机上「逐词全文」应当**内联顶替**逐句精听面板，且窄屏不溢出。
///
/// 用户要求：点全文阅读后，阅读页顶替逐句精听的位置，视频保持可见；
/// 全文阅读的字体与 UI 也要适配手机。
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/full_transcript_reader.dart';
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/shared/data/word_lookup_service.dart';

TranscriptReaderSnapshot snapshot() {
  return const TranscriptReaderSnapshot(
    courseTitle: 'WeiXin',
    episodeTitle: '第 19 集',
    lines: <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:35',
        english: 'You think the man would have manslaughter down by now.',
        chinese: '你觉得这人到现在该把过失杀人练熟了吧。',
        startMs: 35000,
        endMs: 39000,
      ),
      PlayerSubtitleLine(
        startTime: '00:40',
        english: "What'd that set you back about six bills.",
        chinese: '那花了你六百块吧。',
        startMs: 40000,
        endMs: 44000,
      ),
    ],
    meanings: <String, String>{'manslaughter': 'n. 过失杀人'},
    progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
  );
}

void main() {
  testWidgets('360dp 手机上嵌入渲染不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
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
                    data: <String, dynamic>{'choices': <dynamic>[]},
                  ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                // 代表视频区。
                const SizedBox(height: 200, child: ColoredBox(color: Colors.black)),
                Expanded(
                  child: FullTranscriptReaderScreen(
                    embedded: true,
                    snapshot: snapshot(),
                    progressListenable:
                        ValueNotifier<TranscriptReaderProgress>(
                          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
                        ),
                    onClose: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      tester.takeException(),
      isNull,
      reason: '手机窄屏下嵌入渲染阅读器不应抛布局异常',
    );
    // 嵌入模式不应自带 Scaffold（否则会盖住视频）。
    expect(
      find.byType(Scaffold),
      findsOneWidget,
      reason: '嵌入模式不应再套一层 Scaffold',
    );
  });
}
