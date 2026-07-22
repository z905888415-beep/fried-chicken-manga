class Author {
  final String name;
  final String pathWord;

  Author({required this.name, required this.pathWord});

  factory Author.fromJson(Map<String, dynamic> json) => Author(
    name: json['name']?.toString() ?? '',
    pathWord: json['path_word']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {'name': name, 'path_word': pathWord};
}

class MangaBanner {
  final String cover;
  final String brief;
  final String outUuid;
  final Comic? comic;

  const MangaBanner({
    required this.cover,
    required this.brief,
    required this.outUuid,
    this.comic,
  });

  factory MangaBanner.fromJson(Map<String, dynamic> json) => MangaBanner(
    cover: json['cover']?.toString() ?? '',
    brief: json['brief']?.toString() ?? '',
    outUuid: json['out_uuid']?.toString() ?? '',
    comic: json['comic'] is Map
        ? Comic.fromJson(Map<String, dynamic>.from(json['comic']))
        : null,
  );

  Map<String, dynamic> toJson() => {
    'cover': cover,
    'brief': brief,
    'out_uuid': outUuid,
    'comic': comic?.toJson(),
  };
}

class MangaHome {
  final List<MangaBanner> banners;
  final List<Comic> recommendations;

  const MangaHome({this.banners = const [], this.recommendations = const []});

  factory MangaHome.fromJson(Map<String, dynamic> json) => MangaHome(
    banners:
        (json['banners'] as List?)
            ?.map((e) => MangaBanner.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [],
    recommendations: _parseRecList(json['recs']),
  );

  Map<String, dynamic> toJson() => {
    'banners': banners.map((e) => e.toJson()).toList(),
    'recs': {
      'list': recommendations.map((e) => {'comic': e.toJson()}).toList(),
    },
  };

  static List<Comic> _parseRecList(dynamic section) {
    final list = section is Map ? section['list'] as List? : null;
    if (list == null) return const [];
    return list
        .where((e) => e is Map && e['comic'] is Map)
        .map(
          (e) => Comic.fromJson(Map<String, dynamic>.from((e as Map)['comic'])),
        )
        .toList();
  }
}

class Theme {
  final String name;
  final String pathWord;
  final int count;

  Theme({required this.name, required this.pathWord, this.count = 0});

  factory Theme.fromJson(Map<String, dynamic> json) => Theme(
    name: json['name']?.toString() ?? '',
    pathWord: json['path_word']?.toString() ?? '',
    count: json['count'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'path_word': pathWord,
    'count': count,
  };
}

class ComicGroup {
  final String pathWord;
  final int count;
  final String name;

  ComicGroup({required this.pathWord, required this.count, required this.name});

  factory ComicGroup.fromJson(Map<String, dynamic> json) => ComicGroup(
    pathWord: json['path_word']?.toString() ?? '',
    count: json['count'] as int? ?? 0,
    name: json['name']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {
    'path_word': pathWord,
    'count': count,
    'name': name,
  };
}

class Comic {
  final String? uuid;
  final String name;
  final String pathWord;
  final String cover;
  final int popular;
  final List<Author> authors;
  final List<Theme> themes;
  final String? datetimeUpdated;
  final String? brief;
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? lastChapter;
  final String? lastChapterId;
  final String? lastChapterName;
  final Map<String, ComicGroup>? groups;
  final Map<String, dynamic>? region;
  final String sourceId;
  final List<String> categoryIds;

  Comic({
    this.uuid,
    required this.name,
    required this.pathWord,
    required this.cover,
    this.popular = 0,
    this.authors = const [],
    this.themes = const [],
    this.datetimeUpdated,
    this.brief,
    this.status,
    this.lastChapter,
    this.lastChapterId,
    this.lastChapterName,
    this.groups,
    this.region,
    this.sourceId = 'kopymanga',
    this.categoryIds = const [],
  });

  factory Comic.fromJson(Map<String, dynamic> json) => Comic(
    uuid: json['uuid']?.toString(),
    name: json['name']?.toString() ?? json['title']?.toString() ?? '',
    pathWord: json['path_word']?.toString() ?? json['id']?.toString() ?? '',
    cover: json['cover']?.toString() ?? '',
    popular: json['popular'] as int? ?? json['popularity'] as int? ?? 0,
    sourceId:
        json['sourceId']?.toString() ??
        json['source_id']?.toString() ??
        'kopymanga',
    categoryIds:
        (json['categoryIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
    authors:
        (json['author'] as List?)
            ?.whereType<Map>()
            .map((a) => Author.fromJson(Map<String, dynamic>.from(a)))
            .toList() ??
        [],
    themes:
        (json['theme'] as List?)
            ?.whereType<Map>()
            .map((t) => Theme.fromJson(Map<String, dynamic>.from(t)))
            .toList() ??
        [],
    datetimeUpdated:
        json['datetime_updated']?.toString() ?? json['updateTime']?.toString(),
    brief: json['brief']?.toString() ?? json['description']?.toString(),
    status: json['status'] is Map
        ? Map<String, dynamic>.from(json['status'])
        : null,
    lastChapter: json['last_chapter'] is Map
        ? Map<String, dynamic>.from(json['last_chapter'])
        : null,
    lastChapterId: json['last_chapter_id']?.toString(),
    lastChapterName:
        json['last_chapter_name']?.toString() ??
        json['latestChapter']?.toString(),
    groups: json['groups'] is Map
        ? (json['groups'] as Map).map(
            (k, v) => MapEntry(
              k.toString(),
              ComicGroup.fromJson(Map<String, dynamic>.from(v)),
            ),
          )
        : null,
    region: json['region'] is Map
        ? Map<String, dynamic>.from(json['region'])
        : null,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'path_word': pathWord,
    'cover': cover,
    'popular': popular,
    'author': authors.map((a) => a.toJson()).toList(),
    'theme': themes.map((t) => t.toJson()).toList(),
    'datetime_updated': datetimeUpdated,
    'brief': brief,
    'status': status,
    'last_chapter': lastChapter,
    'last_chapter_id': lastChapterId,
    'last_chapter_name': lastChapterName,
    'groups': groups?.map((k, v) => MapEntry(k, v.toJson())),
    'region': region,
  };

  factory Comic.fromDetailJson(Map<String, dynamic> json) {
    final comic = Comic.fromJson(json['comic']);
    final groupsMap = <String, ComicGroup>{};
    if (json['groups'] is Map) {
      (json['groups'] as Map).forEach((k, v) {
        groupsMap[k] = ComicGroup.fromJson(v);
      });
    }
    return Comic(
      uuid: comic.uuid,
      name: comic.name,
      pathWord: comic.pathWord,
      cover: comic.cover,
      popular: json['popular'] ?? comic.popular,
      authors: comic.authors,
      themes: comic.themes,
      datetimeUpdated: comic.datetimeUpdated,
      brief: comic.brief,
      status: comic.status,
      lastChapter: comic.lastChapter,
      lastChapterId: comic.lastChapterId,
      lastChapterName: comic.lastChapterName,
      groups: groupsMap,
      region: comic.region,
    );
  }

  Comic copyWith({
    String? uuid,
    String? name,
    String? pathWord,
    String? cover,
    int? popular,
    List<Author>? authors,
    List<Theme>? themes,
    String? datetimeUpdated,
    String? brief,
    Map<String, dynamic>? status,
    Map<String, dynamic>? lastChapter,
    String? lastChapterId,
    String? lastChapterName,
    Map<String, ComicGroup>? groups,
    Map<String, dynamic>? region,
  }) {
    return Comic(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      pathWord: pathWord ?? this.pathWord,
      cover: cover ?? this.cover,
      popular: popular ?? this.popular,
      authors: authors ?? this.authors,
      themes: themes ?? this.themes,
      datetimeUpdated: datetimeUpdated ?? this.datetimeUpdated,
      brief: brief ?? this.brief,
      status: status ?? this.status,
      lastChapter: lastChapter ?? this.lastChapter,
      lastChapterId: lastChapterId ?? this.lastChapterId,
      lastChapterName: lastChapterName ?? this.lastChapterName,
      groups: groups ?? this.groups,
      region: region ?? this.region,
    );
  }
}

class BookshelfItem {
  final Comic comic;
  final String? lastBrowseId;
  final String? lastBrowseName;

  BookshelfItem({required this.comic, this.lastBrowseId, this.lastBrowseName});

  bool get hasUpdate =>
      lastBrowseId != null &&
      comic.lastChapterId != null &&
      lastBrowseId != comic.lastChapterId;

  factory BookshelfItem.fromJson(Map<String, dynamic> json) => BookshelfItem(
    comic: Comic.fromJson(Map<String, dynamic>.from(json['comic'] ?? {})),
    lastBrowseId: json['last_browse_id']?.toString(),
    lastBrowseName: json['last_browse_name']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'comic': comic.toJson(),
    'last_browse_id': lastBrowseId,
    'last_browse_name': lastBrowseName,
  };
}

class BrowseHistoryItem {
  final int id;
  final Comic comic;
  final String? lastBrowseId;
  final String? lastBrowseName;

  BrowseHistoryItem({
    required this.id,
    required this.comic,
    this.lastBrowseId,
    this.lastBrowseName,
  });
}
