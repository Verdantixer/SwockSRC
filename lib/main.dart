import 'dart:async';
import 'dart:math' as math;

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
      home: const _StartupGate(),
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _water = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();
  Timer? _timer;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _water.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 320),
    child: _ready
        ? const AppShell(key: ValueKey('app'))
        : Scaffold(
            key: const ValueKey('startup'),
            backgroundColor: const Color(0xFF080B09),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 92,
                    child: AnimatedBuilder(
                      animation: _water,
                      builder: (context, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: CustomPaint(
                          painter: _StartupWaterPainter(_water.value),
                          child: const Icon(
                            Icons.bolt_rounded,
                            color: Color(0xFF55E89A),
                            size: 54,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'SWOCK',
                    style: TextStyle(
                      color: Color(0xFF55E89A),
                      fontFamily: 'monospace',
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SizedBox(
                    width: 78,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: Color(0xFF55E89A),
                      backgroundColor: Color(0xFF26322B),
                    ),
                  ),
                ],
              ),
            ),
          ),
  );
}

class _StartupWaterPainter extends CustomPainter {
  const _StartupWaterPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final level = size.height * (.85 - .5 * progress);
    final path = Path()..moveTo(0, level);
    for (var step = 0; step <= 20; step++) {
      final x = size.width * step / 20;
      path.lineTo(
        x,
        level + math.sin(step / 20 * math.pi * 2 + progress * 4) * 3.5,
      );
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF55E89A).withValues(alpha: .16));
  }

  @override
  bool shouldRepaint(covariant _StartupWaterPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
