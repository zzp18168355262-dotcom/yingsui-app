import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_theme.dart';
import '../shadowing_recorder.dart';

/// 跟读练习面板：录下这一遍，和原声 A/B 对照着听。
///
/// 产品定位是不打分 —— 用户自己的耳朵就是判断标准。
class ShadowingPracticePanel extends ConsumerStatefulWidget {
  const ShadowingPracticePanel({
    super.key,
    required this.lineKey,
    required this.onPlayOriginal,
    required this.onStopOriginal,
    this.compact = false,
  });

  /// 当前句子的唯一标识；换句时录音自动作废，避免张冠李戴。
  final String lineKey;

  /// 播放原声（由播放器宿主实现，复用同一个视频播放器）。
  final VoidCallback onPlayOriginal;

  /// 停止原声，避免和跟读录音回放叠在一起。
  final VoidCallback onStopOriginal;

  final bool compact;

  @override
  ConsumerState<ShadowingPracticePanel> createState() =>
      _ShadowingPracticePanelState();
}

class _ShadowingPracticePanelState
    extends ConsumerState<ShadowingPracticePanel> {
  Player? _player;
  StreamSubscription<bool>? _completedSub;
  bool _playingRecording = false;

  @override
  void didUpdateWidget(ShadowingPracticePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切句后上一句的录音不再适用，直接作废，防止误对比。
    if (oldWidget.lineKey != widget.lineKey) {
      _stopRecordingPlayback();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref.read(shadowingRecorderProvider.notifier).resetForNewLine();
      });
    }
  }

  @override
  void dispose() {
    _completedSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Player get _audioPlayer => _player ??= Player();

  Future<void> _playRecording(String path) async {
    widget.onStopOriginal();
    try {
      await _audioPlayer.open(Media('file://$path'));
      setState(() => _playingRecording = true);
      await _completedSub?.cancel();
      _completedSub = _audioPlayer.stream.completed.listen((bool done) {
        if (done && mounted) {
          setState(() => _playingRecording = false);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _playingRecording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('回放失败：$e')),
        );
      }
    }
  }

  Future<void> _stopRecordingPlayback() async {
    await _completedSub?.cancel();
    try {
      await _player?.stop();
    } catch (_) {
      // 播放器可能尚未创建，忽略。
    }
    if (mounted && _playingRecording) {
      setState(() => _playingRecording = false);
    }
  }

  Future<void> _toggleRecord(ShadowingRecordState state) async {
    final ShadowingRecorder recorder = ref.read(
      shadowingRecorderProvider.notifier,
    );
    if (state.isRecording) {
      await recorder.stop();
      return;
    }
    if (state.isPaused) {
      await recorder.resume();
      return;
    }
    await _stopRecordingPlayback();
    widget.onStopOriginal();
    await recorder.start(widget.lineKey);
  }

  @override
  Widget build(BuildContext context) {
    final ShadowingRecordState state = ref.watch(shadowingRecorderProvider);
    final AppPalette palette = AppColors.of(context);
    final bool active = state.isRecording || state.isPaused;

    // 错误提示用 SnackBar 呈现，避免占位撑高面板。
    ref.listen<ShadowingRecordState>(shadowingRecorderProvider, (
      ShadowingRecordState? prev,
      ShadowingRecordState next,
    ) {
      final String? error = next.error;
      if (error != null && error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        ref.read(shadowingRecorderProvider.notifier).clearError();
      }
    });

    return Container(
      padding: EdgeInsets.all(widget.compact ? 12 : 16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: active ? palette.accent : palette.border,
          width: active ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.graphic_eq_rounded,
                size: 18,
                color: active ? palette.accent : palette.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                '影子跟读',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const Spacer(),
              if (active)
                _ElapsedChip(
                  elapsed: state.elapsed,
                  paused: state.isPaused,
                  palette: palette,
                ),
            ],
          ),
          SizedBox(height: widget.compact ? 10 : 14),
          _RecordButton(
            state: state,
            palette: palette,
            onPressed: () => _toggleRecord(state),
          ),
          if (state.isRecording || state.isPaused) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    ref.read(shadowingRecorderProvider.notifier).discard(),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('放弃这一遍'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.textSecondary,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
          if (state.hasRecording) ...<Widget>[
            const SizedBox(height: 14),
            Divider(color: palette.divider, height: 1),
            const SizedBox(height: 14),
            Text(
              '对比着听',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.textTertiary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _CompareButton(
                    icon: Icons.volume_up_rounded,
                    label: '原声',
                    palette: palette,
                    emphasized: false,
                    onPressed: widget.onPlayOriginal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompareButton(
                    icon: _playingRecording
                        ? Icons.stop_rounded
                        : Icons.mic_rounded,
                    label: _playingRecording ? '停止' : '我的',
                    palette: palette,
                    emphasized: true,
                    onPressed: () {
                      final String? path = state.filePath;
                      if (path == null) {
                        return;
                      }
                      if (_playingRecording) {
                        _stopRecordingPlayback();
                      } else {
                        _playRecording(path);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ElapsedChip extends StatelessWidget {
  const _ElapsedChip({
    required this.elapsed,
    required this.paused,
    required this.palette,
  });

  final Duration elapsed;
  final bool paused;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final String mm = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String ss = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: paused ? palette.textTertiary : palette.danger,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$mm:$ss',
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 12,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.state,
    required this.palette,
    required this.onPressed,
  });

  final ShadowingRecordState state;
  final AppPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool active = state.isRecording || state.isPaused;
    final String label;
    final IconData icon;
    if (state.isRecording) {
      label = '结束这一遍';
      icon = Icons.stop_rounded;
    } else if (state.isPaused) {
      label = '继续录';
      icon = Icons.play_arrow_rounded;
    } else if (state.hasRecording) {
      label = '重录一遍';
      icon = Icons.refresh_rounded;
    } else {
      label = '按下开始跟读';
      icon = Icons.mic_rounded;
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: active ? palette.accent : palette.brand,
          foregroundColor: active
              ? (palette.isDark
                    ? const Color(0xFF231705)
                    : const Color(0xFF241A02))
              : palette.onBrand,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
      ),
    );
  }
}

class _CompareButton extends StatelessWidget {
  const _CompareButton({
    required this.icon,
    required this.label,
    required this.palette,
    required this.emphasized,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final AppPalette palette;
  final bool emphasized;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color fg = emphasized ? palette.brand : palette.textPrimary;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: emphasized
              ? palette.brand.withValues(alpha: 0.08)
              : palette.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: emphasized
                ? palette.brand.withValues(alpha: 0.35)
                : palette.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
