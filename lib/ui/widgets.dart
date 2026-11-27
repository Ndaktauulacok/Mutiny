import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/library_store.dart';
import '../services/player_controller.dart';
import 'effects.dart';
import 'glass.dart';
import 'screens/collection_screen.dart';
import 'theme.dart';

/// Space reserved at the bottom of every scroll view for the floating
/// mini player and tab bar.
double bottomInset(BuildContext context) => MediaQuery.paddingOf(context).bottom + 170;

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.accentWord, this.action, this.onAction});

  final String title;

  /// Last word drawn in lavender, like "Your **Mixes**".
  final String? accentWord;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: title),
                if (accentWord != null)
                  TextSpan(text: ' $accentWord', style: const TextStyle(color: MColors.lavender)),
              ]),
              style: MText.h2,
            ),
          ),
          if (action != null)
            Pressable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(action!, style: MText.caption.copyWith(color: MColors.lavender, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// One song row. Highlights itself and shows equalizer bars when playing.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.index,
    this.playlist,
    this.showArtwork = true,
  });

  final Track track;
  final VoidCallback onTap;
  final int? index;
  final UserPlaylist? playlist;
  final bool showArtwork;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final isCurrent = player.current == track;
    return Pressable(
      onTap: onTap,
      onLongPress: () => showTrackMenu(context, track, playlist: playlist),
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            if (showArtwork)
              Stack(
                children: [
                  Artwork(
                    url: track.artworkUrl,
                    size: 50,
                    radius: track.isLive ? 12 : 8,
                    icon: _iconFor(track),
                    fit: track.isLive ? BoxFit.contain : BoxFit.cover,
                  ),
                  if (isCurrent)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x8C0A0612),
                          borderRadius: BorderRadius.circular(track.isLive ? 12 : 8),
                        ),
                        child: Center(child: EqualizerBars(playing: player.playing, size: 16)),
                      ),
                    ),
                ],
              )
            else
              SizedBox(
                width: 28,
                child: isCurrent
                    ? EqualizerBars(playing: player.playing, size: 14)
                    : Text('${(index ?? 0) + 1}', style: MText.caption, textAlign: TextAlign.center),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MText.title.copyWith(color: isCurrent ? MColors.lavender : MColors.text),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (track.isLive) ...[const _LiveDot(), const SizedBox(width: 6)],
                      if (track.isLocal) ...[
                        const Icon(Icons.download_done_rounded, size: 13, color: MColors.lavender),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MText.body.copyWith(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (track.durationSec != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(formatDuration(Duration(seconds: track.durationSec!)), style: MText.caption),
              ),
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded, color: MColors.textSecondary),
              onPressed: () => showTrackMenu(context, track, playlist: playlist),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(Track t) => switch (t.source) {
      TrackSource.radio => Icons.radio_rounded,
      TrackSource.local => Icons.audio_file_rounded,
      TrackSource.audius => Icons.music_note_rounded,
    };

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: const Color(0x33F472B6), borderRadius: BorderRadius.circular(4)),
        child: const Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFF9A8D4), letterSpacing: 0.8)),
      );
}

/// Square artwork card used in horizontal carousels.
class CoverCard extends StatelessWidget {
  const CoverCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.artworkUrl,
    this.cover,
    this.size = 150,
    this.circle = false,
    this.onLongPress,
    this.icon = Icons.music_note_rounded,
    this.contain = false,
  });

  final String title;
  final String subtitle;
  final String? artworkUrl;
  final Widget? cover;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double size;
  final bool circle;
  final IconData icon;
  final bool contain;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            SizedBox.square(
              dimension: size,
              child: cover ??
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: circle ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: circle ? null : BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))],
                    ),
                    child: Artwork(
                      url: artworkUrl,
                      radius: 16,
                      circle: circle,
                      icon: icon,
                      fit: contain ? BoxFit.contain : BoxFit.cover,
                    ),
                  ),
            ),
            const SizedBox(height: 9),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: circle ? TextAlign.center : TextAlign.start,
              style: MText.title.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: circle ? TextAlign.center : TextAlign.start,
              style: MText.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class HorizontalList extends StatelessWidget {
  const HorizontalList({super.key, required this.itemCount, required this.itemBuilder, this.height = 210});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: itemBuilder,
        ),
      );
}

