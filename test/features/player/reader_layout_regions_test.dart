/// 全文阅读的区域划分。
///
/// 需求（按用户标注的红色区域）：横屏下
///   左列 = 视频区域 + 全文阅读区域（视频下方）
///   右列 = 字幕区域 + 课程目录区域
/// 即阅读器位于视频下方，而不是与视频左右并列。
///
/// 这里用真实组件验证：阅读器（嵌入模式）与视频面板可共存于同一列，
/// 且阅读区位于视频下方、左对齐。
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart' show Override;
import 'package:yingsui/features/player/presentation/full_transcript_reader.dart';
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/player/presentation/widgets/player_video_panel.dart';
import 'package:yingsui/features/shared/data/word_lookup_service.dart';

void main() {
  testWidgets('阅读器位于视频下方（同一列），且互不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 阅读器内部的逐句翻译会自动请求接口，测试需覆盖，否则会真的联网。
    final WordLookupService stubService = WordLookupService(
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
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          wordLookupServiceProvider.overrideWithValue(stubService),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: <Widget>[
                // 左列：视频（上） + 全文阅读（下）—— 即用户要求的分区。
                Expanded(
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        flex: 7,
                        child: PlayerVideoPanel(
                          key: const ValueKey<String>('video-region'),
                          line: PlayerMockState.fallbackLines.first,
                          isPlaying: false,
                          subtitleMode: '双语',
                          subtitleModes: const <String>['双语'],
                          speed: '1.0×',
                          isShadowing: false,
                          isLooping: false,
                          isMuted: false,
                          volumeLevel: 1,
                          onTogglePlaying: () {},
                          onPreviousLine: () {},
                          onReplayLine: () {},
                          onNextLine: () {},
                          onSeekBackward: () {},
                          onSeekForward: () {},
                          activeIndex: 0,
                          totalLines: 1,
                          onSelectLine: (_) {},
                          onSeek: (_) {},
                          onSpeedSelected: (_) {},
                          onSelectSubtitleMode: (_) {},
                          onToggleShadowing: () {},
                          onToggleLoop: () {},
                          onToggleMuted: () {},
                          onVolumeChanged: (_) {},
                          onToggleFullscreen: () {},
                          onSubtitleLookupOpen: () {},
                          onCollectWord: (_) {},
                          onFavoriteWord: (_) {},
                          onPronounce: () {},
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        flex: 4,
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
                          progressListenable:
                              ValueNotifier<TranscriptReaderProgress>(
                                const TranscriptReaderProgress(
                                  lineIndex: 0,
                                  wordIndex: 0,
                                ),
                              ),
                          onClose: () {},
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 22),
                // 右列：字幕区域（此处以占位块代表）。
                const Expanded(
                  child: ColoredBox(
                    key: ValueKey<String>('subtitle-region'),
                    color: Color(0xFFF8F9FA),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '视频与阅读区共存时不应溢出');

    final Rect video = tester.getRect(
      find.byKey(const ValueKey<String>('video-region')),
    );
    final Rect subtitle = tester.getRect(
      find.byKey(const ValueKey<String>('subtitle-region')),
    );

    // 阅读器应在视频下方、右列左侧。
    final Finder readerFinder = find.byType(FullTranscriptReaderScreen);
    expect(readerFinder, findsOneWidget);
    final Rect reader = tester.getRect(readerFinder);

    expect(
      reader.top,
      greaterThanOrEqualTo(video.bottom),
      reason: '阅读区应位于视频下方（同一列）',
    );
    expect(reader.right, lessThanOrEqualTo(subtitle.left), reason: '阅读区应在左列');
    expect(video.height, greaterThan(reader.height), reason: '视频应仍占主要高度');
  });
}
