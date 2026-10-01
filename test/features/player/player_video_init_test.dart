import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/player_video_init.dart';

void main() {
  test('times out when player initialization never completes', () async {
    await expectLater(
      waitForVideoInitialization(
        () => Completer<void>().future,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
