import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/domain/word_lookup_entry.dart';
import 'full_transcript_reader.dart';

const String transcriptReaderWindowType = 'full-transcript-reader';

typedef TranscriptReaderWordLookup =
    Future<WordLookupEntry> Function({
      required String rawWord,
      required String contextSentence,
    });

typedef TranscriptReaderLineLoop = Future<void> Function(int lineIndex);
typedef TranscriptReaderFullPlayback = Future<void> Function();
typedef TranscriptReaderSentenceTranslation =
    Future<String?> Function(String sentence);

/// 是否把「逐词全文」开成**独立的原生窗口**。
///
/// 结论来自用户的多轮反馈：
///   - 应用内全屏页：会把播放页整个盖住，看不到视频；
///   - 页内嵌入/浮动窗格：阅读区太小，且会被播放页内容遮挡。
/// 用户明确要求「单独的页面」「单独弹出一个窗格」——即与播放器并存的
/// 独立窗口。
///
/// 移动端没有多窗口概念，仍走应用内整页（fullscreenDialog）。
bool get supportsTranscriptReaderWindow =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

class TranscriptReaderSession {
  final ValueNotifier<TranscriptReaderProgress> progress =
      ValueNotifier<TranscriptReaderProgress>(
        const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
      );

  WindowController? _desktopWindow;
  WindowController? _mainWindow;
  TranscriptReaderWordLookup? _lookupWord;
  TranscriptReaderLineLoop? _toggleLineLoop;
  TranscriptReaderFullPlayback? _playFullTranscript;
  TranscriptReaderSentenceTranslation? _translateSentence;
  bool _sendingProgress = false;
  TranscriptReaderProgress? _lastSentProgress;

