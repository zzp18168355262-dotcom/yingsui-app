import 'package:flutter_test/flutter_test.dart';
import 'package:yingsui/features/player/presentation/player_backend.dart';

void main() {
  test('initializes media_kit backend once', () {
    bool initialized = false;

    initializeVideoPlayerBackend(
      ensureInitialized: () {
        initialized = true;
      },
    );

    expect(initialized, isTrue);
  });
}
