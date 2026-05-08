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
}
