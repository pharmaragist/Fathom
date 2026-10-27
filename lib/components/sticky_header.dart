import 'package:flutter/material.dart';

import '../common/colors.dart';

/// The page's own title, pinned to the top of a utility route's scroll view.
///
/// The title is painted over a gradient that is opaque at the top and
/// transparent at the bottom, so rows scrolling underneath dissolve instead of
/// being cut by the title's edge. Pinning it is what keeps the page named while
/// the user reads far down a long settings list; the horizontal padding lives
/// on the row rather than on the sliver so the gradient spans the full width.
class SliverPageHeader extends StatelessWidget {
  const SliverPageHeader({
    super.key,
    required this.title,
    required this.topInset,
    this.trailing,
    this.extent = 56,
  });

  final String title;

  /// Status-bar inset the title row has to clear.
  final double topInset;

  /// A control at the end of the title row, usually the route's close button.
  final Widget? trailing;

  /// Height of the row below [topInset].
  final double extent;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PageHeaderDelegate(
        title: title,
        trailing: trailing,
        extent: topInset + extent,
      ),
    );
  }
}

class _PageHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PageHeaderDelegate({
    required this.title,
    required this.trailing,
    required this.extent,
  });

  final String title;
  final Widget? trailing;
  final double extent;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            FathomColors.background,
            FathomColors.background,
            FathomColors.background.withValues(alpha: 0),
          ],
          stops: const [0, 0.72, 1],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: FathomColors.onSurface,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_PageHeaderDelegate old) =>
      old.title != title || old.trailing != trailing || old.extent != extent;
}

/// A section label inside a page's scroll view.
///
/// Deliberately plain, not sticky: only the page title stays pinned, so the
/// section labels scroll with the rows they name. A pinned label over live rows
/// was the previous shape and it competed with the title for the same edge.
class SliverSectionLabel extends StatelessWidget {
  const SliverSectionLabel({
    super.key,
    required this.label,
    this.top = 22,
    this.bottom = 8,
    this.left = 20,
  });

  final String label;
  final double top;
  final double bottom;
  final double left;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(left, top, left, bottom),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            color: FathomColors.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
