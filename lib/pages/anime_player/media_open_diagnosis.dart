part of '../anime_player_page.dart';

class _MediaOpenDiagnosis {
  final int? manifestStatus;
  final bool manifestLooksLikeHls;
  final String? manifestError;
  final String? firstSegmentUrl;
  final int? segmentStatus;
  final int? segmentBytes;
  final String? segmentError;

  const _MediaOpenDiagnosis({
    this.manifestStatus,
    this.manifestLooksLikeHls = false,
    this.manifestError,
    this.firstSegmentUrl,
    this.segmentStatus,
    this.segmentBytes,
    this.segmentError,
  });

  bool get networkLooksHealthy =>
      manifestStatus == 200 &&
      manifestLooksLikeHls &&
      segmentStatus == 200 &&
      (segmentBytes ?? 0) > 0;

  String toDebugString() {
    final buffer = StringBuffer();
    if (manifestStatus != null) {
      buffer.writeln('m3u8 状态: $manifestStatus');
    }
    if (manifestLooksLikeHls) {
      buffer.writeln('m3u8 内容: 已识别为 HLS 清单');
    } else if (manifestStatus == 200) {
      buffer.writeln('m3u8 内容: 返回 200，但内容不像标准 HLS 清单');
    }
    if (manifestError != null && manifestError!.isNotEmpty) {
      buffer.writeln('m3u8 错误: $manifestError');
    }
    if (firstSegmentUrl != null && firstSegmentUrl!.isNotEmpty) {
      buffer.writeln('首个分片: $firstSegmentUrl');
    }
    if (segmentStatus != null) {
      buffer.writeln('首个分片状态: $segmentStatus');
    }
    if (segmentBytes != null) {
      buffer.writeln('首个分片字节数: $segmentBytes');
    }
    if (segmentError != null && segmentError!.isNotEmpty) {
      buffer.writeln('首个分片错误: $segmentError');
    }
    if (networkLooksHealthy) {
      buffer.writeln('结论: m3u8 与首个分片都可访问，更像是播放器解析或解码兼容问题');
    }
    return buffer.toString().trim();
  }
}
