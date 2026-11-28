import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/audius_api.dart';
import '../../services/player_controller.dart';
import '../../services/library_store.dart';
import '../../services/radio_api.dart';
import '../effects.dart';
import '../glass.dart';
import '../theme.dart';
import '../widgets.dart';
import 'collection_screen.dart';
import 'now_playing.dart';
import 'profile_screen.dart';

/// Moods the user can tune Flow (the endless mix) to.
enum FlowMood {
  everything('Everything', ['Electronic', 'Hip-Hop/Rap', 'Pop', 'Lo-Fi', 'R&B/Soul', 'Alternative']),
  chill('Chill', ['Lo-Fi', 'Ambient', 'Acoustic', 'R&B/Soul']),
  energy('Energy', ['Electronic', 'House', 'Techno', 'Dubstep']),
  hiphop('Hip-Hop', ['Hip-Hop/Rap', 'Trap', 'R&B/Soul']),
  discover('Discover', []);

  const FlowMood(this.label, this.genres);
  final String label;
  final List<String> genres;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _audius = AudiusApi();
  final _radio = RadioApi();

  late Future<List<Track>> _trending;
  late Future<List<Collection>> _playlists;
  late Future<List<Track>> _underground;
  late Future<List<Track>> _stations;
  FlowMood _mood = FlowMood.everything;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _trending = _audius.trending(limit: 20);
    _playlists = _audius.trendingPlaylists();
    _underground = _audius.undergroundTrending(limit: 15);
    _stations = _radio.topStations(countryCode: 'MY', limit: 15);
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_trending, _playlists].map((f) => f.catchError((_) => <Never>[])));
  }

  /// Six genre mixes that rotate every day.
  late final List<String> _dailyGenres = () {
    final day = DateTime.now().difference(DateTime(2026)).inDays;
    final list = [...AudiusApi.genres]..shuffle(math.Random(day));
    return list.take(6).toList();
  }();

  Future<void> _playFlow() async {
    final player = context.read<PlayerController>();
    if (player.contextName == 'Flow' && player.hasTrack) {
      await player.togglePlay();
      return;
    }
    try {
      final lists = _mood == FlowMood.discover
          ? [await _audius.undergroundTrending(limit: 60)]
          : await Future.wait(_mood.genres.map((g) => _audius.trending(genre: g, limit: 20).catchError((_) => <Track>[])));
      final seen = <String>{};
      final merged = [for (final l in lists) ...l].where((t) => seen.add(t.id)).toList()..shuffle();
      if (merged.isEmpty) throw Exception();
      if (!mounted) return;
      context.read<LibraryStore>().markPlayedFrom(
            PlayContext(type: PlayContextType.flow, id: 'flow', title: 'Flow', subtitle: _mood.label, data: {'mood': _mood.name}),
          );
      await player.playTracks(merged, from: 'Flow');
    } catch (_) {
      if (mounted) toast(context, "Couldn't start Flow. Check your connection");
    }
  }

  void _flowFromRecents(String? mood) {
    final m = FlowMood.values.where((f) => f.name == mood).firstOrNull;
    if (m != null && m != _mood) {
      setState(() => _mood = m);
      final player = context.read<PlayerController>();
      if (player.contextName == 'Flow') player.contextName = null;
    }
    _playFlow();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final top = MediaQuery.paddingOf(context).top;
    return RefreshIndicator(
      onRefresh: _refresh,
      color: MColors.lavender,
      backgroundColor: MColors.bgRaised,
      edgeOffset: top,
      child: ListView(
        padding: EdgeInsets.only(top: top + 8, bottom: bottomInset(context)),
        children: [
          _TopBar(onProfile: () => Navigator.of(context).push(FadeRoute(const ProfileScreen()))),
          const _NowHero(),
          _JumpBackIn(onFlow: _flowFromRecents),

          const SectionHeader('Daily', accentWord: 'mixes'),
          HorizontalList(
            height: 205,
            itemCount: _dailyGenres.length,
            itemBuilder: (_, i) {
              final g = _dailyGenres[i];
              final cover = LiquidCover(index: i + DateTime.now().day, color: genreColor(g), label: '0${i + 1}');
              return CoverCard(
                title: 'Daily Mix ${i + 1}',
                subtitle: g,
                cover: cover,
                onTap: () => Navigator.of(context).push(FadeRoute(CollectionScreen.mix(
                  title: 'Daily Mix ${i + 1}',
                  subtitle: '$g · fresh today',
                  cover: LiquidCover(index: i + DateTime.now().day, color: genreColor(g), label: '0${i + 1}'),
                  load: () async => (await _audius.trending(genre: g, limit: 40))..shuffle(math.Random(DateTime.now().day)),
                  playContext: PlayContext(type: PlayContextType.mix, id: g, title: 'Daily Mix ${i + 1}', subtitle: g, data: {'genre': g}),
                ))),
              );
            },
          ),

          const SectionHeader('Trending', accentWord: 'now'),
          AsyncSection<List<Track>>(
            future: _trending,
            onRetry: () => setState(() => _trending = _audius.trending(limit: 20)),
            builder: (tracks) => HorizontalList(
              itemCount: tracks.length,
              itemBuilder: (_, i) => CoverCard(
                title: tracks[i].title,
                subtitle: tracks[i].artist,
                artworkUrl: tracks[i].artworkUrl,
                onTap: () => player.playTracks(tracks, index: i, from: 'Trending now'),
                onLongPress: () => showTrackMenu(context, tracks[i]),
              ),
            ),
          ),

          const SectionHeader('Hot', accentWord: 'playlists'),
          AsyncSection<List<Collection>>(
            future: _playlists,
            onRetry: () => setState(() => _playlists = _audius.trendingPlaylists()),
            builder: (items) => HorizontalList(
              itemCount: items.length,
              itemBuilder: (_, i) => CoverCard(
                title: items[i].title,
                subtitle: items[i].subtitle,
                artworkUrl: items[i].artworkUrl,
                icon: Icons.queue_music_rounded,
                onTap: () => Navigator.of(context).push(FadeRoute(CollectionScreen.remote(items[i]))),
                onLongPress: () {
                  final saved = context.read<LibraryStore>().toggleSavePlaylist(items[i]);
                  toast(context, saved ? 'Saved to your Library' : 'Removed from your Library');
                },
              ),
            ),
          ),

          const SectionHeader('Underground', accentWord: 'gems'),
          AsyncSection<List<Track>>(
            future: _underground,
            onRetry: () => setState(() => _underground = _audius.undergroundTrending(limit: 15)),
            builder: (tracks) => HorizontalList(
              itemCount: tracks.length,
              itemBuilder: (_, i) => CoverCard(
                title: tracks[i].title,
                subtitle: tracks[i].artist,
                artworkUrl: tracks[i].artworkUrl,
                onTap: () => player.playTracks(tracks, index: i, from: 'Underground gems'),
                onLongPress: () => showTrackMenu(context, tracks[i]),
              ),
            ),
          ),

          const SectionHeader('Radio in', accentWord: 'Malaysia'),
          AsyncSection<List<Track>>(
            future: _stations,
            onRetry: () => setState(() => _stations = _radio.topStations(countryCode: 'MY', limit: 15)),
            builder: (stations) => HorizontalList(
              height: 180,
              itemCount: stations.length,
              itemBuilder: (_, i) => CoverCard(
                size: 120,
                title: stations[i].title,
                subtitle: 'Live radio',
                artworkUrl: stations[i].artworkUrl,
                icon: Icons.radio_rounded,
                contain: true,
                onTap: () => player.playTrack(stations[i], from: 'Radio'),
                onLongPress: () => showTrackMenu(context, stations[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onProfile});

  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? 'Late night'
        : hour < 12
            ? 'Good morning'
            : hour < 18
                ? 'Good afternoon'
                : 'Good evening';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
      child: Row(
        children: [
          const MutinyMark(size: 30),
          const SizedBox(width: 8),
          const Text('Mutiny', style: TextStyle(fontFamily: MText.display, fontSize: 19, fontWeight: FontWeight.w700, color: MColors.lilac)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$greeting, ${context.watch<LibraryStore>().profile.name.split(' ').first}',
              style: MText.caption,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Pressable(
            onTap: onProfile,
            scale: 0.9,
            child: ProfileAvatar(profile: context.watch<LibraryStore>().profile, size: 40),
          ),
        ],
      ),
    );
  }
}

/// The app's logo: a flag made of sound waves.
class MutinyMark extends StatelessWidget {
  const MutinyMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/brand/mark.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      );
}

/// The big card on Home: Mutiny's liquid animation with the song that is
/// playing right now. Tap it to open the player.
class _NowHero extends StatelessWidget {
  const _NowHero();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final track = player.current;
    final playing = player.playing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Pressable(
        scale: 0.98,
        onTap: track == null ? null : () => openNowPlaying(context),
        child: Glass(
          radius: 32,
          blur: 22,
          child: SizedBox(
            height: 340,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 4,
                  height: 220,
                  child: FutureBuilder<Color?>(
                    future: accentFromImage(track?.artworkUrl),
                    builder: (_, snap) => LiquidOrb(active: playing, color: snap.data ?? MColors.purple),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 26,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: track == null
                        ? const Column(
                            key: ValueKey('idle'),
                            children: [
                              Text('Nothing playing', style: TextStyle(fontFamily: MText.display, fontSize: 26, fontWeight: FontWeight.w300, color: MColors.lilac, height: 1.1)),
                              SizedBox(height: 8),
                              Text('Pick a song or playlist to start', style: MText.body),
                            ],
                          )
                        : Column(
                            key: ValueKey(track.key),
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (playing) const Padding(padding: EdgeInsets.only(right: 8), child: EqualizerBars(size: 12)),
                                  Text(
                                    playing ? 'NOW PLAYING' : 'PAUSED',
                                    style: MText.label.copyWith(color: playing ? MColors.purple : MColors.textSecondary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontFamily: MText.display, fontSize: 28, fontWeight: FontWeight.w400, letterSpacing: -0.8, color: MColors.lilac, height: 1.1),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                [track.artist, if (player.contextName != null) player.contextName!].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: MText.body,
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Spotify-style 2-column grid of the playlists, artists, mixes and
/// stations you played from lately (not single songs). Topped up with your
/// own playlists so it is never empty.
class _JumpBackIn extends StatelessWidget {
  const _JumpBackIn({required this.onFlow});

  final void Function(String? mood) onFlow;

  List<PlayContext> _items(LibraryStore lib) {
    final out = <PlayContext>[];
    final seen = <String>{};
    void add(PlayContext c) {
      if (out.length < 6 && seen.add(c.key)) out.add(c);
    }

    for (final c in lib.recentContexts) {
      if (c.type == PlayContextType.playlist && lib.playlistById(c.id) == null) continue; // deleted
      add(c);
    }
    if (lib.liked.isNotEmpty) add(CollectionScreen.liked().playContext!);
    final mine = [...lib.playlists]..sort((a, b) => b.updated.compareTo(a.updated));
    for (final p in mine) {
      add(PlayContext(type: PlayContextType.playlist, id: p.id, title: p.name, subtitle: 'Playlist'));
    }
    if (lib.localTracks.isNotEmpty) add(CollectionScreen.mySongsContext());
    for (final c in lib.savedPlaylists) {
      add(CollectionScreen.remote(c).playContext!);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final items = _items(lib);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Listening', accentWord: 'lately'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 56,
            ),
            itemBuilder: (_, i) => _ContextTile(
              item: items[i],
              inRecents: lib.recentContexts.contains(items[i]),
              onFlow: onFlow,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContextTile extends StatelessWidget {
  const _ContextTile({required this.item, required this.inRecents, required this.onFlow});

  final PlayContext item;
  final bool inRecents;
  final void Function(String? mood) onFlow;

  void _open(BuildContext context) {
    final lib = context.read<LibraryStore>();
    final nav = Navigator.of(context);
    final d = item.data;
    switch (item.type) {
      case PlayContextType.playlist:
        final p = lib.playlistById(item.id);
        if (p != null) nav.push(FadeRoute(CollectionScreen.userPlaylist(p)));
      case PlayContextType.liked:
        nav.push(FadeRoute(CollectionScreen.liked()));
      case PlayContextType.mySongs:
        nav.push(FadeRoute(CollectionScreen.local()));
      case PlayContextType.remote:
        nav.push(FadeRoute(CollectionScreen.remote(Collection.fromJson(d))));
      case PlayContextType.artist:
        nav.push(FadeRoute(CollectionScreen.artist(artist: Artist.fromJson(d))));
      case PlayContextType.genre:
        nav.push(FadeRoute(CollectionScreen.genre(item.id, index: d['index'] as int?)));
      case PlayContextType.mix:
        final g = item.id;
        nav.push(FadeRoute(CollectionScreen.mix(
          title: item.title,
          subtitle: 'Mix · $g',
          cover: LiquidCover(index: g.hashCode.abs() % 50, color: genreColor(g), label: g),
          load: () async => (await AudiusApi().trending(genre: g, limit: 40))..shuffle(),
          playContext: item,
        )));
      case PlayContextType.flow:
        onFlow(d['mood'] as String?);
      case PlayContextType.station:
        context.read<PlayerController>().playTrack(Track.fromJson(d), from: 'Radio');
    }
  }

  /// Whether music is currently playing from this item.
  bool _isPlaying(PlayerController player) {
    if (!player.hasTrack) return false;
    if (item.type == PlayContextType.station) return player.current?.id == item.id;
    return player.contextName == item.title;
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final current = _isPlaying(player);
    return Pressable(
      onTap: () => _open(context),
      onLongPress: inRecents
          ? () {
              context.read<LibraryStore>().removeRecentContext(item);
              toast(context, 'Removed from Listening lately');
            }
          : null,
      child: Glass(
        radius: 10,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
              child: SizedBox(width: 56, height: 56, child: _ContextCover(item: item)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.type == PlayContextType.playlist
                    ? context.select<LibraryStore, String>((l) => l.playlistById(item.id)?.name ?? item.title)
                    : item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MText.title.copyWith(fontSize: 13, color: current ? MColors.purple : MColors.text),
              ),
            ),
            if (current) EqualizerBars(size: 12, playing: player.playing),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _ContextCover extends StatelessWidget {
  const _ContextCover({required this.item});
  final PlayContext item;

  static Widget _gradient(IconData icon, List<Color> colors) => DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: colors)),
        child: Center(child: Icon(icon, color: Colors.white, size: 22)),
      );

  @override
  Widget build(BuildContext context) => switch (item.type) {
        PlayContextType.playlist => switch (context.select<LibraryStore, UserPlaylist?>((l) => l.playlistById(item.id))) {
            final p? => PlaylistCover(playlist: p, radius: 0),
            null => _gradient(Icons.queue_music_rounded, const [Color(0xFF2B1155), Color(0xFF8A3FFC)]),
          },
        PlayContextType.liked => _gradient(Icons.favorite_rounded, const [Color(0xFF4C1D95), Color(0xFFC4B5FD)]),
        PlayContextType.mySongs => _gradient(Icons.library_music_rounded, const [Color(0xFF312E81), Color(0xFF7C3AED)]),
        PlayContextType.flow => _gradient(Icons.waves_rounded, const [Color(0xFF2B1155), Color(0xFFA259FF)]),
        PlayContextType.genre || PlayContextType.mix => _gradient(Icons.graphic_eq_rounded, [Color.lerp(genreColor(item.id), Colors.black, 0.5)!, genreColor(item.id)]),
        PlayContextType.station => Artwork(url: item.artworkUrl, radius: 0, size: 56, icon: Icons.radio_rounded, fit: BoxFit.contain),
        PlayContextType.artist => Artwork(url: item.artworkUrl, radius: 0, size: 56, icon: Icons.person_rounded),
        PlayContextType.remote => Artwork(url: item.artworkUrl, radius: 0, size: 56, icon: Icons.queue_music_rounded),
      };
}
