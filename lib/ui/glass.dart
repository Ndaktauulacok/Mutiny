import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Gentle colour boost on what shows through the glass.
const _vibrancy = ui.ColorFilter.matrix(<double>[
  1.315, -0.286, -0.029, 0, 0, //
  -0.085, 1.114, -0.029, 0, 0,
  -0.085, -0.286, 1.371, 0, 0,
  0, 0, 0, 1, 0,
]);

/// iPhone-style liquid glass: clear and see-through. Only a light blur, an
/// almost invisible fill, and bright refracting edges that catch the light.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 28,
    this.padding,
    this.tint,
    this.strength = 1,
    this.shape = BoxShape.rectangle,
  });

  final Widget child;
  final double radius;

  /// Relative blur; the glass stays mostly clear (sigma ≈ blur × 0.2).
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Color? tint;

  /// 0..2, how visible the glass body is.
  final double strength;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final borderRadius = shape == BoxShape.circle ? null : BorderRadius.circular(radius);
    final s = strength.clamp(0.0, 2.0);
    final sigma = (blur * 0.2).clamp(1.5, 10.0);
    final fill = BoxDecoration(
      shape: shape,
      borderRadius: borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(const Color(0x00FFFFFF), tint ?? const Color(0xFFFFFFFF), 0.07 * s)!,
          const Color(0x00FFFFFF),
          Color.lerp(const Color(0x00FFFFFF), tint ?? const Color(0xFFFFFFFF), 0.04 * s)!,
        ],
        stops: const [0, 0.5, 1],
      ),
    );
    final body = DecoratedBox(
      decoration: fill,
      child: CustomPaint(
        foregroundPainter: _GlassEdgePainter(radius: radius, circle: shape == BoxShape.circle),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
    final filter = BackdropFilter(
      filter: ui.ImageFilter.compose(
        outer: _vibrancy,
        inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror),
      ),
      child: body,
    );
    return shape == BoxShape.circle
        ? ClipOval(child: filter)
        : ClipRRect(borderRadius: borderRadius!, child: filter);
  }
}

/// The look of thick clear glass: light bending at the edges (a soft bright
/// band inside the rim), a crisp specular line on the top-left and
/// bottom-right, and a faint shadow line under the top edge for depth.
class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter({required this.radius, required this.circle});

  final double radius;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = circle ? size.shortestSide / 2 : radius;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(r));
    final edge = (size.shortestSide * 0.18).clamp(4.0, 14.0);

    canvas.save();
    canvas.clipRRect(rr);

    // Refraction band: bright inside the rim, fading toward the middle.
    canvas.drawRRect(
      rr.deflate(edge / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edge
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, edge * 0.6)
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [const Color(0x40FFFFFF), const Color(0x0AFFFFFF), const Color(0x08FFFFFF), const Color(0x30FFFFFF)],
          [0, 0.4, 0.6, 1],
        ),
    );

    // Small curved highlight near the top, like a reflection on a lens.
    final hl = Rect.fromLTWH(size.width * 0.06, 1.5, size.width * 0.88, (size.height * 0.28).clamp(4.0, 26.0));
    canvas.drawRRect(
      RRect.fromRectAndRadius(hl, Radius.circular(r)),
      Paint()
        ..shader = ui.Gradient.linear(hl.topCenter, hl.bottomCenter, [const Color(0x26FFFFFF), const Color(0x00FFFFFF)]),
    );
    canvas.restore();

    // Crisp specular rim.
    canvas.drawRRect(
      rr.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [const Color(0xE6FFFFFF), const Color(0x33FFFFFF), const Color(0x14FFFFFF), const Color(0x26FFFFFF), const Color(0xB3FFFFFF)],
          [0, 0.22, 0.5, 0.78, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_GlassEdgePainter old) => old.radius != radius || old.circle != circle;
}

/// Scales down slightly while pressed, like iOS controls.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 40,
    this.iconSize = 20,
    this.color = MColors.text,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Pressable(
      onTap: onTap,
      scale: 0.9,
      child: SizedBox.square(
        dimension: size,
        child: Glass(
          shape: BoxShape.circle,
          blur: 18,
          child: Center(child: Icon(icon, size: iconSize, color: color)),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Pill button. [filled] = lavender solid (primary action).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? const Color(0xFF2A0F55) : MColors.text;
    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20, vertical: compact ? 8 : 11),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 16 : 19, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 13 : 14,
            ),
          ),
        ],
      ),
    );
    return Pressable(
      onTap: onTap,
      child: filled
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                gradient: MColors.brand,
                border: Border.all(color: const Color(0x99FFFFFF), width: 0.8),
                boxShadow: [
                  BoxShadow(color: MColors.fuchsia.withValues(alpha: 0.45), blurRadius: 26, offset: const Offset(0, 8)),
                  BoxShadow(color: MColors.violet.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 3)),
                ],
              ),
              child: content,
            )
          : Glass(radius: 100, blur: 18, child: content),
    );
  }
}

