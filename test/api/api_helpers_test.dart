import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_helpers.dart';

void main() {
  group('ApiParseException', () {
    test('携带 message 与 raw', () {
      final e = ApiParseException('boom', 42);
      expect(e.message, 'boom');
      expect(e.raw, 42);
      expect(e.toString(), contains('boom'));
      expect(e.toString(), contains('42'));
    });

    test('raw 为可选参数，省略时为 null', () {
      final e = ApiParseException('only message');
      expect(e.message, 'only message');
      expect(e.raw, isNull);
      expect(e.toString(), contains('only message'));
      expect(e.toString(), isNot(contains('raw:')));
    });
  });

  group('safeRawList<T>', () {
    test('传入 List 返回同类型过滤后的列表', () {
      final result = safeRawList<Map>([
        {'a': 1},
        {'b': 2},
      ]);
      expect(result, hasLength(2));
      expect(result.first, {'a': 1});
    });

    test('按元素类型 T 过滤（混入非 T 元素被剔除）', () {
      final result = safeRawList<Map>([
        {'a': 1},
        'not a map',
        5,
      ]);
      expect(result, hasLength(1));
      expect(result.single, {'a': 1});
    });

    group('required: true', () {
      test('非 List（String）抛 ApiParseException', () {
        expect(
          () => safeRawList<Map>('broken', required: true),
          throwsA(isA<ApiParseException>()),
        );
      });

      test('null 抛 ApiParseException', () {
        expect(
          () => safeRawList<Map>(null, required: true),
          throwsA(isA<ApiParseException>()),
        );
      });

      test('Map（非 List）抛 ApiParseException', () {
        expect(
          () => safeRawList<Map>({'k': 1}, required: true),
          throwsA(isA<ApiParseException>()),
        );
      });
    });

    group('required: false（默认）', () {
      test('非 List（String）降级为空列表', () {
        expect(safeRawList<Map>('broken'), isEmpty);
      });

      test('null 降级为空列表', () {
        expect(safeRawList<Map>(null), isEmpty);
      });
    });
  });

  group('safeInt', () {
    test('int 原样返回', () {
      expect(safeInt(42), 42);
    });

    test('数字字符串解析为 int', () {
      expect(safeInt('42'), 42);
    });

    group('required: true', () {
      test('不可解析字符串抛 ApiParseException', () {
        expect(
          () => safeInt('abc', required: true),
          throwsA(isA<ApiParseException>()),
        );
      });

      test('null 抛 ApiParseException', () {
        expect(
          () => safeInt(null, required: true),
          throwsA(isA<ApiParseException>()),
        );
      });
    });

    group('required: false（默认）', () {
      test('不可解析字符串返回 fallback（默认 0）', () {
        expect(safeInt('abc'), 0);
      });

      test('null 返回 fallback（默认 0）', () {
        expect(safeInt(null), 0);
      });

      test('可指定 fallback', () {
        expect(safeInt('xyz', required: false, fallback: -1), -1);
      });
    });
  });

  group('safeMap', () {
    test('Map 透传（规范化为 Map<String, dynamic>）', () {
      final m = {'a': 1, 'b': 'x'};
      expect(safeMap(m), m);
    });

    test('嵌套 Map 值透传且整体为 Map<String, dynamic>', () {
      // 说明：helper 的 Map<String, dynamic>.from 要求入参键可规范化为 String；
      // 这里用合法（字符串键）的嵌套 Map 验证透传与类型归一，非字符串键由调用方保证。
      final m = {
        'b': {'c': 2, 'd': [1, 2]},
      };
      final result = safeMap(m);
      expect(result, isA<Map<String, dynamic>>());
      expect(result['b'], {
        'c': 2,
        'd': [1, 2],
      });
    });

    group('required: true', () {
      test('非 Map（String）抛 ApiParseException', () {
        expect(
          () => safeMap('broken', required: true),
          throwsA(isA<ApiParseException>()),
        );
      });
    });

    group('required: false（默认）', () {
      test('非 Map（String）返回空 Map', () {
        expect(safeMap('broken'), isEmpty);
      });
    });
  });

  group('safeResults', () {
    test('正确提取 results 字段', () {
      final data = {
        'results': {
          'list': [],
          'total': 0,
        }
      };
      final result = safeResults(data);
      expect(result, {'list': [], 'total': 0});
    });

    group('required: true', () {
      test('缺失 results 抛 ApiParseException', () {
        expect(
          () => safeResults({}, required: true),
          throwsA(isA<ApiParseException>()),
        );
      });

      test('顶层非 Map（String）抛 ApiParseException', () {
        expect(
          () => safeResults('broken', required: true),
          throwsA(isA<ApiParseException>()),
        );
      });

      test('results 为非 Map 抛 ApiParseException', () {
        expect(
          () => safeResults({
            'results': 'not a map',
          }, required: true),
          throwsA(isA<ApiParseException>()),
        );
      });
    });

    group('required: false（默认）', () {
      test('缺失 results 返回空 Map', () {
        expect(safeResults({}), isEmpty);
      });

      test('顶层非 Map 返回空 Map', () {
        expect(safeResults('broken'), isEmpty);
      });
    });
  });

  group('BUG-01 闭环：畸形响应不再静默降级为空列表', () {
    test('主数据字段为非 List 时 safeRawList(required:true) 抛 ApiParseException', () {
      // 模拟 getComicList / getChapterList / getBookshelf 收到的畸形响应
      final resp = {'list': 'broken'};
      expect(
        () => safeRawList<Map>(resp['list'], required: true),
        throwsA(isA<ApiParseException>()),
      );
    });

    test('经 safeResults 取出的畸形 list 同样抛 ApiParseException', () {
      final resp = {
        'results': {
          'list': 'broken',
          'total': 0,
        }
      };
      final data = safeResults(resp);
      expect(
        () => safeRawList<Map>(data['list'], required: true),
        throwsA(isA<ApiParseException>()),
      );
    });

    test('total 为字符串时 safeInt(required:false) 不抛且降级为 fallback', () {
      // 次级字段畸形：降级而非崩溃（与 BUG-01 主数据显错形成分层防御）
      expect(safeInt('not-a-number', required: false, fallback: 0), 0);
    });
  });
}
