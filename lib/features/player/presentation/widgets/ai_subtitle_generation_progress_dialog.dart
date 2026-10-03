import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../asr_subtitle_service.dart';

/// 显示生成进度。
///
/// 用户反馈过「有时候会卡住，出现灰白遮罩」。原先这个对话框是
/// `barrierDismissible: false` + `canPop: false` 且**没有任何关闭入口**：
/// 一旦调用方没能成功 pop（异常、路由被顶替等），用户就被永久困在
/// 遮罩之后，只能杀进程。现在提供明确的取消按钮、允许返回键关闭、
/// 并允许点外部关闭，保证任何情况下都能退出。
/// 进度对话框的句柄。
///
/// 返回它（而不是裸 Future）是为了让调用方能**精确关闭这个对话框**：
/// 只用 `Navigator.pop()` 在栈顶不是它时会误弹别的路由，
/// 而只 await Future 又可能在 pop 失效时永远等待 ——
/// 两者都会让用户卡在灰白遮罩后面。
class AiSubtitleProgressDialogHandle {
  AiSubtitleProgressDialogHandle({
    required this.route,
    required this.closed,
  });

  final DialogRoute<void> route;

  /// 对话框退场后完成。
  final Future<void> closed;

  /// 关闭对话框；重复调用或已关闭时安全返回。
  Future<void> close() async {
    if (route.isActive) {
      route.navigator?.removeRoute(route);
    }
    await closed.catchError((Object _) {});
  }
}

AiSubtitleProgressDialogHandle showAiSubtitleGenerationProgressDialog({
  required BuildContext context,
  required ValueListenable<AsrSubtitleProgress> progress,
  VoidCallback? onCancel,
}) {
  final DialogRoute<void> route = DialogRoute<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return PopScope(
        child: AlertDialog(
          title: const Text('正在生成 AI 词级字幕'),
          content: ValueListenableBuilder<AsrSubtitleProgress>(
            valueListenable: progress,
            builder:
                (
                  BuildContext context,
                  AsrSubtitleProgress value,
                  Widget? child,
                ) => SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      LinearProgressIndicator(
                        value: value.totalChunks == 0 ? null : value.value,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        value.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        value.previewText?.isNotEmpty ?? false
                            ? value.previewText!
                            : '等待识别文本...',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '生成期间无需重复点击，完成后会自动切换。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF5F6368)),
                      ),
                    ],
                  ),
                ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                onCancel?.call();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('取消生成'),
            ),
          ],
        ),
      );
    },
  );
  final Future<void> closed = Navigator.of(context, rootNavigator: true)
      .push<void>(route)
      .then<void>((void _) {}, onError: (Object _, StackTrace __) {});
  return AiSubtitleProgressDialogHandle(route: route, closed: closed);
}
