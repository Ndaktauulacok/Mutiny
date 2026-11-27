import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/audius_api.dart';
import '../../services/library_store.dart';
import '../../services/player_controller.dart';
import '../../services/radio_api.dart';
import '../effects.dart';
import '../glass.dart';
import '../theme.dart';
import '../widgets.dart';
import 'collection_screen.dart';

enum _ResultTab { songs, artists, playlists, radio }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _audius = AudiusApi();
  final _radio = RadioApi();
  Timer? _debounce;
  String _query = '';
  _ResultTab _tab = _ResultTab.songs;

  Future<List<Track>>? _songs;
  Future<List<Artist>>? _artists;
  Future<List<Collection>>? _playlists;
  Future<List<Track>>? _stations;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), () => _run(v));
    setState(() {});
  }

  void _run(String v, {bool save = false}) {
    final q = v.trim();
    if (save) context.read<LibraryStore>().addSearch(q);
    if (q == _query) return;
    setState(() {
      _query = q;
      if (q.isEmpty) return;
      _songs = _audius.searchTracks(q);
      _artists = _audius.searchArtists(q);
      _playlists = _audius.searchPlaylists(q);
      _stations = _radio.search(q);
    });
  }

  void _useSuggestion(String q) {
    _ctrl.text = q;
    _ctrl.selection = TextSelection.collapsed(offset: q.length);
    _run(q, save: true);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return GestureDetector(
      onTap: () => _focus.unfocus(),
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, top + 14, 20, 14),
              child: const Text('Search', style: MText.h1),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SearchBarDelegate(
              topPadding: top,
              child: _SearchField(
                controller: _ctrl,
                focus: _focus,
                onChanged: _onChanged,
                onSubmitted: (v) => _run(v, save: true),
                onClear: () {
                  _ctrl.clear();
                  _run('');
                },
              ),
            ),
          ),
          if (_query.isEmpty) ..._browse(context) else ..._results(context),
          SliverToBoxAdapter(child: SizedBox(height: bottomInset(context))),
        ],
      ),
    );
  }

  List<Widget> _browse(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    return [
      if (lib.recentSearches.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader('Recent', accentWord: 'searches')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in lib.recentSearches)
                  Pressable(
                    onTap: () => _useSuggestion(s),
                    onLongPress: () => lib.removeSearch(s),
                    child: Glass(
                      radius: 100,
                      blur: 12,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.history_rounded, size: 15, color: MColors.textTertiary),
                          const SizedBox(width: 6),
                          Text(s, style: MText.body.copyWith(color: MColors.text)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SectionHeader('Browse', accentWord: 'all')),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.builder(
          itemCount: AudiusApi.genres.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
          ),
          itemBuilder: (_, i) {
            final g = AudiusApi.genres[i];
            return Pressable(
              onTap: () => Navigator.of(context).push(FadeRoute(CollectionScreen.genre(g, index: i))),
              child: _GenreTile(genre: g, index: i),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _results(BuildContext context) {
    final player = context.read<PlayerController>();
    return [
      SliverToBoxAdapter(
        child: SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            children: [
              for (final (tab, label) in const [
                (_ResultTab.songs, 'Songs'),
                (_ResultTab.artists, 'Artists'),
                (_ResultTab.playlists, 'Playlists'),
                (_ResultTab.radio, 'Radio'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GlassChip(label: label, selected: _tab == tab, onTap: () => setState(() => _tab = tab)),
                ),
            ],
          ),
        ),
      ),
      switch (_tab) {
        _ResultTab.songs => _futureList<Track>(_songs, (tracks) => SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (_, i) => TrackTile(
                track: tracks[i],
                onTap: () {
                  context.read<LibraryStore>().addSearch(_query);
                  player.playTracks(tracks, index: i, from: 'Search: $_query');
                },
              ),
            )),
        _ResultTab.radio => _futureList<Track>(_stations, (tracks) => SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (_, i) => TrackTile(
                track: tracks[i],
                onTap: () => player.playTrack(tracks[i], from: 'Radio'),
              ),
            )),
        _ResultTab.artists => _futureList<Artist>(_artists, (artists) => SliverList.builder(
              itemCount: artists.length,
              itemBuilder: (_, i) {
                final a = artists[i];
                return Pressable(
                  scale: 0.98,
                  onTap: () {
                    context.read<LibraryStore>().addSearch(_query);
                    Navigator.of(context).push(FadeRoute(CollectionScreen.artist(artist: a)));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    child: Row(
                      children: [
                        Artwork(url: a.avatarUrl, size: 54, circle: true, icon: Icons.person_rounded),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.name, style: MText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text('Artist · ${compactNumber(a.followers)} followers', style: MText.caption),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: MColors.textTertiary),
                      ],
                    ),
                  ),
                );
              },
            )),
        _ResultTab.playlists => _futureList<Collection>(_playlists, (items) => SliverList.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final p = items[i];
                return Pressable(
                  scale: 0.98,
                  onTap: () => Navigator.of(context).push(FadeRoute(CollectionScreen.remote(p))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    child: Row(
                      children: [
                        Artwork(url: p.artworkUrl, size: 54, radius: 8, icon: Icons.queue_music_rounded),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.title, style: MText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text('Playlist · ${p.subtitle}', style: MText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            )),
      },
    ];
  }

  Widget _futureList<T>(Future<List<T>>? future, Widget Function(List<T>) builder) {
    return FutureBuilder<List<T>>(
      key: ValueKey('$_tab$_query'),
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final data = snap.data ?? const [];
        if (snap.hasError || data.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  const Icon(Icons.search_off_rounded, color: MColors.lavender, size: 36),
                  const SizedBox(height: 10),
                  Text(
                    snap.hasError ? "Couldn't search right now" : 'No results for “$_query”',
                    style: MText.body,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return builder(data);
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 16,
      blur: 24,
      strength: focus.hasFocus ? 1.6 : 1,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.search_rounded, color: MColors.lavender, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                textInputAction: TextInputAction.search,
                style: MText.title.copyWith(fontWeight: FontWeight.w500),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Songs, artists, playlists, radio',
                  hintStyle: TextStyle(color: MColors.textTertiary, fontWeight: FontWeight.w400),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(icon: const Icon(Icons.close_rounded, size: 20, color: MColors.textSecondary), onPressed: onClear),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  _SearchBarDelegate({required this.child, required this.topPadding});

  final Widget child;
  final double topPadding;

  @override
  double get minExtent => 66 + topPadding;
  @override
  double get maxExtent => 66 + topPadding;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final pinned = shrinkOffset > 0 || overlapsContent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.fromLTRB(16, topPadding + 4, 16, 12),
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: pinned ? [const Color(0xF00A0612), const Color(0x000A0612)] : [const Color(0x000A0612), const Color(0x000A0612)],
        ),
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(_SearchBarDelegate old) => old.child != child || old.topPadding != topPadding;
}

class _GenreTile extends StatelessWidget {
  const _GenreTile({required this.genre, required this.index});

  final String genre;
  final int index;

  @override
  Widget build(BuildContext context) {
    final color = genreColor(genre);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: 0.9, child: HalftoneCover(index: index * 3 + 1, color: color, label: '')),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.55), Colors.transparent],
              ),
              border: Border.all(color: MColors.glassBorder, width: 0.8),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              genre,
              style: const TextStyle(fontFamily: MText.display, fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
