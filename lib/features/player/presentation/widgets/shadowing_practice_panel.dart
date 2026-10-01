import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_theme.dart';
import '../shadowing_recorder.dart';

/// 跟读练习面板。
///
/// 核心是让用户能**听到自己的跟读**：录下来，然后与原声来回对照。
/// 产品定位是不打分 —— 用户自己的耳朵就是判断标准。
class ShadowingPracticePanel extends ConsumerStatefulWidget {
  const ShadowingPracticePanel({
    super.key,
    required this.lineKey,
    required this.onPlayOriginal,
    required this.onStopOriginal,
    this.english,
    this.chinese,
    this.subtitleMode = '双语',
    this.compact = false,
  });

  /// 当前句子的唯一标识；换句时录音自动作废，避免张冠李戴。
  final String lineKey;

  /// 播放原声（由播放器宿主实现，复用同一个视频播放器）。
  final VoidCallback onPlayOriginal;

  /// 停止原声，避免和跟读录音回放叠在一起。
  final VoidCallback onStopOriginal;

  /// 当前句原文。展示在面板内，用户不必在画面与面板之间来回看。
  final String? english;

  /// 当前句译文（可能为空，取决于字幕模式与是否已翻译）。
  final String? chinese;

  /// 字幕显示模式，决定面板内是否显示译文。
  final String subtitleMode;

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
    // 换句后上一句的录音不再适用，直接作废，防止误对比。
    if (oldWidget.lineKey != widget.lineKey) {
      unawaited(_stopRecordingPlayback());
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
    unawaited(_completedSub?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  Player get _audioPlayer => _player ??= Player();

  /// 把本地路径转成合法的 file URI。
  ///
  /// 不能直接写 'file://$path'：路径中出现空格、中文等字符时需要百分号编码，
  /// 否则底层解码器会找不到文件（表现为点了播放却没有任何声音）。
  String _fileUri(String path) => Uri.file(path).toString();

  Future<void> _playRecording(String path) async {
    // 先停掉原声，避免两路声音重叠、听不清自己的。
    widget.onStopOriginal();
    await _completedSub?.cancel();

    try {
      // 关键：监听器必须在 open 之前注册。
      // 放在 open 之后会漏掉极短录音的 completed 事件，
      // 导致按钮永远停在「停止」状态。
      _completedSub = _audioPlayer.stream.completed.listen((bool done) {
        if (done && mounted) {
          setState(() => _playingRecording = false);
        }
      });

      await _audioPlayer.open(Media(_fileUri(path)));
      if (mounted) {
        setState(() => _playingRecording = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _playingRecording = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('回放失败：$e')));
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

    ref.listen<ShadowingRecordState>(shadowingRecorderProvider, (
      ShadowingRecordState? prev,
      ShadowingRecordState next,
    ) {
      final String? error = next.error;
      if (error != null && error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
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
          // ── 标题 ──
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

          // ── 当前句 ──
          // 直接在面板里展示这句字幕，用户不必「看画面 → 低头按面板」来回切换。
          // 点击可重播原声。
          if ((widget.english ?? '').trim().isNotEmpty) ...<Widget>[
            _CurrentLineBlock(
              english: widget.english!.trim(),
              chinese: widget.chinese?.trim() ?? '',
              showChinese: widget.subtitleMode != '隐藏',
              palette: palette,
              onTap: widget.onPlayOriginal,
            ),
            SizedBox(height: widget.compact ? 10 : 14),
          ],

          // ── 录制控制 ──
          _RecordButton(
            state: state,
            palette: palette,
            onPressed: () => _toggleRecord(state),
          ),

          if (active) ...<Widget>[
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

          // ── 听自己的跟读 ──
          if (state.hasRecording) ...<Widget>[
            const SizedBox(height: 14),
            Divider(color: palette.divider, height: 1),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(
                  Icons.headphones_rounded,
                  size: 15,
                  color: palette.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  '听一遍，和原声对照',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.textTertiary,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 主操作：听自己的跟读。做成整行大按钮，避免用户找不到。
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final String? path = state.filePath;
                  if (path == null) {
                    return;
                  }
                  if (_playingRecording) {
                    unawaited(_stopRecordingPlayback());
                  } else {
                    unawaited(_playRecording(path));
                  }
                },
                icon: Icon(
                  _playingRecording
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                  size: 22,
                ),
                label: Text(_playingRecording ? '停止播放' : '听听我的跟读'),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.isDark
                      ? const Color(0xFF231705)
                      : const Color(0xFF241A02),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // 次要操作：再听原声、重录
            Row(
              children: <Widget>[
                Expanded(
                  child: _CompareButton(
                    icon: Icons.volume_up_rounded,
                    label: '再听原声',
                    palette: palette,
                    emphasized: false,
                    onPressed: widget.onPlayOriginal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompareButton(
                    icon: Icons.refresh_rounded,
                    label: '重录一遍',
                    palette: palette,
                    emphasized: false,
                    onPressed: () {
                      unawaited(_stopRecordingPlayback());
                      unawaited(
                        ref
                            .read(shadowingRecorderProvider.notifier)
                            .discard(),
                      );
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
    final String mm = elapsed.inMinutes.remainder(60).toString().padLeft(
      2,
      '0',
    );
    final String ss = elapsed.inSeconds.remainder(60).toString().padLeft(
      2,
      '0',
    );
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
      // 已有录音时，主按钮让位给「听自己的跟读」，这里只提示状态。
      label = '已录好';
      icon = Icons.check_circle_outline_rounded;
    } else {
      label = '按下开始跟读';
      icon = Icons.mic_rounded;
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: active ? onPressed : (state.hasRecording ? null : onPressed),
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: active ? palette.accent : palette.brand,
          foregroundColor: active
              ? (palette.isDark
                    ? const Color(0xFF231705)
                    : const Color(0xFF241A02))
              : palette.onBrand,
          disabledBackgroundColor: palette.surfaceAlt,
          disabledForegroundColor: palette.textSecondary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
      ),
    );
  }
}

class _CurrentLineBlock extends StatelessWidget {
  const _CurrentLineBlock({
    required this.english,
    required this.chinese,
    required this.showChinese,
    required this.palette,
    required this.onTap,
  });

  final String english;
  final String chinese;
  final bool showChinese;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool hasChinese = showChinese && chinese.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.subject_rounded,
                  size: 13,
                  color: palette.textTertiary,
                ),
                const SizedBox(width: 5),
                Text(
                  '跟读这一句',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.3,
                    color: palette.textTertiary,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.replay_rounded,
                  size: 14,
                  color: palette.textTertiary,
                ),
                const SizedBox(width: 3),
                Text(
                  '重听',
                  style: TextStyle(fontSize: 11, color: palette.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              english,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            if (hasChinese) ...<Widget>[
              const SizedBox(height: 5),
              Text(
                chinese,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ],
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
