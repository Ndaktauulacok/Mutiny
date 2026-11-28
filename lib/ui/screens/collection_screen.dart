import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
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
import 'add_song_screen.dart';

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
    this.artist,
    this.collection,
    this.playContext,
  });

  factory CollectionScreen.remote(Collection c) => CollectionScreen._(
        kind: CollectionKind.remote,
        title: c.title,
        subtitle: c.subtitle.isEmpty ? 'Playlist' : 'Playlist · ${c.subtitle}',
        artworkUrl: c.artworkUrl,
        load: () => AudiusApi().playlistTracks(c.id),
        collection: c,
        playContext: PlayContext(
          type: PlayContextType.remote,
          id: c.id,
          title: c.title,
          subtitle: c.subtitle.isEmpty ? 'Playlist' : 'Playlist · ${c.subtitle}',
          artworkUrl: c.artworkUrl,
          data: c.toJson(),
        ),
      );

  factory CollectionScreen.artist({required Artist artist}) => CollectionScreen._(
        kind: CollectionKind.artist,
        title: artist.name,
        subtitle: artist.followers > 0 ? '${compactNumber(artist.followers)} followers' : 'Artist',
        artworkUrl: artist.avatarUrl,
        load: () => AudiusApi().artistTracks(artist.id),
        artist: artist,
        playContext: PlayContext(
          type: PlayContextType.artist,
          id: artist.id,
          title: artist.name,
          subtitle: 'Artist',
          artworkUrl: artist.avatarUrl,
          data: artist.toJson(),
        ),
      );

  factory CollectionScreen.genre(String genre, {int? index}) => CollectionScreen._(
        kind: CollectionKind.genre,
        title: genre,
        subtitle: 'Trending this week',
        cover: LiquidCover(index: index ?? genre.hashCode.abs() % 50, color: genreColor(genre), label: genre),
        load: () => AudiusApi().trending(genre: genre, limit: 50),
        playContext: PlayContext(type: PlayContextType.genre, id: genre, title: genre, subtitle: 'Genre', data: {'index': index}),
      );

  factory CollectionScreen.mix({
    required String title,
    required String subtitle,
    required Widget cover,
    required Future<List<Track>> Function() load,
    PlayContext? playContext,
  }) =>
      CollectionScreen._(kind: CollectionKind.mix, title: title, subtitle: subtitle, cover: cover, load: load, playContext: playContext);

  factory CollectionScreen.liked() => CollectionScreen._(
        kind: CollectionKind.liked,
        title: 'Liked Songs',
        cover: const _GradientCover(icon: Icons.favorite_rounded),
        playContext: PlayContext(type: PlayContextType.liked, id: 'liked', title: 'Liked Songs', subtitle: 'Playlist'),
      );

  factory CollectionScreen.local() => CollectionScreen._(
        kind: CollectionKind.local,
        title: 'My songs',
        subtitle: 'Only you can see these',
        cover: const _GradientCover(icon: Icons.library_music_rounded, colors: [Color(0xFF312E81), Color(0xFF7C3AED)]),
        playContext: mySongsContext(),
      );

  static PlayContext mySongsContext() =>
      PlayContext(type: PlayContextType.mySongs, id: 'mine', title: 'My songs', subtitle: 'Only you');

  factory CollectionScreen.recent() => const CollectionScreen._(
        kind: CollectionKind.recent,
        title: 'Recently played',
        cover: _GradientCover(icon: Icons.history_rounded, colors: [Color(0xFF581C87), Color(0xFFDB2777)]),
      );

  factory CollectionScreen.userPlaylist(UserPlaylist p) => CollectionScreen._(
        kind: CollectionKind.userPlaylist,
        title: p.name,
        playlistId: p.id,
        playContext: PlayContext(type: PlayContextType.playlist, id: p.id, title: p.name, subtitle: 'Playlist'),
      );

  final CollectionKind kind;
  final String title;
  final String subtitle;
  final String? artworkUrl;
  final Widget? cover;
  final Future<List<Track>> Function()? load;
  final String? playlistId;

  /// Set on artist pages (Follow button).
  final Artist? artist;

  /// Set on Audius playlists (Save to Library button).
  final Collection? collection;

  /// Remembered on Home ("Listening lately") when played from this page.
  final PlayContext? playContext;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  Future<List<Track>>? _future;
  final _filterCtrl = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _future = widget.load?.call();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  void _retry() => setState(() => _future = widget.load?.call());

  void _markPlayed(LibraryStore lib) {
    final c = widget.playContext;
    if (c == null) return;
    // A user playlist may have been renamed since this page opened.
    final p = widget.playlistId == null ? null : lib.playlistById(widget.playlistId!);
    lib.markPlayedFrom(p == null ? PlayContext(type: c.type, id: c.id, title: c.title, subtitle: c.subtitle, artworkUrl: c.artworkUrl, data: c.data)
        : PlayContext(type: c.type, id: c.id, title: p.name, subtitle: 'Playlist'));
  }

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

  String _subtitle(LibraryStore lib, List<Track>? tracks, UserPlaylist? playlist) {
    final count = tracks?.length ?? 0;
    final songs = '$count ${count == 1 ? 'song' : 'songs'}';
    switch (widget.kind) {
      case CollectionKind.userPlaylist:
        final mins = playlist!.totalSeconds ~/ 60;
        final len = mins >= 60 ? '${mins ~/ 60} hr ${mins % 60} min' : '$mins min';
        return '${lib.profile.name} · $songs${mins > 0 ? ' · $len' : ''}';
      case CollectionKind.local:
        return '$songs · only you can see these';
      case CollectionKind.liked:
      case CollectionKind.recent:
        return songs;
      default:
        return widget.subtitle;
    }
  }

  Widget _buildPage(BuildContext context, List<Track>? tracks, UserPlaylist? playlist, {bool error = false}) {
    final lib = context.read<LibraryStore>();
    final player = context.read<PlayerController>();
    final title = playlist?.name ?? widget.title;
    final isArtist = widget.kind == CollectionKind.artist;
    final q = _filter.toLowerCase();
    final shown = tracks == null || q.isEmpty
        ? tracks
        : tracks.where((t) => t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q)).toList();
    final canReorder = playlist != null && q.isEmpty;

    final cover = widget.cover ??
        (playlist != null
            ? PlaylistCover(playlist: playlist, radius: 22)
            : Artwork(url: widget.artworkUrl, radius: 22, circle: isArtist, icon: isArtist ? Icons.person_rounded : Icons.album_rounded));

    Widget tile(int i) => TrackTile(
          key: ValueKey('${shown![i].key}#$i'),
          track: shown[i],
          index: i,
          playlist: playlist,
          onTap: () {
            _markPlayed(lib);
            player.playTracks(shown, index: i, from: title);
          },
          trailing: canReorder
              ? ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.drag_handle_rounded, color: MColors.textTertiary),
                  ),
                )
              : null,
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                      GlassIconButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Add your song',
                        onTap: () => Navigator.of(context).push(FadeRoute(const AddSongScreen())),
                      ),
                    if (playlist != null)
                      GlassIconButton(icon: Icons.more_horiz_rounded, onTap: () => _playlistMenu(context, playlist)),
                    if (widget.kind == CollectionKind.recent && (tracks?.isNotEmpty ?? false))
                      GlassIconButton(
                        icon: Icons.delete_sweep_rounded,
                        tooltip: 'Clear history',
                        onTap: () => lib.clearHistory(),
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
                Pressable(
                  onTap: playlist == null ? null : () => showPlaylistEditor(context, playlist),
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
                if (playlist != null && playlist.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                    child: Text(playlist.description, style: MText.body, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
                  ),
                const SizedBox(height: 6),
                Text(_subtitle(lib, tracks, playlist), style: MText.caption),
                const SizedBox(height: 18),
                _SecondaryActions(widget: widget, playlist: playlist),
                if (tracks != null && tracks.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PillButton(label: 'Play', icon: Icons.play_arrow_rounded, filled: true, onTap: () {
                        _markPlayed(lib);
                        player.playTracks(tracks, from: title);
                      }),
                      const SizedBox(width: 12),
                      PillButton(label: 'Shuffle', icon: Icons.shuffle_rounded, onTap: () {
                        _markPlayed(lib);
                        player.playTracks(tracks, shuffled: true, from: title);
                      }),
                    ],
                  ),
                ],
                if (tracks != null && tracks.length > 6)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                    child: Glass(
                      radius: 14,
                      blur: 14,
                      child: SizedBox(
                        height: 42,
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            const Icon(Icons.search_rounded, size: 19, color: MColors.textTertiary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _filterCtrl,
                                onChanged: (v) => setState(() => _filter = v.trim()),
                                style: MText.body.copyWith(color: MColors.text),
                                decoration: InputDecoration(
                                  isCollapsed: true,
                                  border: InputBorder.none,
                                  hintText: 'Find in ${playlist != null ? 'playlist' : widget.kind == CollectionKind.liked ? 'Liked Songs' : 'this list'}',
                                  hintStyle: const TextStyle(color: MColors.textTertiary),
                                ),
                              ),
                            ),
                            if (_filter.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: MColors.textSecondary),
                                onPressed: () => setState(() {
                                  _filterCtrl.clear();
                                  _filter = '';
                                }),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          if (shown == null)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (error)
            SliverToBoxAdapter(
              child: Center(
                child: PillButton(label: "Couldn't load · Retry", icon: Icons.refresh_rounded, compact: true, onTap: _retry),
              ),
            )
          else if (shown.isEmpty)
            SliverToBoxAdapter(
              child: q.isNotEmpty
                  ? Padding(padding: const EdgeInsets.all(30), child: Text('No songs match “$_filter”', style: MText.body, textAlign: TextAlign.center))
                  : _EmptyState(
                      kind: widget.kind,
                      onImport: () => _import(context),
                      onAddSongs: playlist == null ? null : () => showAddSongs(context, playlist),
                    ),
            )
          else if (canReorder)
            SliverReorderableList(
              itemCount: shown.length,
              onReorderItem: (from, to) => lib.movePlaylistTrack(playlist, from, to),
              proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
              itemBuilder: (_, i) => tile(i),
            )
          else
            SliverList.builder(itemCount: shown.length, itemBuilder: (_, i) => tile(i)),
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
    final nav = Navigator.of(context);
    showGlassSheet(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          SheetAction(
            icon: Icons.add_rounded,
            label: 'Add songs',
            onTap: () {
              Navigator.pop(ctx);
              showAddSongs(context, p);
            },
          ),
          SheetAction(
            icon: Icons.edit_rounded,
            label: 'Edit details & cover',
            onTap: () {
              Navigator.pop(ctx);
              showPlaylistEditor(context, p);
            },
          ),
          SheetAction(
            icon: p.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
            label: p.pinned ? 'Unpin from Library' : 'Pin to top of Library',
            onTap: () {
              Navigator.pop(ctx);
              lib.togglePin(p);
            },
          ),
          SheetAction(
            icon: Icons.copy_rounded,
            label: 'Duplicate playlist',
            onTap: () {
              Navigator.pop(ctx);
              final copy = lib.duplicatePlaylist(p);
              nav.push(FadeRoute(CollectionScreen.userPlaylist(copy)));
            },
          ),
          SheetAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete playlist',
            danger: true,
            onTap: () {
              Navigator.pop(ctx);
              lib.deletePlaylist(p);
              nav.maybePop();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Follow (artists), Save (other people's playlists), Add songs / Edit
/// (your playlists).
class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions({required this.widget, required this.playlist});

  final CollectionScreen widget;
  final UserPlaylist? playlist;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    if (widget.artist != null) {
      final following = lib.isFollowing(widget.artist!);
      return PillButton(
        label: following ? 'Following' : 'Follow',
        icon: following ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
        compact: true,
        onTap: () => lib.toggleFollow(widget.artist!),
      );
    }
    if (widget.collection != null) {
      final saved = lib.isPlaylistSaved(widget.collection!);
      return PillButton(
        label: saved ? 'Saved to Library' : 'Save to Library',
        icon: saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        compact: true,
        onTap: () {
          final now = lib.toggleSavePlaylist(widget.collection!);
          toast(context, now ? 'Saved to your Library' : 'Removed from your Library');
        },
      );
    }
    if (playlist != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PillButton(label: 'Add songs', icon: Icons.add_rounded, compact: true, onTap: () => showAddSongs(context, playlist!)),
          const SizedBox(width: 8),
          PillButton(label: 'Edit', icon: Icons.edit_rounded, compact: true, onTap: () => showPlaylistEditor(context, playlist!)),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

bool get _hasCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Edit a playlist's cover photo, name and description.
void showPlaylistEditor(BuildContext context, UserPlaylist p) {
  final lib = context.read<LibraryStore>();
  final name = TextEditingController(text: p.name);
  final desc = TextEditingController(text: p.description);
  showGlassSheet(
    context,
    builder: (ctx) => ListenableBuilder(
      listenable: lib,
      builder: (ctx, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Edit playlist', style: MText.h2),
            const SizedBox(height: 18),
            SizedBox.square(dimension: 150, child: PlaylistCover(playlist: p, radius: 18)),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                PillButton(label: 'Choose photo', icon: Icons.photo_library_rounded, compact: true, onTap: () => lib.pickPlaylistCover(p)),
                if (_hasCamera)
                  PillButton(
                    label: 'Take photo',
                    icon: Icons.photo_camera_rounded,
                    compact: true,
                    onTap: () => lib.pickPlaylistCover(p, source: ImageSource.camera),
                  ),
                if (p.coverPath != null)
                  PillButton(label: 'Use song covers', icon: Icons.grid_view_rounded, compact: true, onTap: () => lib.removePlaylistCover(p)),
              ],
            ),
            const SizedBox(height: 18),
            _Field(controller: name, label: 'Name', maxLength: 60),
            const SizedBox(height: 10),
            _Field(controller: desc, label: 'Description (optional)', maxLength: 200, lines: 3),
            const SizedBox(height: 22),
            PillButton(
              label: 'Save',
              filled: true,
              onTap: () {
                lib.editPlaylist(p, name: name.text, description: desc.text);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label, this.maxLength, this.lines = 1});

  final TextEditingController controller;
  final String label;
  final int? maxLength;
  final int lines;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLength: maxLength,
        minLines: 1,
        maxLines: lines,
        style: const TextStyle(fontSize: 16, color: MColors.text, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: MColors.textTertiary),
          counterText: '',
          filled: true,
          fillColor: const Color(0x12FFFFFF),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: MColors.lavender)),
        ),
      );
}

/// Search Audius and tap + to add songs straight into a playlist.
void showAddSongs(BuildContext context, UserPlaylist p) {
  showGlassSheet(context, builder: (_) => _AddSongsView(playlist: p));
}

class _AddSongsView extends StatefulWidget {
  const _AddSongsView({required this.playlist});
  final UserPlaylist playlist;

  @override
  State<_AddSongsView> createState() => _AddSongsViewState();
}

class _AddSongsViewState extends State<_AddSongsView> {
  final _api = AudiusApi();
  Timer? _debounce;
  String _query = '';
  late Future<List<Track>> _future = _suggestions();

  Future<List<Track>> _suggestions() {
    final genres = widget.playlist.tracks.map((t) => t.genre).whereType<String>().where(AudiusApi.genres.contains).toList();
    return _api.trending(genre: genres.isEmpty ? null : genres.first, limit: 30);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
            child: Text('Add to ${widget.playlist.name}', style: MText.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Glass(
              radius: 14,
              blur: 14,
              child: SizedBox(
                height: 46,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(Icons.search_rounded, color: MColors.lavender, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        autofocus: false,
                        style: MText.title.copyWith(fontWeight: FontWeight.w500),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: 'Search songs to add',
                          hintStyle: TextStyle(color: MColors.textTertiary, fontWeight: FontWeight.w400),
                        ),
                        onChanged: (v) {
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 400), () {
                            setState(() {
                              _query = v.trim();
                              _future = _query.isEmpty ? _suggestions() : _api.searchTracks(_query);
                            });
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_query.isEmpty ? 'RECOMMENDED' : 'RESULTS', style: MText.label),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Track>>(
              future: _future,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }
                final q = _query.toLowerCase();
                final mine = lib.localTracks
                    .where((t) => q.isEmpty || t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q))
                    .toList();
                final list = [...mine, ...?snap.data];
                if (list.isEmpty) return const Center(child: Text('No songs found', style: MText.body));
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final t = list[i];
                    final added = widget.playlist.tracks.contains(t);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                      child: Row(
                        children: [
                          Artwork(url: t.artworkUrl, size: 48, radius: 8, icon: t.isLocal ? Icons.library_music_rounded : Icons.music_note_rounded),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: MText.title),
                                Text(t.isLocal ? 'My song · ${t.artist}' : t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: MText.caption),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                              child: Icon(
                                added ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                key: ValueKey(added),
                                color: added ? MColors.lavender : MColors.textSecondary,
                                size: 28,
                              ),
                            ),
                            onPressed: () {
                              if (added) {
                                lib.removeFromPlaylist(widget.playlist, t);
                              } else {
                                lib.addToPlaylist(widget.playlist, t);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.kind, required this.onImport, this.onAddSongs});

  final CollectionKind kind;
  final VoidCallback onImport;
  final VoidCallback? onAddSongs;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (kind) {
      CollectionKind.liked => (Icons.favorite_border_rounded, 'Songs you like will show up here.\nTap ♡ on any song.'),
      CollectionKind.local => (Icons.library_music_rounded, 'Add your own songs with a name, cover\nand lyrics. Only you can see them.'),
      CollectionKind.userPlaylist => (Icons.playlist_add_rounded, "Let's find some songs for your playlist."),
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
            PillButton(
              label: 'Add a song',
              icon: Icons.add_rounded,
              filled: true,
              onTap: () => Navigator.of(context).push(FadeRoute(const AddSongScreen())),
            ),
            const SizedBox(height: 10),
            PillButton(label: 'Import many files', icon: Icons.drive_folder_upload_rounded, compact: true, onTap: onImport),
          ],
          if (onAddSongs != null) ...[
            const SizedBox(height: 20),
            PillButton(label: 'Add songs', icon: Icons.add_rounded, filled: true, onTap: onAddSongs),
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
  Color(0xFF8A3FFC),
  Color(0xFF6A1FD1),
  Color(0xFFA259FF),
  Color(0xFF5A189A),
  Color(0xFF7B2CBF),
  Color(0xFF9D4EDD),
  Color(0xFF3C096C),
  Color(0xFFB57BFF),
];

Color genreColor(String genre) => _genrePalette[genre.codeUnits.fold<int>(0, (a, b) => a + b) % _genrePalette.length];
