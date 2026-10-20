import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../common/colors.dart';
import '../common/library.dart';
import '../models/tracks.dart';
import '../services/artwork.dart';

const double kArtRadius = 12;

/// Artwork bytes for either origin behind one call.
Future<Uint8List?> trackArtBytes(FathomLibrary library, FathomTrack track) =>
    track.origin == TrackOrigin.ytMusic
        ? FathomArtCache.instance.forVideo(track.videoId!, track.thumbUri)
        : library.artFor(track.id);

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
        color: FathomColors.onSurface.withValues(alpha: 0.08),
      ),
      child: Icon(
        TablerIcons.music,
        size: size * 0.45,
        color: FathomColors.onSurface.withValues(alpha: 0.45),
      ),
    );
  }
}

/// Album art for a device track.
///
/// The bytes live in the library's own cache, so this widget only awaits the
/// future it is given and never keeps a second copy.
class ArtThumb extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: artwork,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return FallbackArt(size: size, radius: radius);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }
}

/// Artwork for a remote item, fetched from the shared cache.
///
/// Separate from [ArtThumb] because a remote item has no library id: its
/// identity is the `videoId`, and its bytes may not be on disk yet.
class RemoteArt extends StatefulWidget {
  const RemoteArt({
    super.key,
    required this.videoId,
    required this.thumbUri,
    required this.size,
    this.radius = kArtRadius,
  });

  final String videoId;
  final Uri? thumbUri;
  final double size;
  final double radius;

  @override
  State<RemoteArt> createState() => _RemoteArtState();
}

class _RemoteArtState extends State<RemoteArt> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = FathomArtCache.instance.forVideo(widget.videoId, widget.thumbUri);
  }

  @override
  void didUpdateWidget(RemoteArt old) {
    super.didUpdateWidget(old);
    if (old.videoId != widget.videoId) {
      _bytes =
          FathomArtCache.instance.forVideo(widget.videoId, widget.thumbUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
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
      },
    );
  }
}

/// Draws the right kind of artwork for a track's origin, so no surface has to
/// know where a track's bytes come from.
class TrackArt extends StatelessWidget {
  const TrackArt({
    super.key,
    required this.library,
    required this.track,
    required this.size,
    this.radius = kArtRadius,
  });

  final FathomLibrary library;
  final FathomTrack track;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return switch (track.origin) {
      TrackOrigin.device => ArtThumb(
          id: track.id,
          artwork: library.artFor(track.id),
          size: size,
          radius: radius,
        ),
      TrackOrigin.ytMusic => RemoteArt(
          videoId: track.videoId!,
          thumbUri: track.thumbUri,
          size: size,
          radius: radius,
        ),
    };
  }
}
