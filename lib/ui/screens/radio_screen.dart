import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/library_store.dart';
import '../../services/player_controller.dart';
import '../../services/radio_api.dart';
import '../effects.dart';
import '../glass.dart';
import '../theme.dart';
import '../widgets.dart';

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final _api = RadioApi();
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _country = 'MY';
  String _query = '';
  late Future<List<Track>> _future = _api.topStations(countryCode: _country);

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _query.isNotEmpty ? _api.search(_query) : _api.topStations(countryCode: _country);
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final player = context.watch<PlayerController>();
    final saved = context.watch<LibraryStore>().stations;
    final live = player.current?.isLive == true ? player.current : null;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, top + 14, 20, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Radio', style: MText.h1),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('${saved.length} saved', style: MText.caption),
                ),
              ],
            ),
          ),
        ),
        if (live != null) SliverToBoxAdapter(child: _OnAir(station: live, playing: player.playing)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Glass(
              radius: 16,
              blur: 20,
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    const Icon(Icons.radio_rounded, color: MColors.lavender, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        textInputAction: TextInputAction.search,
                        style: MText.title.copyWith(fontWeight: FontWeight.w500),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: 'Find a station (e.g. Hot FM, jazz)',
                          hintStyle: TextStyle(color: MColors.textTertiary, fontWeight: FontWeight.w400),
                        ),
                        onChanged: (v) {
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 450), () {
                            _query = v.trim();
                            _reload();
                          });
                        },
                      ),
                    ),
                    if (_ctrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20, color: MColors.textSecondary),
                        onPressed: () {
                          _ctrl.clear();
                          _query = '';
                          _reload();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_query.isEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                children: [
                  for (final (code, label) in RadioApi.countries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GlassChip(
                        label: label,
                        selected: code == _country,
                        onTap: () {
                          _country = code;
                          _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (saved.isNotEmpty && _query.isEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Your', accentWord: 'stations')),
          SliverToBoxAdapter(
            child: HorizontalList(
              height: 160,
              itemCount: saved.length,
              itemBuilder: (_, i) => CoverCard(
                size: 104,
                title: saved[i].title,
                subtitle: 'Saved',
                artworkUrl: saved[i].artworkUrl,
                icon: Icons.radio_rounded,
                contain: true,
                onTap: () => player.playTrack(saved[i], from: 'Radio'),
                onLongPress: () => showTrackMenu(context, saved[i]),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: SectionHeader(
            _query.isNotEmpty ? 'Results' : 'Popular',
            accentWord: _query.isNotEmpty ? null : 'now',
          ),
        ),
        FutureBuilder<List<Track>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            final stations = snap.data ?? const <Track>[];
            if (snap.hasError || stations.isEmpty) {
              return SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: PillButton(
                      label: snap.hasError ? "Couldn't load · Retry" : 'No stations found',
                      icon: snap.hasError ? Icons.refresh_rounded : null,
                      compact: true,
                      onTap: snap.hasError ? _reload : null,
                    ),
                  ),
                ),
              );
            }
            return SliverList.builder(
              itemCount: stations.length,
              itemBuilder: (_, i) => TrackTile(
                track: stations[i],
                onTap: () => player.playTrack(stations[i], from: 'Radio'),
              ),
            );
          },
        ),
        SliverToBoxAdapter(child: SizedBox(height: bottomInset(context))),
      ],
    );
  }
}

/// "On air" card with a small wave orb for the station that's playing.
class _OnAir extends StatelessWidget {
  const _OnAir({required this.station, required this.playing});

  final Track station;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final saved = lib.isLiked(station);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Glass(
        radius: 22,
        child: SizedBox(
          height: 110,
          child: Stack(
            children: [
              Positioned(right: -30, top: -10, bottom: -10, width: 200, child: LiquidOrb(active: playing)),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Artwork(url: station.artworkUrl, size: 70, radius: 14, icon: Icons.radio_rounded, fit: BoxFit.contain),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('ON AIR', style: MText.label),
                          const SizedBox(height: 4),
                          Text(station.title, style: MText.title.copyWith(fontSize: 17), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(station.artist, style: MText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    GlassIconButton(
                      icon: saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: saved ? MColors.lavender : MColors.text,
                      onTap: () => lib.toggleLike(station),
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
