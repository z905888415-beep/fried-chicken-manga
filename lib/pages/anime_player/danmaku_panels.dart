part of '../anime_player_page.dart';

class _CollapsiblePlayerCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final bool initiallyExpanded;
  final Widget? trailing;

  const _CollapsiblePlayerCard({
    required this.icon,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    this.trailing,
  });

  @override
  State<_CollapsiblePlayerCard> createState() => _CollapsiblePlayerCardState();
}

class _CollapsiblePlayerCardState extends State<_CollapsiblePlayerCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(widget.icon, color: cs.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    widget.trailing!,
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: widget.child,
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
          ),
        ],
      ),
    );
  }
}

class _DanmakuMatchPanel extends StatelessWidget {
  final bool isAutoMatched;
  final List<DandanplayEpisode> candidates;
  final ValueChanged<int> onSelect;
  final bool danmakuVisible;
  final bool hasDanmaku;

  const _DanmakuMatchPanel({
    required this.isAutoMatched,
    required this.candidates,
    required this.onSelect,
    required this.danmakuVisible,
    required this.hasDanmaku,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (candidates.isEmpty && (!danmakuVisible || hasDanmaku)) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasDanmaku
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasDanmaku
              ? cs.primary.withValues(alpha: 0.25)
              : Colors.orange.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasDanmaku
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                size: 18,
                color: hasDanmaku ? cs.primary : Colors.orange.shade800,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasDanmaku ? '弹幕已加载' : '未加载弹幕，请在下方选择',
                  style: tt.labelLarge?.copyWith(
                    color: hasDanmaku ? cs.primary : Colors.orange.shade900,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (candidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ep in candidates)
                  ActionChip(
                    avatar: isAutoMatched && candidates.indexOf(ep) == 0
                        ? const Icon(Icons.auto_awesome, size: 16)
                        : const Icon(Icons.check, size: 16),
                    label: Text('${ep.animeTitle} - ${ep.episodeTitle}'),
                    labelStyle: tt.labelMedium?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: cs.primaryContainer,
                    onPressed: () => onSelect(ep.episodeId),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineSearchPanel extends StatelessWidget {
  final List<String> segments;
  final Set<int> selectedIndices;
  final TextEditingController searchController;
  final List<DandanplayEpisode> results;
  final bool searching;
  final bool hasSearched;
  final int? selectedEpisodeId;
  final int? loadingEpisodeId;
  final ValueChanged<int> onToggleSegment;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;
  final ValueChanged<DandanplayEpisode> onSelectResult;

  const _InlineSearchPanel({
    required this.segments,
    required this.selectedIndices,
    required this.searchController,
    required this.results,
    required this.searching,
    required this.hasSearched,
    required this.selectedEpisodeId,
    required this.loadingEpisodeId,
    required this.onToggleSegment,
    required this.onSearch,
    required this.onRefresh,
    required this.onSelectResult,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasResults = results.isNotEmpty;

    return _CollapsiblePlayerCard(
      icon: Icons.subtitles_outlined,
      title: '弹幕搜索',
      initiallyExpanded: !hasResults,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (segments.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < segments.length; i++)
                  FilterChip(
                    label: Text(segments[i]),
                    selected: selectedIndices.contains(i),
                    onSelected: (_) => onToggleSegment(i),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: true,
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: '输入搜索关键词',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: searching ? null : onRefresh,
                    tooltip: '强制刷新',
                  ),
                  IconButton(
                    icon: searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    onPressed: searching ? null : onSearch,
                    tooltip: '搜索',
                  ),
                ],
              ),
            ),
            onSubmitted: (_) => onSearch(),
          ),
          const SizedBox(height: 12),
          if (searching)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (hasResults)
            _buildFlatResults(cs, tt)
          else if (hasSearched)
            _buildEmptyResults(cs, tt)
          else
            Text(
              '请选择分段或输入搜索词后点击搜索',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _buildFlatResults(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '共找到 ${results.length} 条结果',
          style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            children: [
              for (var i = 0; i < results.length; i++) ...[
                _DanmakuResultTile(
                  episode: results[i],
                  selected: results[i].episodeId == selectedEpisodeId,
                  loading: results[i].episodeId == loadingEpisodeId,
                  onTap: () => onSelectResult(results[i]),
                ),
                if (i != results.length - 1)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyResults(ColorScheme cs, TextTheme tt) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 36, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            '未找到相关弹幕',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '减少关键词，仅搜索作品名称\n如：「Re：从零开始的异世界生活第四季丧失篇」搜索「从零开始的异世界生活第四季」',
            textAlign: TextAlign.start,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DanmakuResultTile extends StatelessWidget {
  final DandanplayEpisode episode;
  final bool selected;
  final bool loading;
  final VoidCallback onTap;

  const _DanmakuResultTile({
    required this.episode,
    required this.selected,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.22)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.animeTitle,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      episode.episodeTitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading) ...[
                const SizedBox(width: 8),
                _LoadingTag(
                  label: '加载中',
                  foreground: cs.primary,
                  background: cs.primaryContainer.withValues(alpha: 0.45),
                ),
              ] else if (selected) ...[
                const SizedBox(width: 8),
                _CheckedTag(
                  label: '',
                  foreground: cs.onPrimary,
                  background: cs.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingTag extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;

  const _LoadingTag({
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckedTag extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;

  const _CheckedTag({
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 14, color: foreground),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
