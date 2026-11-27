import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/library_store.dart';
import '../../services/lyrics_api.dart';
import '../../services/player_controller.dart';
import '../effects.dart';
import '../glass.dart';
import '../theme.dart';

void openLyrics(BuildContext context, Track track) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => Material(type: MaterialType.transparency, child: LyricsView(track: track)),
    transitionsBuilder: (_, anim, _, child) {
      final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: SlideTransition(position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(c), child: child),
      );
    },
  ));
}

/// Full-screen lyrics. Synced lyrics highlight and scroll with the song;
/// tap a line to jump there.
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.track});
  final Track track;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late final String? _own = context.read<LibraryStore>().lyricsFor(widget.track);
  late final Future<Lyrics?> _future = _own != null
      ? Future.value(Lyrics(synced: LyricsApi.parseLrc(_own), plain: _own.replaceAll(RegExp(r'\[\d+:\d+(?:\.\d+)?\]'), '').trim()))
      : LyricsApi().find(widget.track);
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _active = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int _indexAt(List<LyricLine> lines, Duration pos) {
    var idx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= pos + const Duration(milliseconds: 250)) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _follow(int idx) {
    if (idx == _active) return;
    _active = idx;
    final ctx = _keys[idx]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.35, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final pad = MediaQuery.paddingOf(context);
    final t = widget.track;
    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<Color?>(
          future: accentFromImage(t.artworkUrl),
          builder: (_, snap) => AuroraBackground(accent: snap.data, energy: 0.6),
        ),
        const ColoredBox(color: Color(0x660A0612)),
        Padding(
          padding: EdgeInsets.only(top: pad.top + 6),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    GlassIconButton(icon: Icons.keyboard_arrow_down_rounded, iconSize: 26, onTap: () => Navigator.maybePop(context)),
                    const SizedBox(width: 12),
                    Artwork(url: t.artworkUrl, size: 44, radius: 8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title, style: MText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(t.artist, style: MText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<Lyrics?>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    final lyrics = snap.data;
                    if (lyrics == null || lyrics.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lyrics_outlined, color: MColors.lavender, size: 40),
                              SizedBox(height: 14),
                              Text(
                                "No lyrics for this song yet.\nLyrics come from LRCLIB, which mostly has well-known songs. For your own songs, add lyrics with Edit song details.",
                                style: MText.body,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (!lyrics.isSynced) {
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(26, 30, 26, pad.bottom + 60),
                        child: Text(
                          lyrics.plain,
                          style: const TextStyle(fontSize: 22, height: 1.6, fontWeight: FontWeight.w700, color: MColors.text),
                        ),
                      );
                    }
                    final lines = lyrics.synced;
                    return StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (context, pos) {
                        final playingThis = player.current == t;
                        final idx = playingThis ? _indexAt(lines, pos.data ?? Duration.zero) : -1;
                        WidgetsBinding.instance.addPostFrameCallback((_) => _follow(idx));
                        return ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(26, 40, 26, MediaQuery.sizeOf(context).height * 0.5),
                          itemCount: lines.length,
                          itemBuilder: (_, i) {
                            final line = lines[i];
                            final active = i == idx;
                            final past = i < idx;
                            return GestureDetector(
                              key: _keys.putIfAbsent(i, GlobalKey.new),
                              behavior: HitTestBehavior.opaque,
                              onTap: playingThis ? () => player.seek(line.time) : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 260),
                                  style: TextStyle(
                                    fontSize: active ? 28 : 24,
                                    height: 1.25,
                                    fontWeight: FontWeight.w800,
                                    color: active
                                        ? MColors.lilac
                                        : past
                                            ? const Color(0x80E9DDFF)
                                            : const Color(0x59FFFFFF),
                                  ),
                                  child: Text(line.text.isEmpty ? '♪' : line.text),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: pad.bottom + 10,
          left: 0,
          right: 0,
          child: Text(_own != null ? 'Your lyrics' : 'Lyrics by LRCLIB', style: MText.caption, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
