import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('image viewer auto-rotate settings persist', () async {
    final user = UserManager();
    await user.init();

    expect(user.imageViewerAutoRotateLandscape, isFalse);
    expect(user.imageViewerLandscapeRotation, 1);

    await user.setImageViewerAutoRotateLandscape(true);
    await user.setImageViewerLandscapeRotation(-1);
    await user.init();

    expect(user.imageViewerAutoRotateLandscape, isTrue);
    expect(user.imageViewerLandscapeRotation, -1);
  });

  test('image viewer rotation normalizes to left or right', () async {
    final user = UserManager();
    await user.init();

    await user.setImageViewerLandscapeRotation(0);
    expect(user.imageViewerLandscapeRotation, 1);

    await user.setImageViewerLandscapeRotation(-90);
    expect(user.imageViewerLandscapeRotation, -1);
  });

  test('anime home banner collapsed setting persists', () async {
    final user = UserManager();
    await user.init();

    expect(user.animeHomeBannerCollapsed, isFalse);

    await user.setAnimeHomeBannerCollapsed(true);
    await user.init();

    expect(user.animeHomeBannerCollapsed, isTrue);
  });

  test(
    'anime playback progress setting defaults to enabled and persists',
    () async {
      final user = UserManager();
      await user.init();

      expect(user.animePlaybackProgressEnabled, isTrue);

      await user.setAnimePlaybackProgressEnabled(false);
      await user.init();

      expect(user.animePlaybackProgressEnabled, isFalse);
    },
  );

  test('anime feature setting defaults to enabled and persists', () async {
    final user = UserManager();
    await user.init();

    expect(user.animeFeatureEnabled, isTrue);

    await user.setAnimeFeatureEnabled(false);
    await user.init();

    expect(user.animeFeatureEnabled, isFalse);
  });

  test('dark mode cover brightness defaults and persists', () async {
    final user = UserManager();
    await user.init();

    expect(
      user.darkModeCoverBrightness,
      UserManager.defaultDarkModeCoverBrightness,
    );

    await user.setDarkModeCoverBrightness(0.7);
    await user.init();

    expect(user.darkModeCoverBrightness, 0.7);
  });
}
