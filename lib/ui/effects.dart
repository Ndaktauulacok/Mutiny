import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Drives a painter with elapsed seconds; [speed] eases toward its target
/// so motion speeds up / calms down smoothly (e.g. on play / pause).
mixin _TimeTicker<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  late final Ticker _ticker;
  final ValueNotifier<double> time = ValueNotifier(0);
  Duration _last = Duration.zero;
  double speed = 1;
  double targetSpeed = 1;

  void startTicker() {
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      speed += (targetSpeed - speed) * math.min(1, dt * 2.5);
      time.value += dt * speed;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    time.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------- aurora

/// Slow drifting purple light behind the whole app. [accent] blends in the
/// colour of the current song's cover.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, this.accent, this.energy = 0.4});

  final Color? accent;

  /// 0..1 — how lively the drift is (higher while music plays).
  final double energy;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin, _TimeTicker {
  @override
  void initState() {
    super.initState();
    targetSpeed = 0.35 + widget.energy * 0.8;
    speed = targetSpeed;
    startTicker();
  }

  @override
  void didUpdateWidget(AuroraBackground old) {
    super.didUpdateWidget(old);
    targetSpeed = 0.35 + widget.energy * 0.8;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? MColors.violet;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: accent),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeInOut,
      builder: (_, color, _) => RepaintBoundary(
        child: CustomPaint(
          painter: _AuroraPainter(time, color ?? accent),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.time, this.accent) : super(repaint: time);

  final ValueNotifier<double> time;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value * 0.12;
    canvas.drawRect(Offset.zero & size, Paint()..color = MColors.bg);

    final w = size.width, h = size.height;
    final m = math.max(w, h);
    final blobs = <(Offset, double, Color)>[
      (
        Offset(w * (0.15 + 0.25 * math.sin(t * 0.9)), h * (0.10 + 0.08 * math.cos(t * 0.7))),
        m * 0.75,
        Color.lerp(MColors.violet, accent, 0.45)!.withValues(alpha: 0.55),
      ),
      (
        Offset(w * (0.95 + 0.15 * math.cos(t * 0.6)), h * (0.35 + 0.15 * math.sin(t * 0.8))),
        m * 0.6,
        Color.lerp(MColors.deep, accent, 0.35)!.withValues(alpha: 0.7),
      ),
      (
        Offset(w * (0.3 + 0.3 * math.cos(t * 0.5 + 1)), h * (0.85 + 0.1 * math.sin(t * 0.65))),
        m * 0.7,
        const Color(0xFF4C1D95).withValues(alpha: 0.55),
      ),
      (
        Offset(w * (0.7 + 0.2 * math.sin(t * 1.1 + 2)), h * (0.6 + 0.12 * math.cos(t * 0.9))),
        m * 0.35,
        Color.lerp(MColors.purple, accent, 0.3)!.withValues(alpha: 0.22),
      ),
    ];
    for (final (center, radius, color) in blobs) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(center, radius, [color, color.withValues(alpha: 0)]),
      );
    }
    // Vignette keeps text readable at the edges.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, h),
          [const Color(0x330A0612), const Color(0x000A0612), const Color(0xCC0A0612)],
          [0, 0.45, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.accent != accent;
}

// -------------------------------------------------------------- wave orb

/// The "My Wave" dot-matrix orb: a halftone ring that ripples and breathes.
/// When [active] (music playing) it moves faster and pulses harder.
class WaveOrb extends StatefulWidget {
  const WaveOrb({super.key, this.active = false, this.color = MColors.lavender, this.spacing = 7});

  final bool active;
  final Color color;
  final double spacing;

  @override
  State<WaveOrb> createState() => _WaveOrbState();
}

class _WaveOrbState extends State<WaveOrb> with SingleTickerProviderStateMixin, _TimeTicker {
  final ValueNotifier<double> energy = ValueNotifier(0.3);
  Timer? _energyTimer;

  @override
  void initState() {
    super.initState();
    targetSpeed = widget.active ? 1.6 : 0.6;
    speed = targetSpeed;
    energy.value = widget.active ? 1 : 0.3;
    startTicker();
    time.addListener(_ease);
  }

  void _ease() {
    final goal = widget.active ? 1.0 : 0.3;
    energy.value += (goal - energy.value) * 0.04;
  }

  @override
  void didUpdateWidget(WaveOrb old) {
    super.didUpdateWidget(old);
    targetSpeed = widget.active ? 1.6 : 0.6;
  }

  @override
  void dispose() {
    _energyTimer?.cancel();
    time.removeListener(_ease);
    energy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _WaveOrbPainter(time, energy, widget.color, widget.spacing),
          size: Size.infinite,
        ),
      );
}

