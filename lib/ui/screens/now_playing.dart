import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/library_store.dart';
import '../../services/player_controller.dart';
import '../effects.dart';
import '../glass.dart';
import '../theme.dart';
import '../widgets.dart';
import 'collection_screen.dart';
import 'lyrics_view.dart';

/// Opens the full-screen player, sliding up from the mini player.
void openNowPlaying(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => const Material(type: MaterialType.transparency, child: NowPlayingScreen()),
    transitionsBuilder: (_, anim, _, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curve),
        child: child,
      );
    },
  ));
}

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final track = player.current;
    if (track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.maybePop(context);
      });
      return const SizedBox.shrink();
    }
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final wide = size.width > 760;
    final artSize = wide
        ? (size.height * 0.55).clamp(220.0, 460.0)
        : (size.width - 56).clamp(200.0, size.height * 0.42);

    return GestureDetector(
      onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(0, 600)),
      onVerticalDragEnd: (d) {
        if (_drag > 140 || d.velocity.pixelsPerSecond.dy > 900) {
          Navigator.maybePop(context);
        } else {
          setState(() => _drag = 0);
        }
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: _drag == 0 ? 250 : 0),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _drag, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_drag > 0 ? 28 : 0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Backdrop(track: track, playing: player.playing),
              Padding(
                padding: EdgeInsets.fromLTRB(24, pad.top + 6, 24, pad.bottom + 14),
                child: wide
                    ? Row(
                        children: [
                          Expanded(child: Center(child: _Cover(track: track, size: artSize, playing: player.playing))),
                          const SizedBox(width: 40),
                          Expanded(child: _Controls(track: track, topBar: true)),
                        ],
                      )
                    : Column(
                        children: [
                          _TopBar(track: track),
                          const Spacer(),
                          _Cover(track: track, size: artSize, playing: player.playing),
                          const Spacer(),
                          _Controls(track: track),
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

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.track, required this.playing});

  final Track track;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<Color?>(
          future: accentFromImage(track.artworkUrl),
          builder: (_, snap) => AuroraBackground(accent: snap.data, energy: playing ? 1 : 0.3),
        ),
        if (track.bestArtwork != null && !track.isLive)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            child: Opacity(
              key: ValueKey(track.key),
              opacity: 0.55,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70, tileMode: TileMode.decal),
                child: Transform.scale(scale: 1.4, child: Artwork(url: track.artworkUrl, radius: 0)),
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x330A0612), Color(0x660A0612), Color(0xE60A0612)],
              stops: [0, 0.5, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return Row(
      children: [
        GlassIconButton(icon: Icons.keyboard_arrow_down_rounded, iconSize: 26, onTap: () => Navigator.maybePop(context)),
        Expanded(
          child: Column(
            children: [
              Text(track.isLive ? 'LIVE RADIO' : 'PLAYING FROM', style: MText.label),
              const SizedBox(height: 3),
              Text(
                player.contextName ?? (track.isLocal ? 'Your device' : 'Mutiny'),
                style: MText.title.copyWith(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        GlassIconButton(icon: Icons.more_horiz_rounded, onTap: () => showTrackMenu(context, track)),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.track, required this.size, required this.playing});

  final Track track;
  final double size;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    if (track.isLive) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: LiquidOrb(active: playing)),
            Artwork(url: track.artworkUrl, size: size * 0.24, radius: 18, icon: Icons.radio_rounded, fit: BoxFit.contain),
          ],
        ),
      );
    }
    return AnimatedScale(
      scale: playing ? 1 : 0.86,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(anim), child: child),
        ),
        child: Container(
          key: ValueKey(track.key),
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 50, offset: const Offset(0, 24))],
          ),
          child: Artwork(url: track.bestArtwork, radius: 24, icon: track.isLocal ? Icons.audio_file_rounded : Icons.music_note_rounded),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.track, this.topBar = false});

  final Track track;
  final bool topBar;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final lib = context.watch<LibraryStore>();
    final liked = lib.isLiked(track);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (topBar) ...[_TopBar(track: track), const SizedBox(height: 40)],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      track.title,
                      key: ValueKey(track.key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MText.h2.copyWith(fontSize: 21),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Pressable(
                    onTap: track.artistId == null
                        ? null
                        : () {
                            Navigator.maybePop(context);
                            final nav = rootTabNavigator?.call();
                            nav?.push(FadeRoute(CollectionScreen.artist(artist: Artist(id: track.artistId!, name: track.artist))));
                          },
                    child: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: MText.body.copyWith(fontSize: 15)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _HeartButton(
              liked: liked,
              onTap: () {
                final now = lib.toggleLike(track);
                toast(context, now ? (track.isLive ? 'Station saved' : 'Added to Liked Songs') : 'Removed');
              },
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (track.isLive) const _LiveBar() else const _Timeline(),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ToggleIcon(
              icon: Icons.shuffle_rounded,
              active: player.shuffle,
              onTap: track.isLive ? null : player.toggleShuffle,
            ),
            _RoundIcon(icon: Icons.skip_previous_rounded, size: 38, onTap: track.isLive ? null : player.previous),
            _PlayButton(playing: player.playing, buffering: player.buffering, onTap: player.togglePlay),
            _RoundIcon(icon: Icons.skip_next_rounded, size: 38, onTap: track.isLive ? null : player.next),
            _ToggleIcon(
              icon: player.repeat == RepeatState.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              active: player.repeat != RepeatState.off,
              onTap: track.isLive ? null : player.cycleRepeat,
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ToggleIcon(
              icon: Icons.bedtime_rounded,
              active: player.sleepActive,
              size: 22,
              onTap: () => _sleepSheet(context),
            ),
            if (!track.isLive)
              _ToggleIcon(icon: Icons.lyrics_rounded, active: false, size: 23, onTap: () => openLyrics(context, track)),
            _ToggleIcon(icon: Icons.ios_share_rounded, active: false, size: 22, onTap: () => shareTrack(track)),
            if (!track.isLive)
              _ToggleIcon(icon: Icons.playlist_add_rounded, active: false, size: 24, onTap: () => showAddToPlaylist(context, track)),
            _ToggleIcon(icon: Icons.queue_music_rounded, active: false, size: 24, onTap: () => _queueSheet(context)),
          ],
        ),
      ],
    );
  }
}

