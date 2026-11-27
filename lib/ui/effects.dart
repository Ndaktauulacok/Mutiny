import 'dart:async';
import 'dart:io';
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
        Offset(w * (0.12 + 0.25 * math.sin(t * 0.9)), h * (0.08 + 0.08 * math.cos(t * 0.7))),
        m * 0.8,
        Color.lerp(MColors.violet, accent, 0.4)!.withValues(alpha: 0.85),
      ),
      (
        Offset(w * (0.98 + 0.15 * math.cos(t * 0.6)), h * (0.30 + 0.15 * math.sin(t * 0.8))),
        m * 0.62,
        Color.lerp(MColors.fuchsia, accent, 0.3)!.withValues(alpha: 0.55),
      ),
      (
        Offset(w * (0.25 + 0.3 * math.cos(t * 0.5 + 1)), h * (0.78 + 0.1 * math.sin(t * 0.65))),
        m * 0.7,
        const Color(0xFF5B3BFF).withValues(alpha: 0.6),
      ),
      (
        Offset(w * (0.8 + 0.2 * math.sin(t * 1.1 + 2)), h * (0.62 + 0.12 * math.cos(t * 0.9))),
        m * 0.42,
        Color.lerp(MColors.pink, accent, 0.25)!.withValues(alpha: 0.38),
      ),
      (
        Offset(w * (0.5 + 0.35 * math.sin(t * 0.4 + 4)), h * (0.45 + 0.2 * math.cos(t * 0.55 + 1))),
        m * 0.3,
        MColors.sky.withValues(alpha: 0.18),
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
    // Gentle shade at the bottom keeps text readable over the tab bar.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, h),
          [const Color(0x00110824), const Color(0x00110824), const Color(0x99110824)],
          [0, 0.55, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.accent != accent;
}

// ------------------------------------------------------------ liquid orb

/// Mutiny's signature animation: a glossy drop of liquid purple glass that
/// morphs, wobbles and sheds little droplets. When [active] (music playing)
/// it moves faster and ripples harder.
class LiquidOrb extends StatefulWidget {
  const LiquidOrb({super.key, this.active = false, this.color = MColors.purple});

  final bool active;
  final Color color;

  @override
  State<LiquidOrb> createState() => _LiquidOrbState();
}

class _LiquidOrbState extends State<LiquidOrb> with SingleTickerProviderStateMixin, _TimeTicker {
  final ValueNotifier<double> energy = ValueNotifier(0.2);

  @override
  void initState() {
    super.initState();
    targetSpeed = widget.active ? 1.5 : 0.5;
    speed = targetSpeed;
    energy.value = widget.active ? 1 : 0.2;
    startTicker();
    time.addListener(_ease);
  }

  void _ease() {
    final goal = widget.active ? 1.0 : 0.2;
    energy.value += (goal - energy.value) * 0.03;
  }

  @override
  void didUpdateWidget(LiquidOrb old) {
    super.didUpdateWidget(old);
    targetSpeed = widget.active ? 1.5 : 0.5;
  }

  @override
  void dispose() {
    time.removeListener(_ease);
    energy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _LiquidOrbPainter(time, energy, widget.color), size: Size.infinite),
      );
}

class _LiquidOrbPainter extends CustomPainter {
  _LiquidOrbPainter(this.time, this.energy, this.color) : super(repaint: time);

  final ValueNotifier<double> time;
  final ValueNotifier<double> energy;
  final Color color;

