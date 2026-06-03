part of '../anime_detail_page.dart';

class _DandanplayAlignmentDialog extends StatefulWidget {
  final List<AnimeChapter> chapters;
  final List<DandanplayBangumiEpisode> episodes;
  final int initialChapterIndex;
  final int initialEpisodeIndex;
  final bool hasExistingAlignment;

  const _DandanplayAlignmentDialog({
    required this.chapters,
    required this.episodes,
    required this.initialChapterIndex,
    required this.initialEpisodeIndex,
    required this.hasExistingAlignment,
  });

  @override
  State<_DandanplayAlignmentDialog> createState() =>
      _DandanplayAlignmentDialogState();
}

class _DandanplayAlignmentDialogState
    extends State<_DandanplayAlignmentDialog> {
  late int _chapterIndex;
  late int _episodeIndex;

  @override
  void initState() {
    super.initState();
    _chapterIndex = widget.initialChapterIndex.clamp(
      0,
      widget.chapters.length - 1,
    );
    _episodeIndex = widget.initialEpisodeIndex.clamp(
      0,
      widget.episodes.length - 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('对齐弹幕'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _chapterIndex,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '视频第一集',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final entry in widget.chapters.indexed)
                  DropdownMenuItem<int>(
                    value: entry.$1,
                    child: Text(
                      entry.$2.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _chapterIndex = value);
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: _episodeIndex,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '弹幕第一集',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final entry in widget.episodes.indexed)
                  DropdownMenuItem<int>(
                    value: entry.$1,
                    child: Text(
                      _formatDandanplayEpisodeLabel(entry.$2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _episodeIndex = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        if (widget.hasExistingAlignment)
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              const _DandanplayAlignmentResult.clear(),
            ),
            child: const Text('清除对齐'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _DandanplayAlignmentResult.align(
              chapterIndex: _chapterIndex,
              episodeIndex: _episodeIndex,
            ),
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