/// Selectable chip used for filters (genres, countries, result types).
class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          gradient: selected ? MColors.brand : null,
          color: selected ? null : const Color(0x1AFFFFFF),
          border: Border.all(color: selected ? const Color(0xB3FFFFFF) : MColors.glassBorder, width: 0.8),
          boxShadow: selected ? [BoxShadow(color: MColors.fuchsia.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF2A0F55) : MColors.text,
          ),
        ),
      ),
    );
  }
}

/// Network artwork with a soft purple placeholder.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.size,
    this.radius = 10,
    this.icon = Icons.music_note_rounded,
    this.circle = false,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final double? size;
  final double radius;
  final IconData icon;
  final bool circle;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B1D6E), Color(0xFF1A0F33)],
        ),
      ),
      child: Center(
        child: LayoutBuilder(
          builder: (_, c) => Icon(
            icon,
            color: MColors.lavender.withValues(alpha: 0.75),
            size: (c.biggest.shortestSide * 0.38).clamp(14, 72),
          ),
        ),
      ),
    );
    final isFile = url != null && url!.isNotEmpty && !url!.startsWith('http');
    Widget img = url == null || url!.isEmpty
        ? placeholder
        : isFile
            ? (kIsWeb || !File(url!).existsSync()
                ? placeholder
                : Image.file(File(url!), fit: fit, gaplessPlayback: true, errorBuilder: (_, _, _) => placeholder))
            : Image.network(
            url!,
            fit: fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => placeholder,
            frameBuilder: (_, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 260),
                    child: frame == null ? placeholder : child,
                  ),
          );
    if (fit == BoxFit.contain && url != null) {
      img = ColoredBox(color: const Color(0xFF1A0F33), child: Padding(padding: const EdgeInsets.all(6), child: img));
    }
    final sized = SizedBox(width: size, height: size, child: img);
    return circle
        ? ClipOval(child: sized)
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: sized);
  }
}

/// Fade-through route used for pages inside each tab.
class FadeRoute<T> extends PageRouteBuilder<T> {
  FadeRoute(Widget page)
      : super(
          // Opaque: the page below stops painting once this one is in.
          // Pages are transparent, so the aurora behind the navigator shows.
          opaque: true,
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (_, _, _) => page,
          transitionsBuilder: (_, anim, secondary, child) {
            final inCurve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            final outCurve = CurvedAnimation(parent: secondary, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: Tween(begin: 1.0, end: 0.0).animate(outCurve),
              child: FadeTransition(
                opacity: inCurve,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(inCurve),
                  child: child,
                ),
              ),
            );
          },
        );
}

/// Glass bottom sheet with a grab handle.
Future<T?> showGlassSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scrollable = false}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x99050208),
    elevation: 0,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Glass(
          radius: 30,
          blur: 40,
          strength: 1.3,
          tint: const Color(0xFF8B5CF6),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0x801A0D33)),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: const Color(0x40FFFFFF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Flexible(child: builder(ctx)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class SheetAction extends StatelessWidget {
  const SheetAction({super.key, required this.icon, required this.label, required this.onTap, this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF8FA3) : MColors.text;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: danger ? color : MColors.lavender, size: 22),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: MText.title.copyWith(color: color, fontWeight: FontWeight.w500))),
          ],
        ),
      ),
    );
  }
}

void toast(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, textAlign: TextAlign.center),
      duration: const Duration(milliseconds: 1800),
      margin: const EdgeInsets.fromLTRB(40, 0, 40, 150),
    ));
}

Future<String?> askText(BuildContext context, {required String title, String initial = '', String action = 'Save'}) {
  final ctrl = TextEditingController(text: initial);
  return showGlassSheet<String>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: MText.h2, textAlign: TextAlign.center),
          const SizedBox(height: 22),
          TextField(
            controller: ctrl,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: MColors.text),
            decoration: const InputDecoration(
              border: UnderlineInputBorder(borderSide: BorderSide(color: MColors.glassBorder)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: MColors.glassBorder)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: MColors.lavender)),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          const SizedBox(height: 26),
          Center(child: PillButton(label: action, filled: true, onTap: () => Navigator.pop(ctx, ctrl.text))),
        ],
      ),
    ),
  );
}