class _WaveOrbPainter extends CustomPainter {
  _WaveOrbPainter(this.time, this.energy, this.color, this.spacing) : super(repaint: time);

  final ValueNotifier<double> time;
  final ValueNotifier<double> energy;
  final Color color;
  final double spacing;

  static const _levels = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final e = energy.value;
    final cx = size.width / 2, cy = size.height / 2;
    final rx = size.width * 0.46, ry = size.height * 0.44;
    final buckets = List.generate(_levels, (_) => <Offset>[]);

    final ringCenter = 0.58 + 0.07 * math.sin(t * 0.8) * (0.5 + e);
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        final nx = (x - cx) / rx, ny = (y - cy) / ry;
        final d = math.sqrt(nx * nx + ny * ny);
        if (d > 1.15) continue;
        final a = math.atan2(ny, nx);
        final wobble = 0.09 * math.sin(3 * a + t * 1.1) +
            0.06 * math.sin(5 * a - t * 0.8) +
            0.05 * e * math.sin(7 * a + t * 2.3);
        final dd = d + wobble;
        final ring = math.exp(-math.pow((dd - ringCenter) / (0.2 + 0.05 * e), 2));
        final ripple = 0.5 + 0.5 * math.sin(dd * 11 - t * (2.0 + 2.5 * e));
        final core = 0.35 * math.exp(-math.pow(dd / 0.22, 2)) * (0.5 + 0.5 * math.sin(t * 1.7));
        final fade = (1 - ((d - 0.85) / 0.3).clamp(0.0, 1.0));
        final v = ((ring * (0.6 + 0.4 * ripple) + core * e) * fade).clamp(0.0, 1.0);
        final level = (v * _levels).floor();
        if (level <= 0) continue;
        buckets[math.min(level, _levels) - 1].add(Offset(x, y));
      }
    }
    for (var i = 0; i < _levels; i++) {
      if (buckets[i].isEmpty) continue;
      final f = (i + 1) / _levels;
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = spacing * (0.22 + 0.68 * f)
        ..color = Color.lerp(MColors.deep, color, 0.35 + 0.65 * f)!.withValues(alpha: 0.35 + 0.65 * f);
      canvas.drawPoints(ui.PointMode.points, buckets[i], paint);
    }
  }

  @override
  bool shouldRepaint(_WaveOrbPainter old) => old.color != color || old.spacing != spacing;
}

// -------------------------------------------------------- halftone cover

/// Generated cover for daily mixes: a halftone dot pattern with a big
/// "MIX n" label, like the reference design.
class HalftoneCover extends StatelessWidget {
  const HalftoneCover({super.key, required this.index, required this.color, this.label});