/// Lets the full player navigate inside the current tab (set by the shell).
NavigatorState? Function()? rootTabNavigator;

class _HeartButton extends StatelessWidget {
  const _HeartButton({required this.liked, required this.onTap});

  final bool liked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.8,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.elasticOut), child: c),
        child: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(liked),
          color: liked ? MColors.lavender : MColors.text,
          size: 30,
        ),
      ),
    );
  }
}

class _Timeline extends StatefulWidget {
  const _Timeline();

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final dur = player.duration ?? Duration.zero;
        final pos = snap.data ?? Duration.zero;
        final max = dur.inMilliseconds.toDouble().clamp(1.0, double.infinity);
        final value = (_dragValue ?? pos.inMilliseconds.toDouble()).clamp(0.0, max);
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: _dragValue == null ? 3.5 : 6,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: _dragValue == null ? 5 : 8),
              ),
              child: SizedBox(
                height: 24,
                child: Slider(
                  value: value,
                  max: max,
                  padding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _dragValue = v),
                  onChangeEnd: (v) {
                    player.seek(Duration(milliseconds: v.round()));
                    setState(() => _dragValue = null);
                  },
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(Duration(milliseconds: value.round())), style: MText.caption),
                Text('-${formatDuration(dur - Duration(milliseconds: value.round()))}', style: MText.caption),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LiveBar extends StatelessWidget {
  const _LiveBar();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 3.5,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: const LinearGradient(colors: [Color(0xFFF472B6), MColors.lavender]),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.circle, size: 8, color: Color(0xFFF472B6)),
            SizedBox(width: 6),
            Text('LIVE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Color(0xFFF9A8D4), fontSize: 12)),
          ],
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.buffering, required this.onTap});

  final bool playing;
  final bool buffering;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.9,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: MColors.purple,
          boxShadow: [BoxShadow(color: MColors.purple.withValues(alpha: 0.45), blurRadius: 30, offset: const Offset(0, 8))],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (buffering && playing)
              const SizedBox.square(dimension: 74, child: CircularProgressIndicator(strokeWidth: 2.2, color: MColors.violet)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playing),
                size: 42,
                color: MColors.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.size = 30});

  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.85,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: size, color: onTap == null ? MColors.textTertiary : MColors.text),
        ),
      );
}

