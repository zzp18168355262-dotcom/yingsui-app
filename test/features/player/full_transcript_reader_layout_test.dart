/// 逐词全文嵌入播放页后的**布局自适应**测试。
///
/// 回归背景：头部工具栏（书籍图标 + 标题 + 翻译开关 + 听全文 + 定位 + 关闭）
/// 在手机竖屏宽度下会横向溢出（实测 390 逻辑像素溢出 25px），
/// 界面上会出现黄黑条纹警告。现在头部按可用宽度切换紧凑形态：
/// 隐藏图标与文字标签、把「听全文」收成图标按钮。
///
/// 这里覆盖手机竖屏、窄屏与平板三种宽度，确保不再溢出。
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart' show Override;
import 'package:yingsui/features/player/presentation/full_transcript_reader.dart';
import 'package:yingsui/features/player/presentation/player_mock_state.dart';
import 'package:yingsui/features/shared/data/word_lookup_service.dart';

const TranscriptReaderSnapshot _snap = TranscriptReaderSnapshot(
  courseTitle: 'S01',
  episodeTitle: '第 01 集',
  lines: <PlayerSubtitleLine>[
    PlayerSubtitleLine(
      startTime: '00:10',
      english: 'Hell, some people say God avoids this place altogether.',
      chinese: '见鬼，有人说上帝完全避开这个地方。',
      startMs: 10000,
      endMs: 14000,
    ),
  ],
  meanings: <String, String>{},
  progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
);

Widget _wrap(double width, double videoHeight) {
  return ProviderScope(
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
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 844)),
        child: Scaffold(
          body: Column(
            children: <Widget>[
              Container(height: videoHeight, color: Colors.black),
              Expanded(
                child: FullTranscriptReaderScreen(
                  embedded: true,
                  snapshot: _snap,
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
      ),
    ),
  );
}

void main() {
  for (final (String label, double width, double videoHeight) in <
    (String, double, double)
  >[
    ('手机竖屏 390', 390, 400),
    ('窄屏 320', 320, 380),
    ('平板 1024', 1024, 500),
  ]) {
    testWidgets('$label 下不溢出', (WidgetTester tester) async {
      tester.view.physicalSize = Size(width * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(width, videoHeight));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('00:10'), findsWidgets);
    });
  }
}