  Future<void> open({
    required BuildContext context,
    required TranscriptReaderSnapshot snapshot,
    required TranscriptReaderWordLookup lookupWord,
    TranscriptReaderLineLoop? toggleLineLoop,
    TranscriptReaderFullPlayback? playFullTranscript,
    TranscriptReaderSentenceTranslation? translateSentence,
  }) async {
    progress.value = snapshot.progress;
    if (!supportsTranscriptReaderWindow) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (BuildContext routeContext) => FullTranscriptReaderScreen(
            snapshot: snapshot,
            progressListenable: progress,
            onPlayFullTranscript: playFullTranscript,
            onToggleLineLoop: toggleLineLoop,
            onClose: () => Navigator.of(routeContext).pop(),
          ),
        ),
      );
      return;
    }

    final WindowController mainWindow =
        await WindowController.fromCurrentEngine();
    _lookupWord = lookupWord;
    _toggleLineLoop = toggleLineLoop;
    _playFullTranscript = playFullTranscript;
    _translateSentence = translateSentence;
    await mainWindow.setWindowMethodHandler(_handleMainWindowMethod);
    _mainWindow = mainWindow;

    final String arguments = jsonEncode(<String, dynamic>{
      'type': transcriptReaderWindowType,
      'parentWindowId': mainWindow.windowId,
      'snapshot': snapshot.toJson(),
    });
    final List<WindowController> windows = await WindowController.getAll();
    for (final WindowController window in windows) {
      if (!_isTranscriptReaderArguments(window.arguments)) continue;
      try {
        await window.invokeMethod<void>('replaceSnapshot', snapshot.toJson());
        await window.invokeMethod<void>('focus');
        await window.show();
        _desktopWindow = window;
        _scheduleProgressSend();
        return;
      } catch (_) {
        // The native window can disappear between discovery and invocation.
      }
    }

    final WindowController window = await WindowController.create(
      WindowConfiguration(arguments: arguments),
    );
    _desktopWindow = window;
    await window.show();
    _scheduleProgressSend();
  }

  void updateProgress({
    required int lineIndex,
    required int wordIndex,
    int? loopingLineIndex,
  }) {
    final TranscriptReaderProgress next = TranscriptReaderProgress(
      lineIndex: lineIndex,
      wordIndex: wordIndex,
      loopingLineIndex: loopingLineIndex,
    );
    if (progress.value.lineIndex == next.lineIndex &&
        progress.value.wordIndex == next.wordIndex &&
        progress.value.loopingLineIndex == next.loopingLineIndex) {
      return;
    }
    progress.value = next;
    _scheduleProgressSend();
  }

  void _scheduleProgressSend() {
    if (_sendingProgress || _desktopWindow == null) return;
    unawaited(_flushProgress());
  }

  Future<void> _flushProgress() async {
    final WindowController? window = _desktopWindow;
    if (window == null || _sendingProgress) return;
    _sendingProgress = true;
    try {
      while (_desktopWindow == window) {
        final TranscriptReaderProgress target = progress.value;
        if (_sameProgress(_lastSentProgress, target)) return;
        final bool sent = await sendTranscriptReaderProgressWithRetry(
          progress: target,
          send: (TranscriptReaderProgress value) async {
            final Map<dynamic, dynamic>? acknowledged = await window
                .invokeMethod<Map<dynamic, dynamic>>(
                  'progress',
                  value.toJson(),
                );
            if (acknowledged == null ||
                !_sameProgress(
                  TranscriptReaderProgress.fromJson(acknowledged),
                  value,
                )) {
              throw StateError('Transcript reader progress was not applied');
            }
          },
        );
        if (!sent) {
          final List<WindowController> windows =
              await WindowController.getAll();
          if (!windows.any(
            (WindowController item) => item.windowId == window.windowId,
          )) {
            _desktopWindow = null;
          }
          return;
        }
        _lastSentProgress = target;
        if (_sameProgress(progress.value, target)) return;
      }
    } finally {
      _sendingProgress = false;
    }
  }

  void dispose() {
    final WindowController? mainWindow = _mainWindow;
    _toggleLineLoop = null;
    _playFullTranscript = null;
    if (mainWindow != null && _desktopWindow == null) {
      unawaited(mainWindow.setWindowMethodHandler(null));
    }
    progress.dispose();
  }

  Future<dynamic> _handleMainWindowMethod(MethodCall call) async {
    if (call.method == 'playFullTranscript') {
      final TranscriptReaderFullPlayback? playFullTranscript =
          _playFullTranscript;
      if (playFullTranscript == null) {
        throw StateError('Transcript reader full playback is unavailable');
      }
      await playFullTranscript();
      return null;
    }
    if (call.method == 'toggleLineLoop') {
      final TranscriptReaderLineLoop? toggleLineLoop = _toggleLineLoop;
      if (toggleLineLoop == null) {
        throw StateError('Transcript reader line loop is unavailable');
      }
      await toggleLineLoop(call.arguments as int? ?? 0);
      return progress.value.toJson();
    }
    if (call.method == 'translateSentence') {
      final TranscriptReaderSentenceTranslation? translateSentence =
          _translateSentence;
      if (translateSentence == null) return null;
      return translateSentence(call.arguments as String? ?? '');
    }
    if (call.method != 'lookupWord') {
      throw MissingPluginException('Unknown reader request: ${call.method}');
    }
    final TranscriptReaderWordLookup? lookupWord = _lookupWord;
    if (lookupWord == null) {
      throw StateError('Transcript reader lookup is unavailable');
    }
    final Map<dynamic, dynamic> arguments =
        call.arguments as Map<dynamic, dynamic>;
    final WordLookupEntry entry = await lookupWord(
      rawWord: arguments['rawWord'] as String? ?? '',
      contextSentence: arguments['contextSentence'] as String? ?? '',
    );
    return entry.toJson();
  }
}

@visibleForTesting
Future<bool> sendTranscriptReaderProgressWithRetry({
  required TranscriptReaderProgress progress,
  required Future<void> Function(TranscriptReaderProgress progress) send,
  int maxAttempts = 10,
  Duration retryDelay = const Duration(milliseconds: 100),
}) async {
  for (int attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      await send(progress);
      return true;
    } catch (_) {
      if (attempt == maxAttempts - 1) return false;
      await Future<void>.delayed(retryDelay);
    }
  }
  return false;
}

bool _sameProgress(
  TranscriptReaderProgress? left,
  TranscriptReaderProgress right,
) =>
    left?.lineIndex == right.lineIndex &&
    left?.wordIndex == right.wordIndex &&
    left?.loopingLineIndex == right.loopingLineIndex;

bool _isTranscriptReaderArguments(String arguments) {
  try {
    final Object? decoded = jsonDecode(arguments);
    return decoded is Map<String, dynamic> &&
        decoded['type'] == transcriptReaderWindowType;
  } catch (_) {
    return false;
  }
}
