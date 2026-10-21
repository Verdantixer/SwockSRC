import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/home/app_shell.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const SwockApp());
}

class SwockApp extends StatelessWidget {
  const SwockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swock',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const _LaunchGate(),
    );
  }
}

class _LaunchGate extends StatefulWidget {
  const _LaunchGate();

  @override
  State<_LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<_LaunchGate> {
  Timer? _timer;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1450), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 520),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .025),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: _showSplash
        ? const _BrandSplash(key: ValueKey('splash'))
        : const AppShell(key: ValueKey('app')),
  );
}

class _BrandSplash extends StatelessWidget {
  const _BrandSplash({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080B09),
    body: Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: .78, end: 1),
        duration: const Duration(milliseconds: 780),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Opacity(
          opacity: ((scale - .78) / .22).clamp(0, 1),
          child: Transform.scale(scale: scale, child: child),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF55E89A).withValues(alpha: .08),
                border: Border.all(
                  color: const Color(0xFF55E89A).withValues(alpha: .48),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF55E89A).withValues(alpha: .18),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.shield_moon_rounded,
                size: 54,
                color: Color(0xFF79F2B2),
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              'SWOCK',
              style: TextStyle(
                color: Color(0xFF79F2B2),
                fontFamily: 'monospace',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'PRIVATE CONNECTION',
              style: TextStyle(
                color: Color(0xFFA7B0AA),
                fontFamily: 'monospace',
                fontSize: 10,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 112,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1150),
                curve: Curves.easeInOutCubic,
                builder: (context, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 2,
                    backgroundColor: const Color(0xFF27312B),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF55E89A)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