/// Loading / error / empty states for a future-backed section.
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({super.key, required this.future, required this.builder, this.height = 210, this.onRetry});

  final Future<T>? future;
  final Widget Function(T data) builder;
  final double height;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(height: height, child: const ShimmerRow());
        }
        if (snap.hasError || !snap.hasData) {
          return SizedBox(
            height: 90,
            child: Center(
              child: Pressable(
                onTap: onRetry,
                child: const Text("Couldn't load · tap to retry", style: MText.caption),
              ),
            ),
          );
        }
        return builder(snap.data as T);
      },
    );
  }
}

/// Pulsing placeholder cards while content loads.
class ShimmerRow extends StatefulWidget {
  const ShimmerRow({super.key});

  @override
  State<ShimmerRow> createState() => _ShimmerRowState();
}

class _ShimmerRowState extends State<ShimmerRow> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 0.8).animate(_c),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(color: const Color(0x1FC4B5FD), borderRadius: BorderRadius.circular(16)),
                ),
                const SizedBox(height: 10),
                Container(width: 110, height: 10, color: const Color(0x1FC4B5FD)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ song menu

Future<void> showTrackMenu(BuildContext context, Track track, {UserPlaylist? playlist}) {
  final library = context.read<LibraryStore>();
  final player = context.read<PlayerController>();
  final navigator = Navigator.of(context);
  final messengerContext = context;
  return showGlassSheet(
    context,
    builder: (ctx) {
      final liked = library.isLiked(track);
      void close() => Navigator.pop(ctx);
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
              child: Row(
                children: [
                  Artwork(url: track.artworkUrl, size: 54, radius: 10, fit: track.isLive ? BoxFit.contain : BoxFit.cover),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: MText.title),
                        const SizedBox(height: 3),
                        Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: MText.body),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: MColors.hairline, height: 18),
            SheetAction(
              icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              label: track.isLive
                  ? (liked ? 'Remove from saved stations' : 'Save station')
                  : (liked ? 'Remove from Liked Songs' : 'Add to Liked Songs'),
              onTap: () {
                close();
                final now = library.toggleLike(track);
                toast(messengerContext, now ? (track.isLive ? 'Station saved' : 'Added to Liked Songs') : 'Removed');
              },
            ),
            if (!track.isLive) ...[
              SheetAction(
                icon: Icons.playlist_add_rounded,
                label: 'Add to playlist',
                onTap: () {
                  close();
                  showAddToPlaylist(messengerContext, track);
                },
              ),
              SheetAction(
                icon: Icons.queue_play_next_rounded,
                label: 'Play next',
                onTap: () {
                  close();
                  player.playNext(track);
                },
              ),
              SheetAction(
                icon: Icons.queue_music_rounded,
                label: 'Add to queue',
                onTap: () {
                  close();
                  player.addToQueue(track);
                },
              ),
            ],
            if (track.artistId != null)
              SheetAction(
                icon: Icons.person_rounded,
                label: 'Go to artist',
                onTap: () {
                  close();
                  navigator.push(FadeRoute(CollectionScreen.artist(
                    artist: Artist(id: track.artistId!, name: track.artist),
                  )));
                },
              ),
            if (playlist != null)
              SheetAction(
                icon: Icons.remove_circle_outline_rounded,
                label: 'Remove from this playlist',
                danger: true,
                onTap: () {
                  close();
                  library.removeFromPlaylist(playlist, track);
                },
              ),
            if (track.isLocal)
              SheetAction(
                icon: Icons.delete_outline_rounded,
                label: 'Remove from this device',
                danger: true,
                onTap: () {
                  close();
                  library.removeLocal(track);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> showAddToPlaylist(BuildContext context, Track track) {
  final library = context.read<LibraryStore>();
  return showGlassSheet(
    context,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: 14, bottom: 10),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Add to playlist', style: MText.h2, textAlign: TextAlign.center),
          ),
          SheetAction(
            icon: Icons.add_rounded,
            label: 'New playlist',
            onTap: () async {
              Navigator.pop(ctx);
              final name = await askText(context, title: 'Name your playlist', action: 'Create');
              if (name == null) return;
              library.createPlaylist(name, tracks: [track]);
              if (context.mounted) toast(context, 'Playlist created');
            },
          ),
          for (final p in library.playlists)
            Pressable(
              onTap: () {
                Navigator.pop(ctx);
                final added = library.addToPlaylist(p, track);
                toast(context, added ? 'Added to ${p.name}' : 'Already in ${p.name}');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                child: Row(
                  children: [
                    Artwork(url: p.coverUrl, size: 46, radius: 8, icon: Icons.queue_music_rounded),
                    const SizedBox(width: 14),
                    Expanded(child: Text(p.name, style: MText.title)),
                    Text('${p.tracks.length}', style: MText.caption),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
