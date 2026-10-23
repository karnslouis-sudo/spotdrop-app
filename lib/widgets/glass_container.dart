import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/theme_service.dart';

class LiquidGlassCard extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 24.0,
    this.borderColor,
    this.backgroundColor,
    this.onTap,
  });

  @override
  State<LiquidGlassCard> createState() => _LiquidGlassCardState();
}

class _LiquidGlassCardState extends State<LiquidGlassCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeService();
    final style = theme.glassStyle;
    final accent = theme.accentColor;

    Color bg;
    Border border;
    List<BoxShadow> shadows;

    if (style == 'obsidian') {
      bg = widget.backgroundColor ?? const Color(0xFF06090F).withOpacity(0.92);
      border = Border.all(
        color: widget.borderColor ?? Colors.white.withOpacity(0.10),
        width: 1.0,
      );
      shadows = [
        BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 30, offset: const Offset(0, 12)),
      ];
    } else if (style == 'neon') {
      bg = widget.backgroundColor ?? const Color(0xFF0C121D).withOpacity(0.82);
      border = Border.all(
        color: widget.borderColor ?? accent.withOpacity(0.45),
        width: 1.5,
      );
      shadows = [
        BoxShadow(color: accent.withOpacity(0.18), blurRadius: 20, spreadRadius: 1),
        BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 24, offset: const Offset(0, 10)),
      ];
    } else {
      // Default: Liquid Glass
      bg = widget.backgroundColor ?? const Color(0xFF101624).withOpacity(0.72);
      border = Border.all(
        color: widget.borderColor ?? Colors.white.withOpacity(0.18),
        width: 1.2,
      );
      shadows = [
        BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 10)),
        BoxShadow(color: accent.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, -2)),
      ];
    }

    Widget content = AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Container(
        width: widget.width,
        height: widget.height,
        margin: widget.margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: shadows,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: widget.padding ?? const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: border,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.12),
                    Colors.white.withOpacity(0.02),
                  ],
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    if (widget.onTap != null) {
      return GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: content,
      );
    }
    return content;
  }
}

typedef GlassContainer = LiquidGlassCard;
