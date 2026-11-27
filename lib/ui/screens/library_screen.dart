import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../services/library_store.dart';
import '../../services/player_controller.dart';
import '../glass.dart';
import '../theme.dart';
import '../widgets.dart';
import 'collection_screen.dart';

enum _Filter { all, playlists, stations, files }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _Filter _filter = _Filter.all;

  Future<void> _newPlaylist() async {
    final name = await askText(context, title: 'Name your playlist', action: 'Create');
    if (name == null || !mounted) return;
    final p = context.read<LibraryStore>().createPlaylist(name);
    Navigator.of(context).push(FadeRoute(CollectionScreen.userPlaylist(p)));
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final top = MediaQuery.paddingOf(context).top;

    final rows = <Widget>[
      if (_filter == _Filter.all || _filter == _Filter.playlists) ...[
        _LibraryRow(
          cover: gradientCover(Icons.favorite_rounded),
          title: 'Liked Songs',
          subtitle: 'Playlist · ${songs(lib.liked.length)}',
          pinned: true,
          onTap: () => _open(CollectionScreen.liked()),
        ),
      ],
      if (_filter == _Filter.all || _filter == _Filter.files)
        _LibraryRow(
          cover: gradientCover(Icons.folder_rounded, colors: const [Color(0xFF312E81), Color(0xFF7C3AED)]),
          title: 'On this device',
          subtitle: '${lib.localTracks.length} ${lib.localTracks.length == 1 ? 'file' : 'files'}',
          pinned: true,
          onTap: () => _open(CollectionScreen.local()),
        ),
      if (_filter == _Filter.all)
        _LibraryRow(
          cover: gradientCover(Icons.history_rounded, colors: const [Color(0xFF581C87), Color(0xFFDB2777)]),
          title: 'Recently played',
          subtitle: songs(lib.recent.length),
          onTap: () => _open(CollectionScreen.recent()),
        ),
      if (_filter == _Filter.all || _filter == _Filter.playlists)
        for (final p in lib.playlists)
          _LibraryRow(
            cover: p.coverUrl == null
                ? gradientCover(Icons.queue_music_rounded, colors: const [Color(0xFF2E1065), Color(0xFF6D28D9)])
                : Artwork(url: p.coverUrl, radius: 10),
            title: p.name,
            subtitle: 'Playlist · ${songs(p.tracks.length)}',
            onTap: () => _open(CollectionScreen.userPlaylist(p)),
          ),
      if (_filter == _Filter.all || _filter == _Filter.stations)
        for (final s in lib.stations)
          _LibraryRow(
            cover: Artwork(url: s.artworkUrl, radius: 10, icon: Icons.radio_rounded, fit: BoxFit.contain),
            title: s.title,
            subtitle: 'Radio station',
            onTap: () => player.playTrack(s, from: 'Radio'),
            onLongPress: () => showTrackMenu(context, s),
          ),
      if (_filter == _Filter.files)
        for (final (i, t) in lib.localTracks.indexed)
          TrackTile(track: t, onTap: () => player.playTracks(lib.localTracks, index: i, from: 'On this device')),
    ];

    return ListView(
      padding: EdgeInsets.only(top: top + 14, bottom: bottomInset(context)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
          child: Row(
            children: [
              const Expanded(child: Text('Your Library', style: MText.h1)),
              GlassIconButton(icon: Icons.add_rounded, onTap: _newPlaylist, tooltip: 'New playlist'),
            ],
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            children: [
              for (final (f, label) in const [
                (_Filter.all, 'All'),
                (_Filter.playlists, 'Playlists'),
                (_Filter.stations, 'Stations'),
                (_Filter.files, 'Files'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GlassChip(label: label, selected: _filter == f, onTap: () => setState(() => _filter = f)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (_filter == _Filter.files)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: PillButton(
                label: 'Import files',
                icon: Icons.add_rounded,
                compact: true,
                onTap: () async {
                  final n = await lib.importLocalFiles();
                  if (context.mounted && n > 0) toast(context, 'Added $n ${n == 1 ? 'song' : 'songs'}');
                },
              ),
            ),
          ),
        ...rows,
        if (_filter == _Filter.playlists && lib.playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.all(30),
            child: Center(child: PillButton(label: 'Create a playlist', icon: Icons.add_rounded, filled: true, onTap: _newPlaylist)),
          ),
        if (_filter == _Filter.stations && lib.stations.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Text('Tap ♡ on a radio station to save it here.', style: MText.body, textAlign: TextAlign.center),
          ),
      ],
    );
  }

  void _open(Widget page) => Navigator.of(context).push(FadeRoute(page));
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.cover,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.pinned = false,
  });

  final Widget cover;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            SizedBox.square(dimension: 62, child: cover),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: MText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (pinned) ...[
                        const Icon(Icons.push_pin_rounded, size: 13, color: MColors.lavender),
                        const SizedBox(width: 4),
                      ],
                      Expanded(child: Text(subtitle, style: MText.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
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

String songs(int n) => '$n ${n == 1 ? 'song' : 'songs'}';
