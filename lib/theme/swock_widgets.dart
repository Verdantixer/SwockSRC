import 'package:flutter/material.dart';

class SwockColors {
  static const background = Color(0xFF080B09);
  static const surface = Color(0xFF101512);
  static const line = Color(0xFF39413B);
  static const muted = Color(0xFFA7B0AA);
  static const faint = Color(0xFF77817A);
  static const green = Color(0xFF55E89A);
  static const cyan = Color(0xFF5FE5E4);
  static const ink = Color(0xFFE2E8E4);
  static const amber = Color(0xFFFFD45C);
  static const red = Color(0xFFFF625C);
}

class SwockCard extends StatelessWidget {
  const SwockCard({
    super.key,
    required this.child,
    this.minHeight,
    this.padding,
  });

  final Widget child;
  final double? minHeight;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: BoxConstraints(minHeight: minHeight ?? 0),
    padding:
        padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: SwockColors.surface,
      border: Border.all(color: SwockColors.line),
      borderRadius: BorderRadius.circular(7),
    ),
    child: child,
  );
}

class SwockHeading extends StatelessWidget {
  const SwockHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: SwockColors.muted,
      fontFamily: 'monospace',
      fontSize: 11,
      letterSpacing: 1.8,
    ),
  );
}
