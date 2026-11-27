import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../services/library_store.dart';
import '../../services/player_controller.dart';
import '../glass.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_song_screen.dart';
import 'collection_screen.dart';
import 'profile_screen.dart';

enum _Filter { all, playlists, artists, stations, files }

enum _Sort { recents, alphabetical, creator }

/// One row/tile in the Library, whatever it is.
class _Item {
  final String title;
  final String subtitle;
  final Widget cover;
  final bool circle;
  final bool pinned;
  final int order; // lower = more recent
  final String creator;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _Item({
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.onTap,
    this.circle = false,
    this.pinned = false,
    this.order = 0,
    this.creator = '',
    this.onLongPress,
  });
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.recents;
  bool _grid = false;

  Future<void> _newPlaylist() async {
    final name = await askText(context, title: 'Name your playlist', action: 'Create');
    if (name == null || !mounted) return;
    final p = context.read<LibraryStore>().createPlaylist(name);
    _open(CollectionScreen.userPlaylist(p));
  }

  void _open(Widget page) => Navigator.of(context).push(FadeRoute(page));

  void _createMenu() {
    showGlassSheet(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          SheetAction(
            icon: Icons.queue_music_rounded,
            label: 'Create playlist',
            onTap: () {
              Navigator.pop(ctx);
              _newPlaylist();
            },
          ),
          SheetAction(
            icon: Icons.library_add_rounded,
            label: 'Add your own song',
            onTap: () {
              Navigator.pop(ctx);
              _open(const AddSongScreen());
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<_Item> _items(LibraryStore lib, PlayerController player) {
    final me = lib.profile.name;
    final items = <_Item>[];
    bool show(_Filter f) => _filter == _Filter.all || _filter == f;

    if (show(_Filter.playlists)) {
      items.add(_Item(
        title: 'Liked Songs',
        subtitle: 'Playlist · ${songs(lib.liked.length)}',
        cover: gradientCover(Icons.favorite_rounded),
        pinned: true,
        order: -3,
        creator: me,
        onTap: () => _open(CollectionScreen.liked()),
      ));
      final byUpdate = [...lib.playlists]..sort((a, b) => b.updated.compareTo(a.updated));
      for (final (i, p) in byUpdate.indexed) {
        items.add(_Item(
          title: p.name,
          subtitle: 'Playlist · $me',
          cover: PlaylistCover(playlist: p, radius: 10),
          pinned: p.pinned,
          order: i,
          creator: me,
          onTap: () => _open(CollectionScreen.userPlaylist(p)),
        ));
      }
      for (final (i, c) in lib.savedPlaylists.indexed) {
        items.add(_Item(
          title: c.title,
          subtitle: 'Playlist · ${c.subtitle}',
          cover: Artwork(url: c.artworkUrl, radius: 10, icon: Icons.queue_music_rounded),
          order: i * 2 + 1,
          creator: c.subtitle,
          onTap: () => _open(CollectionScreen.remote(c)),
        ));
      }
    }
    if (show(_Filter.artists)) {
      for (final (i, a) in lib.followedArtists.indexed) {
        items.add(_Item(
          title: a.name,
          subtitle: 'Artist',
          cover: Artwork(url: a.avatarUrl, circle: true, icon: Icons.person_rounded),
          circle: true,
          order: i * 2 + 1,
          creator: a.name,
          onTap: () => _open(CollectionScreen.artist(artist: a)),
        ));
      }
    }
    if (_filter == _Filter.all) {
      items.add(_Item(
        title: 'My songs',
        subtitle: '${songs(lib.localTracks.length)} · only you',
        cover: gradientCover(Icons.library_music_rounded, colors: const [Color(0xFF312E81), Color(0xFF7C3AED)]),
        pinned: true,
        order: -2,
        creator: me,
        onTap: () => _open(CollectionScreen.local()),
      ));
      items.add(_Item(
        title: 'Recently played',
        subtitle: songs(lib.recent.length),
        cover: gradientCover(Icons.history_rounded, colors: const [Color(0xFF581C87), Color(0xFFDB2777)]),
        order: -1,
        creator: me,
        onTap: () => _open(CollectionScreen.recent()),
      ));
    }
    if (show(_Filter.stations)) {
      for (final (i, s) in lib.stations.indexed) {
        items.add(_Item(
          title: s.title,
          subtitle: 'Radio station',
          cover: Artwork(url: s.artworkUrl, radius: 10, icon: Icons.radio_rounded, fit: BoxFit.contain),
          order: i * 2 + 1,
          creator: s.title,
          onTap: () => player.playTrack(s, from: 'Radio'),
          onLongPress: () => showTrackMenu(context, s),
        ));
      }
    }

    int compare(_Item a, _Item b) => switch (_sort) {
          _Sort.recents => a.order.compareTo(b.order),
          _Sort.alphabetical => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          _Sort.creator => a.creator.toLowerCase().compareTo(b.creator.toLowerCase()),
        };
    final pinned = items.where((i) => i.pinned).toList()..sort((a, b) => a.order.compareTo(b.order));
    final rest = items.where((i) => !i.pinned).toList()..sort(compare);
    return [...pinned, ...rest];
  }

  void _pickSort() {
    showGlassSheet(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(0, 16, 0, 8), child: Text('Sort by', style: MText.h2)),
          for (final (s, label, icon) in const [
            (_Sort.recents, 'Recents', Icons.schedule_rounded),
            (_Sort.alphabetical, 'Alphabetical', Icons.sort_by_alpha_rounded),
            (_Sort.creator, 'Creator', Icons.person_outline_rounded),
          ])
            SheetAction(
              icon: _sort == s ? Icons.check_rounded : icon,
              label: label,
              onTap: () {
                setState(() => _sort = s);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final top = MediaQuery.paddingOf(context).top;
    final items = _items(lib, player);
    final sortLabel = switch (_sort) {
      _Sort.recents => 'Recents',
      _Sort.alphabetical => 'Alphabetical',
      _Sort.creator => 'Creator',
    };

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, top + 12, 16, 0),
            child: Row(
              children: [
                Pressable(
                  onTap: () => _open(const ProfileScreen()),
                  scale: 0.9,
                  child: ProfileAvatar(profile: lib.profile, size: 38),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Your Library', style: MText.h1)),
                GlassIconButton(icon: Icons.add_rounded, onTap: _createMenu, tooltip: 'Create'),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              children: [
                for (final (f, label) in const [
                  (_Filter.all, 'All'),
                  (_Filter.playlists, 'Playlists'),
                  (_Filter.artists, 'Artists'),
                  (_Filter.stations, 'Stations'),
                  (_Filter.files, 'My songs'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GlassChip(label: label, selected: _filter == f, onTap: () => setState(() => _filter = f)),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 8, 4),
            child: Row(
              children: [
                if (_filter != _Filter.files)
                  TextButton.icon(
                    onPressed: _pickSort,
                    icon: const Icon(Icons.swap_vert_rounded, size: 18, color: MColors.text),
                    label: Text(sortLabel, style: MText.title.copyWith(fontSize: 13)),
                  ),
                if (_filter == _Filter.files) ...[
                  TextButton.icon(
                    onPressed: () => _open(const AddSongScreen()),
                    icon: const Icon(Icons.add_rounded, size: 18, color: MColors.lavender),
                    label: Text('Add song', style: MText.title.copyWith(fontSize: 13, color: MColors.lavender)),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final n = await lib.importLocalFiles();
                      if (context.mounted && n > 0) toast(context, 'Added $n ${n == 1 ? 'song' : 'songs'}');
                    },
                    icon: const Icon(Icons.drive_folder_upload_rounded, size: 18, color: MColors.textSecondary),
                    label: Text('Import many', style: MText.title.copyWith(fontSize: 13, color: MColors.textSecondary)),
                  ),
                ],
                const Spacer(),
                if (_filter != _Filter.files)
                  IconButton(
                    tooltip: _grid ? 'List view' : 'Grid view',
                    icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded, color: MColors.textSecondary, size: 20),
                    onPressed: () => setState(() => _grid = !_grid),
                  ),
              ],
            ),
          ),
        ),
        if (_filter == _Filter.files) ...[
          SliverList.builder(
            itemCount: lib.localTracks.length,
            itemBuilder: (_, i) => TrackTile(
              track: lib.localTracks[i],
              onTap: () => player.playTracks(lib.localTracks, index: i, from: 'On this device'),
            ),
          ),
          if (lib.localTracks.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(36),
                child: Text('Add your own songs with a name, cover and lyrics. Only you can see them.', style: MText.body, textAlign: TextAlign.center),
              ),
            ),
        ] else if (_grid)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid.builder(
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 16,
                crossAxisSpacing: 14,
                childAspectRatio: 0.74,
              ),
              itemBuilder: (_, i) => _GridTile(item: items[i]),
            ),
          )
        else
          SliverList.builder(itemCount: items.length, itemBuilder: (_, i) => _Row(item: items[i])),
        if (_filter != _Filter.files && _isSparse(lib))
          SliverToBoxAdapter(child: _Hint(filter: _filter, onCreate: _newPlaylist)),
        SliverToBoxAdapter(child: SizedBox(height: bottomInset(context))),
      ],
    );
  }

  bool _isSparse(LibraryStore lib) => switch (_filter) {
        _Filter.artists => lib.followedArtists.isEmpty,
        _Filter.stations => lib.stations.isEmpty,
        _ => lib.playlists.isEmpty && lib.savedPlaylists.isEmpty,
      };
}

class _Row extends StatelessWidget {
  const _Row({required this.item});
  final _Item item;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: item.onTap,
      onLongPress: item.onLongPress,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            SizedBox.square(dimension: 62, child: item.cover),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: MText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (item.pinned) ...[
                        const Icon(Icons.push_pin_rounded, size: 13, color: MColors.lavender),
                        const SizedBox(width: 4),
                      ],
                      Expanded(child: Text(item.subtitle, style: MText.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.item});
  final _Item item;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: item.onTap,
      onLongPress: item.onLongPress,
      child: Column(
        crossAxisAlignment: item.circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 1, child: item.cover),
          const SizedBox(height: 8),
          Text(item.title, style: MText.title.copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(
            mainAxisSize: item.circle ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (item.pinned) ...[
                const Icon(Icons.push_pin_rounded, size: 12, color: MColors.lavender),
                const SizedBox(width: 3),
              ],
              Flexible(child: Text(item.subtitle, style: MText.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.filter, required this.onCreate});

  final _Filter filter;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final text = switch (filter) {
      _Filter.artists => 'Tap Follow on an artist page to see them here.',
      _Filter.stations => 'Tap ♡ on a radio station to save it here.',
      _ => 'Create your own playlist, or save one you like with "Save to Library".',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 26, 36, 0),
      child: Column(
        children: [
          Text(text, style: MText.body, textAlign: TextAlign.center),
          if (filter == _Filter.all || filter == _Filter.playlists) ...[
            const SizedBox(height: 16),
            PillButton(label: 'Create playlist', icon: Icons.add_rounded, filled: true, onTap: onCreate),
          ],
        ],
      ),
    );
  }
}

String songs(int n) => '$n ${n == 1 ? 'song' : 'songs'}';
