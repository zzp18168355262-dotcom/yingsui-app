import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 录音状态。
enum ShadowingRecordStatus {
  /// 尚未录制。
  idle,

  /// 正在录音。
  recording,

  /// 录音暂停。
  paused,

  /// 已录好，等待回放。
  recorded,
}

@immutable
class ShadowingRecordState {
  const ShadowingRecordState({
    this.status = ShadowingRecordStatus.idle,
    this.filePath,
    this.lineKey,
    this.elapsed = Duration.zero,
    this.error,
  });

  final ShadowingRecordStatus status;

  /// 录音文件路径（仅当前平台为 IO 时有值）。
  final String? filePath;

  /// 这条录音对应哪一句（用于「切句后录音失效」的判断）。
  final String? lineKey;

  final Duration elapsed;

  final String? error;

  bool get isRecording => status == ShadowingRecordStatus.recording;
  bool get isPaused => status == ShadowingRecordStatus.paused;
  bool get hasRecording =>
      status == ShadowingRecordStatus.recorded && filePath != null;

  /// 本次对比是否对指定句子有效。
  bool matchesLine(String key) => hasRecording && lineKey == key;

  ShadowingRecordState copyWith({
    ShadowingRecordStatus? status,
    String? filePath,
    String? lineKey,
    Duration? elapsed,
    String? error,
    bool clearError = false,
    bool clearFile = false,
  }) {
    return ShadowingRecordState(
      status: status ?? this.status,
      filePath: clearFile ? null : (filePath ?? this.filePath),
      lineKey: clearFile ? null : (lineKey ?? this.lineKey),
      elapsed: elapsed ?? this.elapsed,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 影子跟读录音状态机。
///
/// 只负责「录下用户这一遍」+「把文件交给播放器对比」，
/// 不做打分 —— 产品定位是让用户自己听、自己判断。
class ShadowingRecorder extends Notifier<ShadowingRecordState> {
  AudioRecorder? _recorder;
  Timer? _ticker;

  @override
  ShadowingRecordState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _recorder?.dispose();
      _recorder = null;
    });
    return const ShadowingRecordState();
  }

  AudioRecorder get _engine => _recorder ??= AudioRecorder();

  /// 麦克风权限。返回 false 表示用户拒绝或设备不支持。
  Future<bool> ensurePermission() async {
    try {
      return await _engine.hasPermission();
    } catch (e) {
      state = state.copyWith(error: '无法访问麦克风：$e');
      return false;
    }
  }

  /// 开始录制 [lineKey] 对应的句子。
  Future<void> start(String lineKey) async {
    if (state.isRecording) {
      return;
    }

    // Web 端无法拿到可交给本地播放器的文件路径，明确告知而不是静默失败。
    if (kIsWeb) {
      state = state.copyWith(error: '网页版暂不支持录音跟读，请使用桌面端或手机 App。');
      return;
    }

    if (!await ensurePermission()) {
      state = state.copyWith(error: '需要麦克风权限才能录下你的跟读。请在系统设置里允许后重试。');
      return;
    }

    try {
      final Directory dir = await getTemporaryDirectory();
      final Directory target = Directory('${dir.path}/shadowing_recordings');
      if (!target.existsSync()) {
        target.createSync(recursive: true);
      }
      final String path =
          '${target.path}/line_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _engine.start(const RecordConfig(), path: path);

      state = ShadowingRecordState(
        status: ShadowingRecordStatus.recording,
        filePath: path,
        lineKey: lineKey,
      );
      _startTicker();
    } catch (e) {
      state = state.copyWith(
        status: ShadowingRecordStatus.idle,
        error: '录音启动失败：$e',
        clearFile: true,
      );
    }
  }

  Future<void> pause() async {
    if (!state.isRecording) {
      return;
    }
    try {
      await _engine.pause();
      _ticker?.cancel();
      state = state.copyWith(status: ShadowingRecordStatus.paused);
    } catch (e) {
      state = state.copyWith(error: '暂停失败：$e');
    }
  }

  Future<void> resume() async {
    if (!state.isPaused) {
      return;
    }
    try {
      await _engine.resume();
      state = state.copyWith(status: ShadowingRecordStatus.recording);
      _startTicker();
    } catch (e) {
      state = state.copyWith(error: '继续录音失败：$e');
    }
  }

  /// 结束录音，保留文件供对比回放。
  Future<void> stop() async {
    if (!state.isRecording && !state.isPaused) {
      return;
    }
    _ticker?.cancel();
    try {
      final String? path = await _engine.stop();
      state = state.copyWith(
        status: ShadowingRecordStatus.recorded,
        filePath: path ?? state.filePath,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        status: ShadowingRecordStatus.idle,
        error: '结束录音失败：$e',
        clearFile: true,
      );
    }
  }

  /// 放弃本次录音并删除文件。
  Future<void> discard() async {
    _ticker?.cancel();
    final String? path = state.filePath;
    try {
      if (state.isRecording || state.isPaused) {
        await _engine.cancel();
      }
    } catch (_) {
      // 取消失败不阻塞状态重置。
    }
    if (path != null) {
      try {
        final File f = File(path);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {
        // 删不掉就留给系统清理临时目录。
      }
    }
    state = const ShadowingRecordState();
  }

  /// 切换句子时清掉上一句的录音，避免把 A 句的录音和 B 句对比。
  Future<void> resetForNewLine() async {
    if (state.status == ShadowingRecordStatus.idle) {
      return;
    }
    await discard();
  }

  void clearError() {
    if (state.error != null) {
      state = state.copyWith(clearError: true);
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (state.isRecording) {
        state = state.copyWith(
          elapsed: state.elapsed + const Duration(milliseconds: 200),
        );
      }
    });
  }
}

final NotifierProvider<ShadowingRecorder, ShadowingRecordState>
shadowingRecorderProvider =
    NotifierProvider<ShadowingRecorder, ShadowingRecordState>(
      ShadowingRecorder.new,
    );
