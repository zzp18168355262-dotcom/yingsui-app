/// 逐词全文头部高度。
///
/// 用户反馈：头部占比太大，导致全文阅读区很小。
/// 原先头部约 90px（内边距 + 42px 图标 + 默认 48px 的按钮）。
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart' show Override;
import 'package:yingsui/features/player/presentation/full_transcript_reader.dart';
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/shared/data/word_lookup_service.dart';

void main() {
  testWidgets('头部高度已收紧（不再挤占阅读区）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
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
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: FullTranscriptReaderScreen(
                embedded: true,
                snapshot: TranscriptReaderSnapshot(
                  courseTitle: 'S01',
                  episodeTitle: '第 01 集',
                  lines: <PlayerSubtitleLine>[
                    PlayerMockState.fallbackLines.first,
                  ],
                  meanings: const <String, String>{},
                  progress: const TranscriptReaderProgress(
                    lineIndex: 0,
                    wordIndex: 0,
                  ),
                ),
                progressListenable: ValueNotifier<TranscriptReaderProgress>(
                  const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
                ),
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 头部是内容区第一个 Container（白底 + 下边框）。用标题所在行的高度近似。
    final Rect titleRect = tester.getRect(find.text('S01'));

    // 直接量「课程标题」下方到列表顶部之间不该再有过多留白：
    // 用整个阅读器的第一个 Container 高度作为头部高度。
    final Finder containers = find.descendant(
      of: find.byType(FullTranscriptReaderScreen),
      matching: find.byType(Container),
    );
    double headerHeight = 0;
    for (int i = 0; i < containers.evaluate().length; i += 1) {
      final Rect r = tester.getRect(containers.at(i));
      if (r.width > 300 && r.height > 20 && r.height < 120) {
        headerHeight = r.height;
        break;
      }
    }

    expect(
      headerHeight,
      lessThan(64),
      reason: '头部应收紧到 64 以下（原先约 90）',
    );
    // 标题本身确实渲染了（避免上面的查找落空导致误判）。
    expect(titleRect.height, greaterThan(0));
  });
}
