/// AI 字幕进度对话框必须**任何情况下都能关掉**。
///
/// 用户反馈「有时候会卡住，出现灰白遮罩」：原先该对话框是
/// `barrierDismissible: false` + `canPop: false` 且没有任何关闭入口，
/// 一旦调用方没能成功 pop，用户就被永久困在遮罩之后，只能杀进程。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/asr_subtitle_service.dart';
import 'package:yingsui/features/player/presentation/widgets/ai_subtitle_generation_progress_dialog.dart';

void main() {
  testWidgets('有取消按钮，点击后对话框关闭', (WidgetTester tester) async {
    final ValueNotifier<AsrSubtitleProgress> progress =
        ValueNotifier<AsrSubtitleProgress>(
          const AsrSubtitleProgress(completedChunks: 1, totalChunks: 4),
        );
    addTearDown(progress.dispose);
    bool cancelled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showAiSubtitleGenerationProgressDialog(
                    context: context,
                    progress: progress,
                    onCancel: () => cancelled = true,
                  );
                },
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在生成 AI 词级字幕'), findsOneWidget);

    await tester.tap(find.text('取消生成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(cancelled, isTrue, reason: '取消应回调到调用方以中止任务');
    expect(
      find.text('正在生成 AI 词级字幕'),
      findsNothing,
      reason: '对话框必须真的关闭，否则用户会卡在遮罩后面',
    );
  });

  testWidgets('可以点遮罩外部关闭（兜底）', (WidgetTester tester) async {
    final ValueNotifier<AsrSubtitleProgress> progress =
        ValueNotifier<AsrSubtitleProgress>(
          const AsrSubtitleProgress(completedChunks: 0, totalChunks: 0),
        );
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAiSubtitleGenerationProgressDialog(
                  context: context,
                  progress: progress,
                ),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在生成 AI 词级字幕'), findsOneWidget);

    // 点击对话框外部（左上角）。
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('正在生成 AI 词级字幕'),
      findsNothing,
      reason: '点外部应能关闭，避免用户被困',
    );
  });
}
