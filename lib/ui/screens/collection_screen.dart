import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/audius_api.dart';
import '../../services/library_store.dart';
import '../../services/player_controller.dart';
import '../effects.dart';
import '../glass.dart';
import '../theme.dart';
import '../widgets.dart';

enum CollectionKind { remote, artist, genre, mix, liked, local, userPlaylist, recent }

/// One page for every list of songs: Audius playlists, artists, genres,
/// daily mixes, Liked Songs, files on this device and your own playlists.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen._({
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.artworkUrl,
    this.cover,
    this.load,
    this.playlistId,
  });

  factory CollectionScreen.remote(Collection c) => CollectionScreen._(
        kind: CollectionKind.remote,
        title: c.title,
        subtitle: c.subtitle.isEmpty ? 'Playlist' : 'Playlist · ${c.subtitle}',
        artworkUrl: c.artworkUrl,
        load: () => AudiusApi().playlistTracks(c.id),
      );

  factory CollectionScreen.artist({required Artist artist}) => CollectionScreen._(
        kind: CollectionKind.artist,
        title: artist.name,
        subtitle: artist.followers > 0 ? '${compactNumber(artist.followers)} followers' : 'Artist',
        artworkUrl: artist.avatarUrl,
        load: () => AudiusApi().artistTracks(artist.id),
      );

  factory CollectionScreen.genre(String genre, {int? index}) => CollectionScreen._(
        kind: CollectionKind.genre,
        title: genre,
        subtitle: 'Trending this week',
        cover: LiquidCover(index: index ?? genre.hashCode.abs() % 50, color: genreColor(genre), label: genre),
        load: () => AudiusApi().trending(genre: genre, limit: 50),
      );

  factory CollectionScreen.mix({required String title, required String subtitle, required Widget cover, required Future<List<Track>> Function() load}) =>
      CollectionScreen._(kind: CollectionKind.mix, title: title, subtitle: subtitle, cover: cover, load: load);

  factory CollectionScreen.liked() => const CollectionScreen._(
        kind: CollectionKind.liked,
        title: 'Liked Songs',
        cover: _GradientCover(icon: Icons.favorite_rounded),
      );

  factory CollectionScreen.local() => const CollectionScreen._(
        kind: CollectionKind.local,
        title: 'On this device',
        cover: _GradientCover(icon: Icons.folder_rounded, colors: [Color(0xFF312E81), Color(0xFF7C3AED)]),
      );

  factory CollectionScreen.recent() => const CollectionScreen._(
        kind: CollectionKind.recent,
        title: 'Recently played',
        cover: _GradientCover(icon: Icons.history_rounded, colors: [Color(0xFF581C87), Color(0xFFDB2777)]),
      );

  factory CollectionScreen.userPlaylist(UserPlaylist p) => CollectionScreen._(
        kind: CollectionKind.userPlaylist,
        title: p.name,
        playlistId: p.id,
      );

  final CollectionKind kind;
  final String title;
  final String subtitle;
  final String? artworkUrl;
  final Widget? cover;
  final Future<List<Track>> Function()? load;
  final String? playlistId;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  Future<List<Track>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load?.call();
  }

  void _retry() => setState(() => _future = widget.load?.call());

  List<Track>? _liveTracks(LibraryStore lib) => switch (widget.kind) {
        CollectionKind.liked => lib.liked,
        CollectionKind.local => lib.localTracks,
        CollectionKind.recent => lib.recent,
        CollectionKind.userPlaylist => lib.playlistById(widget.playlistId!)?.tracks,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final playlist = widget.playlistId == null ? null : lib.playlistById(widget.playlistId!);
    if (widget.kind == CollectionKind.userPlaylist && playlist == null) {
      return const SizedBox.shrink(); // deleted
    }
    final live = _liveTracks(lib);
    if (live != null) return _buildPage(context, live, playlist);
    return FutureBuilder<List<Track>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _buildPage(context, null, null);
        if (snap.hasError) return _buildPage(context, const [], null, error: true);
        return _buildPage(context, snap.data ?? const [], null);
      },
    );
  }

  Widget _buildPage(BuildContext context, List<Track>? tracks, UserPlaylist? playlist, {bool error = false}) {
    final player = context.read<PlayerController>();
    final title = playlist?.name ?? widget.title;
    final count = tracks?.length ?? 0;
    final subtitle = switch (widget.kind) {
      CollectionKind.liked || CollectionKind.local || CollectionKind.recent || CollectionKind.userPlaylist =>
        '$count ${count == 1 ? 'song' : 'songs'}',
      _ => widget.subtitle,
    };
    final isArtist = widget.kind == CollectionKind.artist;
    final cover = widget.cover ??
        (playlist != null
            ? (playlist.coverUrl == null
                ? const _GradientCover(icon: Icons.queue_music_rounded)
                : Artwork(url: playlist.coverUrl, radius: 22))
            : Artwork(url: widget.artworkUrl, radius: 22, circle: isArtist, icon: isArtist ? Icons.person_rounded : Icons.album_rounded));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, iconSize: 17, onTap: () => Navigator.maybePop(context)),
                    const Spacer(),
                    if (widget.kind == CollectionKind.local)
                      GlassIconButton(icon: Icons.add_rounded, tooltip: 'Import files', onTap: () => _import(context)),
                    if (playlist != null)
                      GlassIconButton(icon: Icons.more_horiz_rounded, onTap: () => _playlistMenu(context, playlist)),
                    if (widget.kind == CollectionKind.recent && (tracks?.isNotEmpty ?? false))
                      GlassIconButton(
                        icon: Icons.delete_sweep_rounded,
                        tooltip: 'Clear history',
                        onTap: () => context.read<LibraryStore>().clearHistory(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 10),
                Hero(
                  tag: 'cover:${widget.kind}:${widget.playlistId ?? title}',
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: isArtist ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: isArtist ? null : BorderRadius.circular(22),
                      boxShadow: [BoxShadow(color: MColors.violet.withValues(alpha: 0.35), blurRadius: 50, offset: const Offset(0, 18))],
                    ),
                    child: cover,
                  ),
                ),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Text(title, style: MText.h1, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: MText.body),
                const SizedBox(height: 20),
                if (tracks != null && tracks.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PillButton(
                        label: 'Play',
                        icon: Icons.play_arrow_rounded,
                        filled: true,
                        onTap: () => player.playTracks(tracks, from: title),
                      ),
                      const SizedBox(width: 12),
                      PillButton(
                        label: 'Shuffle',
                        icon: Icons.shuffle_rounded,
                        onTap: () => player.playTracks(tracks, shuffled: true, from: title),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
              ],
            ),
          ),
          if (tracks == null)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (error)
            SliverToBoxAdapter(
              child: Center(
                child: PillButton(label: "Couldn't load · Retry", icon: Icons.refresh_rounded, compact: true, onTap: _retry),
              ),
            )
          else if (tracks.isEmpty)
            SliverToBoxAdapter(child: _EmptyState(kind: widget.kind, onImport: () => _import(context)))
          else
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) => TrackTile(
                track: tracks[i],
                index: i,
                playlist: playlist,
                onTap: () => player.playTracks(tracks, index: i, from: title),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: bottomInset(context))),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final lib = context.read<LibraryStore>();
    final n = await lib.importLocalFiles();
    if (context.mounted && n > 0) toast(context, 'Added $n ${n == 1 ? 'song' : 'songs'}');
  }

  void _playlistMenu(BuildContext context, UserPlaylist p) {
    final lib = context.read<LibraryStore>();
    showGlassSheet(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          SheetAction(
            icon: Icons.edit_rounded,
            label: 'Rename',
            onTap: () async {
              Navigator.pop(ctx);
              final name = await askText(context, title: 'Rename playlist', initial: p.name);
              if (name != null) lib.renamePlaylist(p, name);
            },
          ),
          SheetAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete playlist',
            danger: true,
            onTap: () {
              Navigator.pop(ctx);
              lib.deletePlaylist(p);
              Navigator.maybePop(context);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.kind, required this.onImport});

  final CollectionKind kind;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (kind) {
      CollectionKind.liked => (Icons.favorite_border_rounded, 'Songs you like will show up here.\nTap ♡ on any song.'),
      CollectionKind.local => (Icons.audio_file_rounded, 'Add MP3, M4A, FLAC or WAV files\nfrom your device.'),
      CollectionKind.userPlaylist => (Icons.playlist_add_rounded, 'Add songs with ••• → Add to playlist.'),
      CollectionKind.recent => (Icons.history_rounded, 'Nothing played yet.'),
      _ => (Icons.music_off_rounded, 'No songs here.'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 30, 40, 10),
      child: Column(
        children: [
          Icon(icon, color: MColors.lavender, size: 40),
          const SizedBox(height: 14),
          Text(text, style: MText.body, textAlign: TextAlign.center),
          if (kind == CollectionKind.local) ...[
            const SizedBox(height: 20),
            PillButton(label: 'Import files', icon: Icons.add_rounded, filled: true, onTap: onImport),
          ],
        ],
      ),
    );
  }
}

class _GradientCover extends StatelessWidget {
  const _GradientCover({required this.icon, this.colors = const [Color(0xFF4C1D95), Color(0xFFC4B5FD)]});

  final IconData icon;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: colors),
        ),
        child: LayoutBuilder(
          builder: (_, c) => Center(child: Icon(icon, color: Colors.white, size: c.biggest.shortestSide * 0.36)),
        ),
      );
}

/// Library tiles reuse the same gradient covers.
Widget gradientCover(IconData icon, {List<Color>? colors}) =>
    colors == null ? _GradientCover(icon: icon) : _GradientCover(icon: icon, colors: colors);

const _genrePalette = [
  Color(0xFF8B5CF6),
  Color(0xFF6D28D9),
  Color(0xFFC084FC),
  Color(0xFFD946EF),
  Color(0xFF7C3AED),
  Color(0xFF6366F1),
  Color(0xFFA855F7),
  Color(0xFF9333EA),
];

Color genreColor(String genre) => _genrePalette[genre.codeUnits.fold<int>(0, (a, b) => a + b) % _genrePalette.length];
