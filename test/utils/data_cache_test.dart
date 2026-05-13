import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/data_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('remove deletes a cached entry', () async {
    final cache = DataCache();

    await cache.put('video_link', {'url': 'https://example.com/video.m3u8'});
    await cache.remove('video_link');

    expect(await cache.get('video_link'), isNull);
  });

  test('get removes expired ttl entries', () async {
    final cache = DataCache();

    await cache.put('video_link', {
      'url': 'https://example.com/video.m3u8',
    }, ttl: const Duration(milliseconds: -1));

    expect(await cache.get('video_link'), isNull);
  });
}