  final int index;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _HalftonePainter(index, color)),
          const Positioned(
            left: 10,
            top: 10,
            child: _MiniMark(),
          ),
          Positioned(
            left: 10,
            right: 8,
            bottom: 6,
            child: FittedBox(
              alignment: Alignment.bottomLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                label ?? 'MIX ${index + 1}',
                style: const TextStyle(
                  fontFamily: MText.display,
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  letterSpacing: -0.5,
                  color: Colors.white,
                  shadows: [Shadow(color: Color(0x66000000), blurRadius: 12)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMark extends StatelessWidget {
  const _MiniMark();

  @override
  Widget build(BuildContext context) => const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 18);
}

class _HalftonePainter extends CustomPainter {
  _HalftonePainter(this.seed, this.color);

  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = Color.lerp(color, Colors.black, 0.72)!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          [Color.lerp(color, Colors.black, 0.45)!, dark],
        ),
    );
    final rnd = math.Random(seed * 7919 + 13);
    final fx = 1.5 + rnd.nextDouble() * 3, fy = 1.5 + rnd.nextDouble() * 3;
    final px = rnd.nextDouble() * math.pi * 2, py = rnd.nextDouble() * math.pi * 2;
    final cx = size.width * (0.3 + rnd.nextDouble() * 0.5);
    final cy = size.height * (0.2 + rnd.nextDouble() * 0.4);
    final step = size.width / 22;
    final paint = Paint()..strokeCap = StrokeCap.round;
    final buckets = <int, List<Offset>>{};
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        final u = x / size.width, v = y / size.height;
        final dist = (Offset(x, y) - Offset(cx, cy)).distance / size.width;
        var s = 0.5 + 0.25 * math.sin(u * fx * math.pi + px) + 0.25 * math.cos(v * fy * math.pi + py);
        s = s * 0.6 + 0.4 * math.max(0, 1 - dist * 1.6);
        final level = (s.clamp(0, 1) * 6).round();
        if (level <= 0) continue;
        buckets.putIfAbsent(level, () => []).add(Offset(x, y));
      }
    }
    buckets.forEach((level, pts) {
      final f = level / 6;
      paint
        ..strokeWidth = step * (0.25 + 0.6 * f)
        ..color = Color.lerp(color, Colors.white, 0.15 + 0.35 * f)!.withValues(alpha: 0.35 + 0.6 * f);
      canvas.drawPoints(ui.PointMode.points, pts, paint);
    });
  }

  @override
  bool shouldRepaint(_HalftonePainter old) => old.seed != seed || old.color != color;
}

// ------------------------------------------------------------ equalizer

/// Small bouncing bars shown next to the song that is playing.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({super.key, this.playing = true, this.size = 14, this.color = MColors.lavender});

  final bool playing;
  final double size;
  final Color color;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) _c.repeat();
    if (!widget.playing) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(painter: _EqPainter(_c.value, widget.color)),
        ),
      );
}

class _EqPainter extends CustomPainter {
  _EqPainter(this.v, this.color);
  final double v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final w = size.width / 5;
    for (var i = 0; i < 3; i++) {
      final phase = v * math.pi * 2 + i * 2.1;
      final h = size.height * (0.3 + 0.7 * (0.5 + 0.5 * math.sin(phase * (1 + i * 0.3))));
      canvas.drawRRect(
        RRect.fromLTRBR(i * 2 * w, size.height - h, i * 2 * w + w, size.height, Radius.circular(w / 2)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_EqPainter old) => old.v != v || old.color != color;
}

// ---------------------------------------------------------- cover colour

final _accentCache = <String, Color?>{};

/// The most vivid colour in an image, pulled toward the lavender theme so
/// the app always stays purple-ish. Null when the image can't be read.
Future<Color?> accentFromImage(String? url) async {
  if (url == null || url.isEmpty) return null;
  if (_accentCache.containsKey(url)) return _accentCache[url];
  try {
    final provider = ResizeImage(NetworkImage(url), width: 32, height: 32);
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info.image.clone());
        stream.removeListener(listener);
      },
      onError: (e, _) {
        if (!completer.isCompleted) completer.completeError(e);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    final image = await completer.future.timeout(const Duration(seconds: 8));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return _accentCache[url] = null;

    var best = MColors.violet;
    var bestScore = -1.0;
    double r = 0, g = 0, b = 0;
    var n = 0;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final c = Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
      final hsv = HSVColor.fromColor(c);
      final score = hsv.saturation * (0.3 + hsv.value) * (hsv.value > 0.15 ? 1 : 0);
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
      r += c.r;
      g += c.g;
      b += c.b;
      n++;
    }
    final avg = n == 0 ? best : Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n);
    final picked = bestScore > 0.25 ? best : avg;
    final hsv = HSVColor.fromColor(picked);
    final vivid = hsv.withSaturation(math.max(hsv.saturation, 0.45)).withValue(math.max(hsv.value, 0.6)).toColor();
    return _accentCache[url] = Color.lerp(vivid, MColors.violet, 0.35);
  } catch (_) {
    return _accentCache[url] = null;
  }
}
