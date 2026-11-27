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
  bool _flowLoading = false;

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
  List<String> get _dailyGenres {
    final day = DateTime.now().difference(DateTime(2026)).inDays;
    final list = [...AudiusApi.genres]..shuffle(math.Random(day));
    return list.take(6).toList();
  }

  Future<void> _playFlow() async {
    final player = context.read<PlayerController>();
    if (player.contextName == 'Flow' && player.hasTrack) {
      await player.togglePlay();
      return;
    }
    setState(() => _flowLoading = true);
    try {
      final lists = _mood == FlowMood.discover
          ? [await _audius.undergroundTrending(limit: 60)]
          : await Future.wait(_mood.genres.map((g) => _audius.trending(genre: g, limit: 20).catchError((_) => <Track>[])));
      final seen = <String>{};
      final merged = [for (final l in lists) ...l].where((t) => seen.add(t.id)).toList()..shuffle();
      if (merged.isEmpty) throw Exception();
      await player.playTracks(merged, from: 'Flow');
    } catch (_) {
      if (mounted) toast(context, "Couldn't start Flow. Check your connection");
    } finally {
      if (mounted) setState(() => _flowLoading = false);
    }
  }

  void _tuneFlow() {
    showGlassSheet(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Tune your Flow', style: MText.h2),
              const SizedBox(height: 6),
              const Text('Pick a mood for your endless mix', style: MText.body),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 10,
                children: [
                  for (final m in FlowMood.values)
                    GlassChip(
                      label: m.label,
                      selected: m == _mood,
                      onTap: () {
                        setSheet(() {});
                        setState(() => _mood = m);
                        final player = context.read<PlayerController>();
                        if (player.contextName == 'Flow') player.contextName = null;
                        Navigator.pop(ctx);
                        _playFlow();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
          _FlowHero(mood: _mood, loading: _flowLoading, onPlay: _playFlow, onTune: _tuneFlow),
          const _JumpBackIn(),

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

class _FlowHero extends StatelessWidget {
  const _FlowHero({required this.mood, required this.loading, required this.onPlay, required this.onTune});

  final FlowMood mood;
  final bool loading;
  final VoidCallback onPlay;
  final VoidCallback onTune;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final flowOn = player.contextName == 'Flow' && player.hasTrack;
    final playing = flowOn && player.playing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Glass(
        radius: 32,
        blur: 22,
        child: SizedBox(
          height: 360,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 4,
                height: 220,
                child: LiquidOrb(active: player.playing),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 22,
                child: Column(
                  children: [
                    const Text('Flow', style: TextStyle(fontFamily: MText.display, fontSize: 40, fontWeight: FontWeight.w300, letterSpacing: -1.5, color: MColors.lilac, height: 1)),
                    const SizedBox(height: 6),
                    Text(
                      flowOn ? player.current?.title ?? '' : 'Endless free music · ${mood.label}',
                      style: MText.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PillButton(
                          label: loading ? 'Tuning…' : (playing ? 'Pause' : (flowOn ? 'Resume' : 'Start Flow')),
                          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          filled: true,
                          onTap: loading ? null : onPlay,
                        ),
                        const SizedBox(width: 10),
                        PillButton(label: mood.label, icon: Icons.tune_rounded, onTap: onTune),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Spotify-style 2-column grid of what you played lately.
class _JumpBackIn extends StatelessWidget {
  const _JumpBackIn();

  @override
  Widget build(BuildContext context) {
    final recent = context.watch<LibraryStore>().recent.take(6).toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    final player = context.read<PlayerController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Listening',
          accentWord: 'lately',
          action: 'See all',
          onAction: () => Navigator.of(context).push(FadeRoute(CollectionScreen.recent())),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: recent.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 56,
            ),
            itemBuilder: (_, i) {
              final t = recent[i];
              final isCurrent = context.watch<PlayerController>().current == t;
              return Pressable(
                onTap: () => player.playTracks(recent, index: i, from: 'Recently played'),
                onLongPress: () => showTrackMenu(context, t),
                child: Glass(
                  radius: 12,
                  blur: 14,
                  child: Row(
                    children: [
                      Artwork(url: t.artworkUrl, size: 56, radius: 0, fit: t.isLive ? BoxFit.contain : BoxFit.cover),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MText.title.copyWith(fontSize: 13, color: isCurrent ? MColors.purple : MColors.text),
                        ),
                      ),
                      if (isCurrent) const Padding(padding: EdgeInsets.only(right: 10), child: EqualizerBars(size: 12)),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