  Path _blob(Offset c, double r, double t, double seed, double amp) {
    const n = 90;
    final path = Path();
    for (var i = 0; i <= n; i++) {
      final a = i / n * math.pi * 2;
      final k = 1 +
          amp *
              (0.085 * math.sin(2 * a + t * 1.1 + seed) +
                  0.06 * math.sin(3 * a - t * 0.8 + seed * 1.7) +
                  0.035 * math.sin(5 * a + t * 1.6 + seed * 0.6) +
                  0.02 * math.sin(7 * a - t * 2.2));
      final p = c + Offset(math.cos(a), math.sin(a)) * (r * k);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final e = energy.value;
    final r = math.min(size.width, size.height) * 0.32 * (1 + 0.04 * e * math.sin(t * 3.1));
    final c = size.center(Offset(0, math.sin(t * 0.7) * r * 0.04));
    final amp = 0.7 + 1.1 * e;
    final deep = Color.lerp(MColors.deep, color, 0.25)!;
    final mid = Color.lerp(MColors.violet, color, 0.5)!;

    // Soft glow under the drop.
    canvas.drawPath(
      _blob(c, r * 1.08, t * 0.8, 2.1, amp),
      Paint()
        ..color = mid.withValues(alpha: 0.35 + 0.25 * e)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.38),
    );

    // Droplets that orbit, stretch away and fall back in.
    final dropPaint = Paint()
      ..shader = ui.Gradient.radial(c - Offset(r * 0.4, r * 0.5), r * 2.2, [MColors.lilac, mid, deep], [0, 0.45, 1]);
    for (var i = 0; i < 3; i++) {
      final ang = t * (0.35 + i * 0.13) + i * 2.1;
      final pull = 0.98 + (0.18 + 0.12 * e) * (0.5 + 0.5 * math.sin(t * (0.9 + i * 0.3) + i));
      final pos = c + Offset(math.cos(ang), math.sin(ang)) * r * pull;
      final dr = r * (0.13 + 0.05 * math.sin(t * 1.3 + i * 1.7)) * (0.8 + 0.4 * e);
      canvas.drawCircle(pos, dr, dropPaint);
    }

    // The body: deep glass with a light core.
    final body = _blob(c, r, t, 0, amp);
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          c - Offset(r * 0.38, r * 0.45),
          r * 1.75,
          [MColors.lilac, Color.lerp(MColors.lavender, color, 0.3)!, mid, deep],
          [0, 0.22, 0.55, 1],
        ),
    );

    // Inner current swirling inside the drop.
    canvas.save();
    canvas.clipPath(body);
    final swirl = c + Offset(math.cos(t * 0.6), math.sin(t * 0.8)) * r * 0.28;
    canvas.drawPath(
      _blob(swirl, r * 0.55, -t * 1.3, 4.0, amp * 1.4),
      Paint()
        ..color = const Color(0xFFF0ABFC).withValues(alpha: 0.18 + 0.12 * e)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.16),
    );
    canvas.drawPath(
      _blob(c + Offset(r * 0.3, r * 0.45), r * 0.7, t * 0.9, 1.3, amp),
      Paint()
        ..color = deep.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
    );
    canvas.restore();

    // Glass rim and specular highlight.
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = ui.Gradient.linear(c - Offset(r, r), c + Offset(r, r), [const Color(0x80FFFFFF), const Color(0x10FFFFFF)]),
    );
    canvas.save();
    canvas.translate(c.dx - r * 0.36, c.dy - r * 0.46);
    canvas.rotate(-0.55);
    final hl = Rect.fromCenter(center: Offset.zero, width: r * 0.62, height: r * 0.26);
    canvas.drawOval(
      hl,
      Paint()
        ..shader = ui.Gradient.linear(hl.topCenter, hl.bottomCenter, [const Color(0xB3FFFFFF), const Color(0x00FFFFFF)]),
    );
    canvas.restore();
    canvas.drawCircle(
      c + Offset(r * 0.42, r * 0.38),
      r * 0.06,
      Paint()..color = const Color(0x40FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_LiquidOrbPainter old) => old.color != color;
}

// ---------------------------------------------------------- liquid cover

/// Generated cover for mixes and genres: soft liquid colour blobs under a
/// glass sheen, with a big thin number (or label) and the flag mark.
class LiquidCover extends StatelessWidget {
  const LiquidCover({super.key, required this.index, required this.color, this.label = '', this.showMark = true});

  final int index;
  final Color color;
  final String label;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final short = label.length <= 3;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _LiquidCoverPainter(index, color)),
          if (showMark)
            Positioned(
              left: 10,
              top: 10,
              child: Image.asset('assets/brand/mark_white.png', width: 18, height: 18),
            ),
          if (label.isNotEmpty)
            Positioned(
              left: 12,
              right: 10,
              bottom: short ? 2 : 10,
              child: FittedBox(
                alignment: Alignment.bottomLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: MText.display,
                    fontWeight: short ? FontWeight.w300 : FontWeight.w700,
                    fontSize: short ? 64 : 22,
                    height: 1,
                    letterSpacing: short ? -3 : -0.4,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiquidCoverPainter extends CustomPainter {
  _LiquidCoverPainter(this.seed, this.color);

  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), [Color.lerp(color, Colors.black, 0.35)!, Color.lerp(color, Colors.black, 0.8)!]),
    );
    final rnd = math.Random(seed * 9973 + 7);
    final hsv = HSVColor.fromColor(color);
    final palette = [
      hsv.withHue((hsv.hue + 25) % 360).withSaturation(0.7).withValue(1).toColor(),
      MColors.lilac,
      hsv.withHue((hsv.hue - 35 + 360) % 360).withValue(0.85).toColor(),
    ];
    for (var i = 0; i < 3; i++) {
      final center = Offset(w * (0.15 + rnd.nextDouble() * 0.75), h * (0.1 + rnd.nextDouble() * 0.7));
      final radius = w * (0.22 + rnd.nextDouble() * 0.2);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: radius * 2, height: radius * (1.4 + rnd.nextDouble() * 0.8)),
        Paint()
          ..color = palette[i].withValues(alpha: i == 1 ? 0.45 : 0.75)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.12),
      );
    }
    // Curved glass sheen across the top.
    final sheen = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.28)
      ..quadraticBezierTo(w * 0.55, h * 0.48, 0, h * 0.36)
      ..close();
    canvas.drawPath(
      sheen,
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, h * 0.45), [const Color(0x2EFFFFFF), const Color(0x05FFFFFF)]),
    );
    // Darken the bottom so the label reads.
    canvas.drawRect(
      rect,
      Paint()..shader = ui.Gradient.linear(Offset(0, h * 0.45), Offset(0, h), [const Color(0x00000000), const Color(0x66000000)]),
    );
  }

  @override
  bool shouldRepaint(_LiquidCoverPainter old) => old.seed != seed || old.color != color;
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
    final ImageProvider base = url.startsWith('http') ? NetworkImage(url) : FileImage(File(url));
    final provider = ResizeImage(base, width: 32, height: 32);
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
