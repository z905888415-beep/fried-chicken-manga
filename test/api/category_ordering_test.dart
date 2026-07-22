import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/copymanga_source_adapter.dart';
import 'package:kira/models/comic.dart';

Comic _comic({
  required String name,
  required int popular,
  String? updated,
  List<Theme> themes = const [],
  String? brief,
}) {
  return Comic(
    name: name,
    pathWord: name,
    cover: '',
    popular: popular,
    datetimeUpdated: updated,
    themes: themes,
    brief: brief,
  );
}

void main() {
  group('normalizeCategoryOrdering', () {
    test('maps popular aliases to -popular', () {
      expect(normalizeCategoryOrdering('-popular'), '-popular');
      expect(normalizeCategoryOrdering('popular'), '-popular');
      expect(normalizeCategoryOrdering('unknown'), '-popular');
    });

    test('maps update aliases to -datetime_updated', () {
      expect(
        normalizeCategoryOrdering('-datetime_updated'),
        '-datetime_updated',
      );
      expect(
        normalizeCategoryOrdering('datetime_updated'),
        '-datetime_updated',
      );
    });
  });

  group('isDanmeiComic', () {
    test('accepts theme path_word danmei / BL tags', () {
      expect(
        isDanmeiComic(
          _comic(
            name: 'A',
            popular: 1,
            themes: [Theme(name: '耽美', pathWord: 'danmei')],
          ),
          requirePositiveEvidence: true,
        ),
        isTrue,
      );
      expect(
        isDanmeiComic(
          _comic(
            name: 'B',
            popular: 1,
            themes: [Theme(name: 'BL', pathWord: 'bl')],
          ),
          requirePositiveEvidence: true,
        ),
        isTrue,
      );
    });

    test('rejects plain school manga without danmei tags when evidence required',
        () {
      expect(
        isDanmeiComic(
          _comic(
            name: '校园時光',
            popular: 100,
            themes: [Theme(name: '校园', pathWord: 'school')],
          ),
          requirePositiveEvidence: true,
        ),
        isFalse,
      );
      expect(
        isDanmeiComic(
          _comic(
            name: '校園傳說',
            popular: 407,
            themes: [Theme(name: '校园', pathWord: 'school')],
          ),
          requirePositiveEvidence: true,
        ),
        isFalse,
      );
    });

    test('list API path trusts server when evidence not required', () {
      expect(
        isDanmeiComic(_comic(name: '无标签列表项', popular: 1)),
        isTrue,
      );
      expect(
        isDanmeiComic(
          _comic(name: '无标签列表项', popular: 1),
          requirePositiveEvidence: true,
        ),
        isFalse,
      );
    });
  });

  group('matchesCategoryKeyword', () {
    test('matches name / theme / brief', () {
      final c = _comic(
        name: '重生之我在娱乐圈',
        popular: 1,
        themes: [Theme(name: '耽美', pathWord: 'danmei')],
        brief: '甜宠文',
      );
      expect(matchesCategoryKeyword(c, '重生'), isTrue);
      expect(matchesCategoryKeyword(c, '甜宠'), isTrue);
      expect(matchesCategoryKeyword(c, '黑道'), isFalse);
    });
  });

  group('sortComicsByOrdering', () {
    final comics = [
      _comic(name: 'a', popular: 10, updated: '2024-01-01'),
      _comic(name: 'b', popular: 50, updated: '2025-06-01'),
      _comic(name: 'c', popular: 30, updated: '2025-01-15'),
      _comic(name: 'd', popular: 5, updated: null),
    ];

    test('最热：按 popular 降序', () {
      final sorted = sortComicsByOrdering(comics, '-popular');
      expect(sorted.map((e) => e.name).toList(), ['b', 'c', 'a', 'd']);
    });

    test('最新：按 datetime_updated 降序，缺失沉底', () {
      final sorted = sortComicsByOrdering(comics, '-datetime_updated');
      expect(sorted.map((e) => e.name).toList(), ['b', 'c', 'a', 'd']);
    });

    test('切换排序后顺序不同', () {
      final pair = [
        _comic(name: 'hot', popular: 100, updated: '2020-01-01'),
        _comic(name: 'new', popular: 1, updated: '2026-07-01'),
      ];
      expect(sortComicsByOrdering(pair, '-popular').first.name, 'hot');
      expect(
        sortComicsByOrdering(pair, '-datetime_updated').first.name,
        'new',
      );
    });
  });
}
