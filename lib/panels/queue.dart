import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/player.dart';
import '../common/settings.dart';
import '../components/flat_icon_button.dart';
import '../models/tracks.dart';

class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<FathomPlayer>();
    final accent = context.watch<FathomSettings>().accent;
    final queue = player.queue;
    final current = player.selectedIndex;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text(
                  'Up Next',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: FlatIconButton(
                  icon: TablerIcons.x,
                  size: 20,
                  padding: const EdgeInsets.all(8),
                  color: Colors.white,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child: Text(
                      'Queue is empty',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: queue.length,
                    onReorder: (from, to) =>
                        context.read<FathomPlayer>().moveAt(from, to),
                    proxyDecorator: (child, index, anim) => Material(
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: child,
                      ),
                    ),
                    itemBuilder: (context, i) {
                      final track = queue[i];
                      final isCurrent = i == current;

                      return Material(
                        key: ValueKey('${track.id}_$i'),
                        color: Colors.transparent,
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () =>
                                    context.read<FathomPlayer>().playIndex(i),
                                onLongPress: () =>
                                    context.read<FathomPlayer>().removeAt(i),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        child: isCurrent
                                            ? Icon(
                                                TablerIcons.playerPlayFilled,
                                                size: 16,
                                                color: accent,
                                              )
                                            : Text(
                                                '${i + 1}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.4),
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              track.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: isCurrent
                                                    ? accent
                                                    : Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              track.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.white
                                                    .withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Icon(
                                  TablerIcons.gripVertical,
                                  size: 18,
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
