import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// A liquid-glass surface: live blur of what's behind, a soft white
/// gradient fill, a hairline border and a specular highlight on top.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 26,
    this.padding,
    this.tint,
    this.strength = 1,
    this.shape = BoxShape.rectangle,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Color? tint;

  /// 0..2, how milky the glass is.
  final double strength;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final borderRadius = shape == BoxShape.circle ? null : BorderRadius.circular(radius);
    final s = strength.clamp(0.0, 2.0);
    final decoration = BoxDecoration(
      shape: shape,
      borderRadius: borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(const Color(0x00FFFFFF), tint ?? const Color(0xFFFFFFFF), 0.16 * s)!,
          Color.lerp(const Color(0x00FFFFFF), tint ?? const Color(0xFFB9A3FF), 0.05 * s)!,
        ],
      ),
      border: Border.all(color: MColors.glassBorder, width: 0.8),
    );
    final highlight = BoxDecoration(
      shape: shape,
      borderRadius: borderRadius,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment(0, -0.2),
        colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
      ),
    );
    final body = DecoratedBox(
      decoration: decoration,
      position: DecorationPosition.background,
      child: DecoratedBox(
        decoration: highlight,
        position: DecorationPosition.foreground,
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
    final filter = BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: body,
    );
    return shape == BoxShape.circle
        ? ClipOval(child: filter)
        : ClipRRect(borderRadius: borderRadius!, child: filter);
  }
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
    final fg = filled ? MColors.bg : MColors.text;
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
                gradient: const LinearGradient(colors: [MColors.lilac, MColors.lavender]),
                boxShadow: [
                  BoxShadow(
                    color: MColors.violet.withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
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
          color: selected ? MColors.lavender : const Color(0x14FFFFFF),
          border: Border.all(color: selected ? MColors.lavender : MColors.glassBorder, width: 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? MColors.bg : MColors.text,
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
            decoration: const BoxDecoration(color: Color(0x8C120A22)),
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
