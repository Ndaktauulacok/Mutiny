import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/cloud_sync.dart';
import '../services/library_store.dart';
import '../services/player_controller.dart';
import 'effects.dart';
import 'glass.dart';
import 'screens/connect_sheet.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing.dart';
import 'screens/radio_screen.dart';
import 'screens/search_screen.dart';
import 'screens/update_sheet.dart';
import 'theme.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _navKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());
  final _pages = const [HomeScreen(), SearchScreen(), RadioScreen(), LibraryScreen()];
  Color? _accent;
  String? _accentFor;
  late final AppLifecycleListener _lifecycle;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    rootTabNavigator = () => _navKeys[_tab].currentState;
    final player = context.read<PlayerController>();
    player.onMessage = (m) {
      if (mounted) toast(context, m);
    };
    player.addListener(_updateAccent);
    HardwareKeyboard.instance.addHandler(_onKey);
    // Catch up on changes made on other devices while the app was closed.
    _lifecycle = AppLifecycleListener(onResume: () {
      context.read<CloudSync>().onResume();
      autoCheckForUpdate(context);
    });
    // Look for a newer Mutiny on GitHub a few seconds after start-up, then
    // every half hour (a computer may keep Mutiny open all day).
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) autoCheckForUpdate(context);
    });
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (mounted) autoCheckForUpdate(context);
    });
  }

  /// Keyboard shortcuts on computers: Space plays/pauses (not while typing),
  /// media keys work too.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final player = context.read<PlayerController>();
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.mediaPlay || key == LogicalKeyboardKey.mediaPause) {
      if (player.hasTrack) player.togglePlay();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      player.next();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      player.previous();
      return true;
    }
    if (key != LogicalKeyboardKey.space || !player.hasTrack) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    final typing = focus != null && (focus.widget is EditableText || focus.findAncestorWidgetOfExactType<EditableText>() != null);
    if (typing) return false;
    player.togglePlay();
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _updateTimer?.cancel();
    _lifecycle.dispose();
    context.read<PlayerController>().removeListener(_updateAccent);
    super.dispose();
  }

  Future<void> _updateAccent() async {
    final url = context.read<PlayerController>().current?.artworkUrl;
    if (url == _accentFor) return;
    _accentFor = url;
    final c = await accentFromImage(url);
    if (mounted && _accentFor == url) setState(() => _accent = c);
  }

  void _select(int i) {
    if (i == _tab) {
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = _navKeys[_tab].currentState;
        if (nav != null && await nav.maybePop()) return;
        if (_tab != 0) {
          setState(() => _tab = 0);
        } else {
          // Back on Home with nothing open: leave the app (music keeps playing).
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(child: AuroraBackground(accent: _accent, energy: playing ? 1 : 0.25)),
            Positioned.fill(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 1100 : double.infinity),
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      for (var i = 0; i < 4; i++)
                        // Hidden tabs pause their animations.
                        TickerMode(
                          enabled: i == _tab,
                          child: HeroControllerScope.none(
                            child: Navigator(
                              key: _navKeys[i],
                              onGenerateRoute: (_) => FadeRoute(_pages[i]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 10),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MiniPlayer(),
                          const SizedBox(height: 8),
                          _TabBar(index: _tab, onSelect: _select),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.home_rounded, Icons.home_outlined, 'Home'),
    (Icons.search_rounded, Icons.search_rounded, 'Search'),
    (Icons.radio_rounded, Icons.radio_outlined, 'Radio'),
    (Icons.library_music_rounded, Icons.library_music_outlined, 'Library'),
  ];

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 100,
      blur: 32,
      strength: 1.1,
      backdrop: true, // floats over scrolling pages
      child: SizedBox(
        height: 62,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth / _items.length;
          return Stack(
            children: [
              // The liquid highlight that glides to the selected tab.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                left: index * w + 6,
                top: 6,
                bottom: 6,
                width: w - 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [MColors.purple.withValues(alpha: 0.45), MColors.violet.withValues(alpha: 0.25)],
                    ),
                    border: Border.all(color: const Color(0x66FFFFFF), width: 0.9),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: Pressable(
                        onTap: () => onSelect(i),
                        scale: 0.88,
                        child: Semantics(
                          label: _items[i].$3,
                          selected: i == index,
                          button: true,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                i == index ? _items[i].$1 : _items[i].$2,
                                size: 23,
                                color: i == index ? Colors.white : MColors.textSecondary,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _items[i].$3,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                                  color: i == index ? Colors.white : MColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// Floating glass mini player. Tap to open, swipe sideways to skip.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final track = player.current;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (c, a) => SizeTransition(
        sizeFactor: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
        alignment: Alignment.bottomCenter,
        child: FadeTransition(opacity: a, child: c),
      ),
      child: track == null
          ? const SizedBox(width: double.infinity)
          : GestureDetector(
              key: const ValueKey('mini'),
              onTap: () => openNowPlaying(context),
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < -300) openNowPlaying(context);
              },
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (track.isLive) return;
                if (v < -300) player.next();
                if (v > 300) player.previous();
              },
              child: Glass(
                radius: 22,
                blur: 32,
                strength: 1.2,
                backdrop: true, // floats over scrolling pages
                child: SizedBox(
                  height: 62,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
                        child: Row(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Artwork(
                                key: ValueKey(track.key),
                                url: track.artworkUrl,
                                size: 46,
                                radius: 10,
                                fit: track.isLive ? BoxFit.contain : BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: MText.title.copyWith(fontSize: 14)),
                                  const SizedBox(height: 2),
                                  if (player.remote != null)
                                    Row(
                                      children: [
                                        const Icon(Icons.speaker_group_rounded, size: 13, color: MColors.purple),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            player.remote!.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: MText.caption.copyWith(color: MColors.purple, fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      track.isLive ? 'Live radio' : track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: MText.caption.copyWith(color: MColors.textSecondary),
                                    ),
                                ],
                              ),
                            ),
                            const ConnectButton(size: 20),
                            Consumer<LibraryStore>(
                              builder: (context, lib, _) {
                                final liked = lib.isLiked(track);
                                return IconButton(
                                  icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                      color: liked ? MColors.lavender : MColors.text, size: 23),
                                  onPressed: () => lib.toggleLike(track),
                                );
                              },
                            ),
                            IconButton(
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                                child: player.buffering && player.playing
                                    ? const SizedBox.square(key: ValueKey('b'), dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Icon(
                                        player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        key: ValueKey(player.playing),
                                        size: 30,
                                        color: MColors.text,
                                      ),
                              ),
                              onPressed: player.togglePlay,
                            ),
                          ],
                        ),
                      ),
                      if (!track.isLive)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 0,
                          child: StreamBuilder<Duration>(
                            stream: player.positionStream,
                            builder: (_, snap) {
                              final d = player.duration?.inMilliseconds ?? 0;
                              final p = snap.data?.inMilliseconds ?? 0;
                              final f = d <= 0 ? 0.0 : (p / d).clamp(0.0, 1.0);
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: f,
                                  child: Container(
                                    height: 2.2,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(2),
                                      color: MColors.purple,
                                    ),
                                  ),
                                ),
                              );
                            },
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
