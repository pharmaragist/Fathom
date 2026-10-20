import 'package:flutter/foundation.dart';

/// The one search field's query.
///
/// There is a single page now, so the field needs no source to bind to. The
/// notifier stays rather than the page owning the text because the rail, the
/// page and the shell's dismiss layer all read it from different places.
class FathomSearch extends ChangeNotifier {
  final ValueNotifier<String> query = ValueNotifier<String>('');

  /// Empties the query, which is what "show everything" means.
  void clear() => query.value = '';

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }
}
