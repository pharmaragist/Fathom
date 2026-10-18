import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

const double kArtRadius = 12;

class FallbackArt extends StatelessWidget {
  const FallbackArt({
    super.key,
    this.size = 48,
    this.radius = kArtRadius,
  });

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: Colors.white.withValues(alpha: 0.08),
      ),
      child: Icon(
        TablerIcons.music,
        size: size * 0.45,
        color: Colors.white.withValues(alpha: 0.45),
      ),
    );
  }
}

class ArtThumb extends StatefulWidget {
  const ArtThumb({
    super.key,
    required this.id,
    required this.artwork,
    required this.size,
    this.radius = kArtRadius,
  });

  final int id;
  final Future<Uint8List?> artwork;
  final double size;
  final double radius;

  @override
  State<ArtThumb> createState() => _ArtThumbState();
}

class _ArtThumbState extends State<ArtThumb> {
  static final Map<int, Uint8List> _memCache = {};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ArtThumb old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _resolve();
    }
  }

  void _resolve() {
    if (_memCache.containsKey(widget.id)) {
      _bytes = _memCache[widget.id];
      return;
    }

    widget.artwork.then((data) {
      if (!mounted) return;
      if (data != null) {
        _memCache[widget.id] = data;
      }
      setState(() => _bytes = data);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes ?? _memCache[widget.id];

    if (bytes == null) {
      return FallbackArt(size: widget.size, radius: widget.radius);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Image.memory(
        bytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
      ),
    );
  }
}
