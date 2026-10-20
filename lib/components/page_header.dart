import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/library.dart';
import '../pages/settings.dart';
import 'flat_icon_button.dart';

/// The title row every main page wears.
///
/// Pages compose their own trailing controls; [shellTrailing] is the set the
/// shell pages share, so a page never re-implements the icons.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.trailing = const []});

  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: FathomColors.onSurface,
              letterSpacing: -0.8,
            ),
          ),
        ),
        ...trailing,
      ],
    );
  }
}

/// Settings and Rescan — the controls every main page carries.
/// Pages pass this as their `trailing`. The equalizer is a nav destination,
/// not a header control.
List<Widget> shellTrailing(BuildContext context) => [
      FlatIconButton(
        icon: TablerIcons.settings,
        size: 22,
        padding: const EdgeInsets.all(8),
        color: FathomColors.onSurface,
        onTap: () => Navigator.of(context).push(settingsRoute()),
      ),
      FlatIconButton(
        icon: TablerIcons.refresh,
        size: 22,
        padding: const EdgeInsets.all(8),
        color: FathomColors.onSurface,
        onTap: () => context.read<FathomLibrary>().load(grantIfMissing: false),
      ),
    ];

/// Right-sliding route, the motion both the header's pushed pages use.
Route<void> utilityRoute(Widget page) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: child,
    ),
  );
}

Route<void> settingsRoute() => utilityRoute(const SettingsPage());
