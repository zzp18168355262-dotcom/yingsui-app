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

  testWidgets('头部控件尺寸统一（高度与基准线一致）', (WidgetTester tester) async {
    // 用户反馈：「这边的 ui 重新调整一下，太丑了，大小不统一」。
    // 实测原先 Switch 40、定位按钮 40、听全文按钮 26 —— 三种高度、基准线不齐。
    // Material 默认会给按钮留最小点按区域（compact 下 40），
    // 仅设 constraints 不够，必须显式设 materialTapTargetSize 为 shrinkWrap。
    tester.view.physicalSize = const Size(1400, 800);
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
          home: FullTranscriptReaderScreen(
            snapshot: const TranscriptReaderSnapshot(
              courseTitle: 'S01',
              episodeTitle: '第 01 集',
              lines: PlayerMockState.fallbackLines,
              meanings: <String, String>{},
              progress: TranscriptReaderProgress(
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
    );
    await tester.pumpAndSettle();

    final Rect switchRect = tester.getRect(find.byType(Switch));
    final Rect listenRect = tester.getRect(
      find.byKey(const ValueKey<String>('reader-play-full-transcript')),
    );
    final Rect locateRect = tester.getRect(
      find.byKey(const ValueKey<String>('reader-locate-current-word')),
    );

    // 三者高度必须一致。
    expect(
      listenRect.height,
      closeTo(switchRect.height, 1),
      reason: '听全文按钮与开关高度应一致',
    );
    expect(
      locateRect.height,
      closeTo(switchRect.height, 1),
      reason: '定位按钮与开关高度应一致',
    );
    // 基准线（垂直中心）也必须一致。
    expect(
      listenRect.center.dy,
      closeTo(switchRect.center.dy, 1.5),
      reason: '听全文按钮应与开关在同一条基准线上',
    );
    expect(
      locateRect.center.dy,
      closeTo(switchRect.center.dy, 1.5),
      reason: '定位按钮应与开关在同一条基准线上',
    );
  });
}
