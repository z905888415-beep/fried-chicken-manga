class ComicComment {
  final int id;
  final String createAt;
  final String userId;
  final String userName;
  final String userAvatar;
  final String comment;
  final int replyCount;
  final int? parentId;
  final String? parentUserId;
  final String? parentUserName;

  const ComicComment({
    required this.id,
    required this.createAt,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.comment,
    required this.replyCount,
    this.parentId,
    this.parentUserId,
    this.parentUserName,
  });

  factory ComicComment.fromJson(Map<String, dynamic> json) => ComicComment(
    id: json['id'] is int
        ? json['id'] as int
        : int.tryParse(json['id']?.toString() ?? '') ?? 0,
    createAt: json['create_at']?.toString() ?? '',
    userId: json['user_id']?.toString() ?? '',
    userName: json['user_name']?.toString() ?? '匿名用户',
    userAvatar: json['user_avatar']?.toString() ?? '',
    comment: json['comment']?.toString() ?? '',
    replyCount: json['count'] is int
        ? json['count'] as int
        : int.tryParse(json['count']?.toString() ?? '') ?? 0,
    parentId: json['parent_id'] is int
        ? json['parent_id'] as int
        : int.tryParse(json['parent_id']?.toString() ?? ''),
    parentUserId: json['parent_user_id']?.toString(),
    parentUserName: json['parent_user_name']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'create_at': createAt,
    'user_id': userId,
    'user_name': userName,
    'user_avatar': userAvatar,
    'comment': comment,
    'count': replyCount,
    'parent_id': parentId,
    'parent_user_id': parentUserId,
    'parent_user_name': parentUserName,
  };
}
