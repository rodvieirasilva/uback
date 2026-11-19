import 'package:material_ui/material_ui.dart';

import '../../core/backup/media_source.dart';
import '../../core/testing/test_keys.dart';
import '../../core/utils/path_sanitizer.dart';

/// Collapsible hierarchical Media Sources selector with tri-state group toggles,
/// nested sub-items, and live non-blocking file count + byte size estimates.
class MediaSourcesCard extends StatefulWidget {
  final List<MediaSource> sources;
  final Set<String> enabledSourceIds;
  final Map<String, MediaSourceStats> stats;
  final bool estimating;
  final bool hasEstimated;
  final int selectedFiles;
  final int selectedBytes;
  final bool enabled;
  final void Function(MediaSource source, bool value) onToggle;
  final VoidCallback onRefreshEstimate;

  const MediaSourcesCard({
    super.key,
    required this.sources,
    required this.enabledSourceIds,
    required this.stats,
    required this.estimating,
    required this.hasEstimated,
    required this.selectedFiles,
    required this.selectedBytes,
    required this.enabled,
    required this.onToggle,
    required this.onRefreshEstimate,
  });

  @override
  State<MediaSourcesCard> createState() => _MediaSourcesCardState();
}

class _MediaSourcesCardState extends State<MediaSourcesCard> {
  bool _sectionExpanded = true;
  final Set<String> _expandedNodes = <String>{};

  void _toggleExpanded(String id) {
    setState(() {
      if (!_expandedNodes.remove(id)) {
        _expandedNodes.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: cs.onSurfaceVariant,
          letterSpacing: 1.0,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            withTestId(
              AppTestKeys.mediaSourcesCollapseId,
              child: InkWell(
                key: AppTestKeys.mediaSourcesCollapse,
                onTap: () => setState(() => _sectionExpanded = !_sectionExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _sectionExpanded ? Icons.expand_more : Icons.chevron_right,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text('MEDIA SOURCES', style: labelStyle),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: widget.estimating
                    ? withTestId(
                        AppTestKeys.mediaSourcesEstimatingId,
                        child: Row(
                          key: AppTestKeys.mediaSourcesEstimating,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Estimating size...',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.primary),
                              ),
                            ),
                          ],
                        ),
                      )
                    : InkWell(
                        onTap: widget.enabled ? widget.onRefreshEstimate : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: withTestId(
                            AppTestKeys.mediaSourcesSummaryId,
                            child: Text(
                              widget.hasEstimated
                                  ? 'Selected: ${widget.selectedFiles} files • '
                                      '${PathSanitizer.formatBytes(widget.selectedBytes)}'
                                  : 'Tap to estimate',
                              key: AppTestKeys.mediaSourcesSummary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
        if (_sectionExpanded) ...[
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < widget.sources.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ..._buildNodeTree(context, widget.sources[i], depth: 0),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildNodeTree(BuildContext context, MediaSource node, {required int depth}) {
    final expanded = _expandedNodes.contains(node.id);
    final widgets = <Widget>[
      _SourceNodeRow(
        node: node,
        depth: depth,
        expanded: expanded,
        selectionState: node.selectionState(widget.enabledSourceIds),
        stat: node.aggregateStats(widget.stats),
        estimating: widget.estimating,
        hasEstimated: widget.hasEstimated,
        enabled: widget.enabled,
        onToggleExpand: node.isGroup ? () => _toggleExpanded(node.id) : null,
        onToggleSelection: (val) => widget.onToggle(node, val),
      ),
    ];

    if (node.isGroup && expanded) {
      for (final child in node.children) {
        widgets.add(const Divider(height: 1, indent: 16));
        widgets.addAll(_buildNodeTree(context, child, depth: depth + 1));
      }
    }
    return widgets;
  }
}

class _SourceNodeRow extends StatelessWidget {
  final MediaSource node;
  final int depth;
  final bool expanded;
  final bool? selectionState;
  final MediaSourceStats stat;
  final bool estimating;
  final bool hasEstimated;
  final bool enabled;
  final VoidCallback? onToggleExpand;
  final ValueChanged<bool> onToggleSelection;

  const _SourceNodeRow({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.selectionState,
    required this.stat,
    required this.estimating,
    required this.hasEstimated,
    required this.enabled,
    required this.onToggleExpand,
    required this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final leftPad = 8.0 + (depth * 18.0);
    final estimateText = switch ((estimating, hasEstimated)) {
      (true, false) => '${node.subtitle} • Estimating...',
      (_, true) => '${stat.fileCount} files • ${PathSanitizer.formatBytes(stat.totalBytes)}',
      _ => node.subtitle,
    };

    return InkWell(
      onTap: onToggleExpand ?? (enabled ? () => onToggleSelection(!(selectionState ?? false)) : null),
      child: Padding(
        padding: EdgeInsets.fromLTRB(leftPad, 6, 8, 6),
        child: Row(
          children: [
            if (node.isGroup)
              withTestId(
                AppTestKeys.sourceExpandId(node.id),
                child: IconButton(
                  key: AppTestKeys.sourceExpand(node.id),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onToggleExpand,
                  icon: Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              )
            else
              const SizedBox(width: 32),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.w500,
                      fontSize: depth == 0 ? 15 : 14,
                    ),
                  ),
                  const SizedBox(height: 1),
                  withTestId(
                    AppTestKeys.sourceStatsId(node.id),
                    child: Text(
                      estimateText,
                      key: AppTestKeys.sourceStats(node.id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            withTestId(
              AppTestKeys.sourceToggleId(node.id),
              child: Checkbox(
                key: AppTestKeys.sourceToggle(node.id),
                tristate: node.isGroup,
                value: selectionState,
                onChanged: enabled
                    ? (_) {
                        // Tri-state UX: if unchecked or partial -> check all; if all checked -> uncheck all.
                        final nextValue = selectionState != true;
                        onToggleSelection(nextValue);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
