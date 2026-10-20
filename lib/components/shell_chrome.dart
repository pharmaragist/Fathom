import 'package:flutter/material.dart';

/// The fixed chrome every shell page wears: the ambient backdrop behind it and
/// the page header above it.
///
/// The shell builds this once and swaps only the page body underneath, because
/// both layers have to survive a page change. The backdrop animates between
/// accents and the header names the page you are on; if either lived inside the
/// page, switching pages would cross-fade them, and the backdrop would
/// duplicate or flicker mid-transition instead of staying put.
///
/// The header's own padding is spelled out here rather than left to a caller,
/// so every page lands on the same gutter: [PageHeader] carries no padding of
/// its own, and a page that added its own would drift from its neighbours.
class ShellChrome extends StatelessWidget {
  const ShellChrome({
    super.key,
    required this.header,
    required this.body,
    required this.backdrop,
  });

  /// The page's title row. The shell derives it from the active destination so
  /// the title and its controls can change with the page without the header
  /// itself being rebuilt as part of the page.
  final Widget header;

  /// The page's full layer, below the header.
  final Widget body;

  /// The ambient layer behind everything. The shell supplies the one that
  /// carries the playing track's artwork, so this stays a plain layer that
  /// knows nothing about the player.
  final Widget backdrop;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The backdrop is the bottom layer, so everything else paints over it.
        backdrop,
        Padding(
          // The status bar inset belongs to the header, not the backdrop: the
          // gradient has to reach under the system bars, while the row below
          // must clear them.
          padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: header,
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ],
    );
  }
}