class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon({required this.icon, required this.active, required this.onTap, this.size = 24});

  final IconData icon;
  final bool active;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? MColors.textTertiary.withValues(alpha: 0.3) : (active ? MColors.lavender : MColors.textSecondary);
    return Pressable(
      onTap: onTap,
      scale: 0.85,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: size, color: color),
            const SizedBox(height: 3),
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: MColors.lavender, shape: BoxShape.circle)),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- sheets

void _sleepSheet(BuildContext context) {
  final player = context.read<PlayerController>();
  showGlassSheet(
    context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(0, 16, 0, 4), child: Text('Sleep timer', style: MText.h2)),
        if (player.sleepAt != null)
          Text('Stops at ${TimeOfDay.fromDateTime(player.sleepAt!).format(ctx)}', style: MText.body),
        if (player.sleepAfterTrack) const Text('Stops after this song', style: MText.body),
        const SizedBox(height: 8),
        for (final m in [5, 15, 30, 45, 60])
          SheetAction(
            icon: Icons.timer_outlined,
            label: '$m minutes',
            onTap: () {
              player.setSleepTimer(Duration(minutes: m));
              Navigator.pop(ctx);
              toast(context, 'Music stops in $m minutes');
            },
          ),
        SheetAction(
          icon: Icons.music_note_rounded,
          label: 'End of this song',
          onTap: () {
            player.setSleepTimer(null, endOfTrack: true);
            Navigator.pop(ctx);
          },
        ),
        if (player.sleepActive)
          SheetAction(
            icon: Icons.close_rounded,
            label: 'Turn off timer',
            danger: true,
            onTap: () {
              player.setSleepTimer(null);
              Navigator.pop(ctx);
            },
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
}

void _queueSheet(BuildContext context) {
  showGlassSheet(context, builder: (ctx) => const _QueueView());
}

class _QueueView extends StatelessWidget {
  const _QueueView();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final queue = player.queue;
    final current = player.queueIndex;
    final upNext = queue.length > current + 1 ? queue.sublist(current + 1) : const <Track>[];
    final height = MediaQuery.sizeOf(context).height * 0.72;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(22, 18, 22, 8), child: Text('Now playing', style: MText.label)),
          if (player.current != null)
            TrackTile(track: player.current!, onTap: () {}),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
            child: Row(
              children: [
                const Expanded(child: Text('Next up', style: MText.label)),
                if (player.shuffle) const Text('Shuffled', style: MText.caption),
              ],
            ),
          ),
          Expanded(
            child: upNext.isEmpty
                ? const Center(child: Text('Nothing queued', style: MText.body))
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: upNext.length,
                    proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                    onReorderItem: (from, to) => player.moveInQueue(current + 1 + from, current + 1 + to),
                    itemBuilder: (_, i) {
                      final t = upNext[i];
                      final qi = current + 1 + i;
                      return Dismissible(
                        key: ValueKey('q$qi${t.key}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: const Color(0x33F472B6),
                          child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF9A8D4)),
                        ),
                        onDismissed: (_) => player.removeFromQueue(qi),
                        child: Row(
                          children: [
                            Expanded(child: TrackTile(track: t, onTap: () => player.jumpTo(qi))),
                            if (player.canReorder)
                              ReorderableDragStartListener(
                                index: i,
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 16),
                                  child: Icon(Icons.drag_handle_rounded, color: MColors.textTertiary),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
