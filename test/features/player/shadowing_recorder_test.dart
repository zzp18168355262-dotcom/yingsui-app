import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/shadowing_recorder.dart';

void main() {
  group('ShadowingRecordState', () {
    test('初始状态是 idle 且没有录音', () {
      const ShadowingRecordState state = ShadowingRecordState();
      expect(state.status, ShadowingRecordStatus.idle);
      expect(state.isRecording, isFalse);
      expect(state.isPaused, isFalse);
      expect(state.hasRecording, isFalse);
      expect(state.filePath, isNull);
      expect(state.elapsed, Duration.zero);
    });

    test('只有 recorded 且有文件才算「有录音」', () {
      const ShadowingRecordState noFile = ShadowingRecordState(
        status: ShadowingRecordStatus.recorded,
      );
      expect(noFile.hasRecording, isFalse);

      const ShadowingRecordState withFile = ShadowingRecordState(
        status: ShadowingRecordStatus.recorded,
        filePath: '/tmp/a.m4a',
      );
      expect(withFile.hasRecording, isTrue);
    });

    test('录音只在对应句子有效，换句即失效', () {
      const ShadowingRecordState state = ShadowingRecordState(
        status: ShadowingRecordStatus.recorded,
        filePath: '/tmp/a.m4a',
        lineKey: '1000#0',
      );
      expect(state.matchesLine('1000#0'), isTrue);
      expect(state.matchesLine('2000#1'), isFalse);
    });

    test('没有录音时任何句子都不匹配', () {
      const ShadowingRecordState state = ShadowingRecordState(
        lineKey: '1000#0',
      );
      expect(state.matchesLine('1000#0'), isFalse);
    });

    test('copyWith 可以单独清除错误而不动其他字段', () {
      const ShadowingRecordState state = ShadowingRecordState(
        status: ShadowingRecordStatus.recorded,
        filePath: '/tmp/a.m4a',
        lineKey: '1000#0',
        error: '出错了',
      );
      final ShadowingRecordState cleared = state.copyWith(clearError: true);
      expect(cleared.error, isNull);
      expect(cleared.filePath, '/tmp/a.m4a');
      expect(cleared.lineKey, '1000#0');
      expect(cleared.status, ShadowingRecordStatus.recorded);
    });

    test('copyWith 可以清空录音文件与句子绑定', () {
      const ShadowingRecordState state = ShadowingRecordState(
        status: ShadowingRecordStatus.recorded,
        filePath: '/tmp/a.m4a',
        lineKey: '1000#0',
      );
      final ShadowingRecordState cleared = state.copyWith(
        status: ShadowingRecordStatus.idle,
        clearFile: true,
      );
      expect(cleared.filePath, isNull);
      expect(cleared.lineKey, isNull);
      expect(cleared.hasRecording, isFalse);
    });
  });

  group('ShadowingRecorder', () {
    test('初始状态为 idle', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final ShadowingRecordState state = container.read(
        shadowingRecorderProvider,
      );
      expect(state.status, ShadowingRecordStatus.idle);
      expect(state.hasRecording, isFalse);
    });

    test('未录音时 stop / pause / resume 都是安全空操作', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final ShadowingRecorder recorder = container.read(
        shadowingRecorderProvider.notifier,
      );

      await recorder.stop();
      await recorder.pause();
      await recorder.resume();

      final ShadowingRecordState state = container.read(
        shadowingRecorderProvider,
      );
      expect(state.status, ShadowingRecordStatus.idle);
      expect(state.error, isNull);
    });

    test('idle 状态下 resetForNewLine 不会产生副作用', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final ShadowingRecorder recorder = container.read(
        shadowingRecorderProvider.notifier,
      );
      await recorder.resetForNewLine();

      expect(
        container.read(shadowingRecorderProvider).status,
        ShadowingRecordStatus.idle,
      );
    });

    test('无错误时 clearError 是空操作', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      // 读取 notifier 以获得实例；随后清错。
      container.read(shadowingRecorderProvider.notifier).clearError();
      expect(container.read(shadowingRecorderProvider).error, isNull);
    });
  });
}
