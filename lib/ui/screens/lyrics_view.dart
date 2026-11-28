import 'dart:async';
import 'dart:math' as math;

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

/// Full-screen lyrics in the style of Apple Music: the line being sung is
/// bright and large, the others are dimmed, and the page glides to keep the
/// current line in place. It opens at the right line mid-song, follows the
/// player to the next song, and pauses following while you scroll yourself.
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.track});
  final Track track;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late Track _track = widget.track;
  String? _own;
  late Future<Lyrics?> _future;
  List<LyricLine> _lines = const [];

  final _scroll = ScrollController();
  final _keys = <GlobalKey>[];
  late final PlayerController _player = context.read<PlayerController>();
  Timer? _clock;

  /// Line being sung (-1: before the first line).
  int _active = -1;
  bool _placed = false; // jumped to the current line after opening
  DateTime? _userScrolledAt;
  Timer? _resume;

  @override
  void initState() {
    super.initState();
    _load(_player.current ?? widget.track);
    _player.addListener(_onPlayer);
    // Checks the exact position 20 times a second so lines change right on
    // time; only rebuilds when the line changes.
    _clock = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _resume?.cancel();
    _player.removeListener(_onPlayer);
    _scroll.dispose();
    super.dispose();
  }

  void _load(Track t) {
    _track = t;
    _own = context.read<LibraryStore>().lyricsFor(t);
    final own = _own;
    _future = own != null
        ? Future.value(Lyrics(synced: LyricsApi.parseLrc(own), plain: own.replaceAll(RegExp(r'\[\d+:\d+(?:\.\d+)?\]'), '').trim()))
        : LyricsApi().find(t);
    _lines = const [];
    _keys.clear();
    _active = -1;
    _placed = false;
    _userScrolledAt = null;
    _future.then((l) {
      if (!mounted || t != _track) return;
      setState(() {
        _lines = l?.synced ?? const [];
        _keys
          ..clear()
          ..addAll(List.generate(_lines.length, (_) => GlobalKey()));
      });
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// The next song started: show its lyrics.
  void _onPlayer() {
    final c = _player.current;
    if (c != null && c != _track && mounted) setState(() => _load(c));
  }

  bool get _following => _userScrolledAt == null;

  void _tick() {
    if (_lines.isEmpty || _player.current != _track) return;
    final pos = _player.player.position + const Duration(milliseconds: 200); // sing slightly ahead, like Apple Music
    var idx = -1;
    // Lines are sorted: binary search for the last line that has started.
    var lo = 0, hi = _lines.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_lines[mid].time <= pos) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (idx != _active) {
      setState(() => _active = idx);
      if (_following) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive(animate: _placed));
    } else if (!_placed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive(animate: false));
    }
  }

  void _scrollToActive({required bool animate}) {
    if (!mounted || !_scroll.hasClients) return;
    final i = _active < 0 ? 0 : _active;
    if (i >= _keys.length) return;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    _placed = true;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.3,
      duration: animate ? const Duration(milliseconds: 700) : Duration.zero,
      curve: const Cubic(0.2, 0.9, 0.25, 1), // soft spring-like glide
    );
  }

  /// The user scrolls: stop following for a moment, then glide back.
  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _resume?.cancel();
      setState(() => _userScrolledAt = DateTime.now());
    } else if (n is ScrollEndNotification && _userScrolledAt != null) {
      _resume?.cancel();
      _resume = Timer(const Duration(seconds: 3), _backToNow);
    }
    return false;
  }

  void _backToNow() {
    if (!mounted) return;
    _resume?.cancel();
    setState(() => _userScrolledAt = null);
    _scrollToActive(animate: true);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final t = _track;
    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<Color?>(
          key: ValueKey(t.key),
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
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Artwork(key: ValueKey(t.key), url: t.artworkUrl, size: 44, radius: 8),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Column(
                          key: ValueKey(t.key),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title, style: MText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(t.artist, style: MText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: KeyedSubtree(key: ValueKey(t.key), child: _body(pad))),
            ],
          ),
        ),
        if (!_following && _lines.isNotEmpty)
          Positioned(
            bottom: pad.bottom + 40,
            left: 0,
            right: 0,
            child: Center(
              child: PillButton(label: 'Back to now', icon: Icons.my_location_rounded, compact: true, onTap: _backToNow),
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

  Widget _body(EdgeInsets pad) => FutureBuilder<Lyrics?>(
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
              child: Text(lyrics.plain, style: const TextStyle(fontSize: 22, height: 1.6, fontWeight: FontWeight.w700, color: MColors.text)),
            );
          }
          if (_keys.length != _lines.length) return const SizedBox.shrink(); // keys arrive next frame
          final height = MediaQuery.sizeOf(context).height;
          // Every line is built (a song has ~60), so the view can jump to any
          // line straight away, even when opened in the middle of a song.
          return NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ShaderMask(
              // Lines fade softly at the top and bottom edges.
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                stops: [0, 0.08, 0.82, 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(26, height * 0.12, 26, height * 0.6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Before the first line: a gentle "…" while the intro plays.
                    if (_lines.first.time > const Duration(seconds: 3))
                      _Interlude(active: _active < 0 && _player.current == _track),
                    for (var i = 0; i < _lines.length; i++)
                      _LyricLineView(
                        key: _keys[i],
                        text: _lines[i].text,
                        distance: _active < 0 ? i + 1 : (i - _active),
                        onTap: () {
                          _player.seek(_lines[i].time);
                          _backToNow();
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

/// One lyric line. [distance] is how far it is from the line being sung
/// (0 = being sung, negative = already sung).
class _LyricLineView extends StatelessWidget {
  const _LyricLineView({super.key, required this.text, required this.distance, required this.onTap});

  final String text;
  final int distance;
  final VoidCallback onTap;

  static const _curve = Cubic(0.2, 0.9, 0.25, 1);

  @override
  Widget build(BuildContext context) {
    final active = distance == 0;
    final far = distance.abs();
    // Apple Music style: one bright line, the rest dimmed a little more the
    // further away they are.
    final opacity = active ? 1.0 : math.max(0.18, 0.42 - far * 0.04);
    if (text.trim().isEmpty) return _Interlude(active: active);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: AnimatedScale(
          scale: active ? 1.0 : 0.94,
          alignment: Alignment.centerLeft,
          duration: const Duration(milliseconds: 600),
          curve: _curve,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: 30,
                height: 1.22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: Colors.white,
                shadows: active ? const [Shadow(color: Color(0x66C9A6FF), blurRadius: 22)] : const [],
              ),
              child: Text(text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Instrumental gap: three dots that breathe while it plays.
class _Interlude extends StatefulWidget {
  const _Interlude({required this.active});
  final bool active;

  @override
  State<_Interlude> createState() => _InterludeState();
}

class _InterludeState extends State<_Interlude> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(_Interlude old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: AnimatedOpacity(
        opacity: widget.active ? 1 : 0.3,
        duration: const Duration(milliseconds: 400),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Transform.scale(
                    scale: widget.active ? 0.7 + 0.5 * (0.5 + 0.5 * math.sin((_c.value - i * 0.18) * 2 * math.pi)) : 0.8,
                    child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
