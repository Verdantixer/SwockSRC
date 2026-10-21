import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/time_bank_service.dart';
import '../../theme/swock_widgets.dart';

class TimerCard extends StatelessWidget {
  const TimerCard({
    super.key,
    required this.remaining,
    required this.counting,
    required this.message,
  });

  final Duration remaining;
  final bool counting;
  final String message;

  Color get _color {
    if (remaining == Duration.zero) return SwockColors.red;
    if (!counting) return SwockColors.ink;
    if (remaining <= const Duration(minutes: 1)) return SwockColors.red;
    if (remaining <= const Duration(minutes: 10)) return SwockColors.amber;
    return SwockColors.ink;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return SwockCard(
      minHeight: 56,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.timer_outlined,
              color: color.withValues(alpha: .85),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Timer: ${formatTimer(remaining)}',
                    style: TextStyle(
                      color: color,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: .4,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SwockColors.muted,
                    fontSize: 9,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AddTimeButton extends StatefulWidget {
  const AddTimeButton({
    super.key,
    required this.onPressed,
    required this.cooldownSeconds,
    required this.busy,
    this.attention = false,
  });

  final VoidCallback onPressed;
  final int cooldownSeconds;
  final bool busy;
  final bool attention;

  @override
  State<AddTimeButton> createState() => _AddTimeButtonState();
}

class _AddTimeButtonState extends State<AddTimeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat();
  bool _pressed = false;

  bool get _enabled => widget.cooldownSeconds <= 0 && !widget.busy;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        widget.busy
            ? 'LOADING'
            : widget.cooldownSeconds > 0
            ? 'WAIT ${widget.cooldownSeconds}s'
            : 'AD TO SPIN';
    return AnimatedScale(
      scale: _pressed && _enabled ? .95 : 1,
      duration: const Duration(milliseconds: 110),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: _enabled ? widget.onPressed : null,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final wave = (math.sin(_pulse.value * math.pi * 2) + 1) / 2;
            final glow = widget.attention ? 1.0 : .55;
            return Container(
              width: 112,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                boxShadow:
                    _enabled
                        ? [
                          BoxShadow(
                            color: SwockColors.green.withValues(
                              alpha: (.10 + .16 * wave) * glow,
                            ),
                            blurRadius: 8 + 8 * wave,
                          ),
                        ]
                        : const [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors:
                              _enabled
                                  ? const [Color(0xFF0E7C58), Color(0xFF075F63)]
                                  : const [
                                    Color(0xFF1B231E),
                                    Color(0xFF161C18),
                                  ],
                        ),
                      ),
                    ),
                    if (_enabled)
                      Positioned.fill(
                        child: OverflowBox(
                          maxHeight: 240,
                          alignment: Alignment(-1.6 + 3.2 * _pulse.value, 0),
                          child: Transform.rotate(
                            angle: .35,
                            child: Container(
                              width: 26,
                              height: 240,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: .10),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color:
                              _enabled
                                  ? SwockColors.green.withValues(alpha: .55)
                                  : SwockColors.line,
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          widget.busy
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: SwockColors.green,
                                ),
                              )
                              : Transform.rotate(
                                angle:
                                    _enabled
                                        ? math.sin(_pulse.value * math.pi * 2) *
                                            .12
                                        : 0,
                                child: Icon(
                                  Icons.add_alarm_rounded,
                                  size: 18,
                                  color:
                                      _enabled
                                          ? const Color(0xFFD9FFEF)
                                          : SwockColors.faint,
                                ),
                              ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              color:
                                  _enabled
                                      ? const Color(0xFFD9FFEF)
                                      : SwockColors.muted,
                              fontFamily: 'monospace',
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Spins to [reward], announces it, then closes itself and returns it.
class RewardWheelDialog extends StatefulWidget {
  const RewardWheelDialog({super.key});

  static final segments = List<TimeReward>.unmodifiable(
    List.generate(TimeReward.wheelSize, TimeReward.atWheelIndex),
  );

  @override
  State<RewardWheelDialog> createState() => _RewardWheelDialogState();
}

class _RewardWheelDialogState extends State<RewardWheelDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5400),
  );
  late final Animation<double> _eased = CurvedAnimation(
    parent: _spin,
    curve: Curves.easeOutQuart,
  );
  late final int _selectedIndex;
  late final TimeReward _reward;
  late final double _target;
  Timer? _closeTimer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final random = math.Random.secure();
    _selectedIndex = TimeReward.drawWheelIndex(random);
    _reward = TimeReward.atWheelIndex(_selectedIndex);
    final slice = 2 * math.pi / RewardWheelDialog.segments.length;
    // A Dart canvas arc starts at 3 o'clock; this aligns the chosen wedge
    // center with the fixed pointer at 12 o'clock after the eased spin.
    _target = 2 * math.pi * 6 - (_selectedIndex + .5) * slice;
    _spin.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _finished = true);
      _closeTimer = Timer(const Duration(milliseconds: 2400), () {
        if (mounted) Navigator.of(context).pop(_reward);
      });
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _spin.dispose();
    super.dispose();
  }

  bool get _jackpot => _reward.duration >= const Duration(days: 1);

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      backgroundColor: const Color(0xFF101713),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF345341)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SPIN FOR TIME',
              style: TextStyle(
                color: SwockColors.green,
                fontFamily: 'monospace',
                letterSpacing: 2.4,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'One rewarded video unlocks one spin. The prize goes to your VPN timer.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SwockColors.muted,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 260,
              height: 276,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: 16,
                    child: AnimatedBuilder(
                      animation: _eased,
                      builder:
                          (context, _) => CustomPaint(
                            size: const Size.square(260),
                            painter: _WheelPainter(
                              angle: _eased.value * _target,
                              segments: RewardWheelDialog.segments,
                            ),
                          ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 52,
                    color: Color(0xFFFFD45C),
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '5 min 45%  ·  15 min 33%  ·  1 hr 20%  ·  1 day 1%  ·  24 days 1%',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SwockColors.faint,
                fontFamily: 'monospace',
                fontSize: 9,
              ),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder:
                  (child, animation) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
              child:
                  _finished
                      ? Text(
                        'You won ${_reward.label}!',
                        key: const ValueKey('won'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              _jackpot
                                  ? const Color(0xFFFFD45C)
                                  : SwockColors.green,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                      : const Text(
                        'Spinning…',
                        key: ValueKey('spinning'),
                        style: TextStyle(
                          color: SwockColors.muted,
                          fontSize: 15,
                        ),
                      ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter({required this.angle, required this.segments});

  final double angle;
  final List<TimeReward> segments;

  static Color _fill(TimeReward reward) =>
      reward.duration >= const Duration(days: 1)
          ? const Color(0xFF8A6A10)
          : reward.duration >= const Duration(hours: 1)
          ? const Color(0xFF0A6F70)
          : reward.duration >= const Duration(minutes: 15)
          ? const Color(0xFF0E5A4B)
          : const Color(0xFF123D2C);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    final slice = 2 * math.pi / segments.length;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius + 6,
      Paint()
        ..color = SwockColors.green.withValues(alpha: .18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    for (var i = 0; i < segments.length; i++) {
      final start = -math.pi / 2 + angle + i * slice;
      canvas.drawArc(
        rect,
        start,
        slice,
        true,
        Paint()..color = _fill(segments[i]),
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = SwockColors.green.withValues(alpha: .85),
    );
    canvas.drawCircle(center, 22, Paint()..color = const Color(0xFF080B09));
    canvas.drawCircle(
      center,
      22,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = SwockColors.green,
    );
    canvas.drawCircle(center, 6, Paint()..color = SwockColors.green);
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => oldDelegate.angle != angle;
}

/// Asks the user to add time; resolves true to add time, false to disconnect.
class TimeUpDialog extends StatefulWidget {
  const TimeUpDialog({super.key, required this.initialCooldownSeconds});

  final int initialCooldownSeconds;

  @override
  State<TimeUpDialog> createState() => _TimeUpDialogState();
}

class _TimeUpDialogState extends State<TimeUpDialog> {
  static const _grace = 30;
  int _left = _grace;
  late int _cooldown = widget.initialCooldownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _timer?.cancel();
        Navigator.of(context).pop(false);
      } else {
        setState(() {
          _left--;
          if (_cooldown > 0) _cooldown--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      backgroundColor: const Color(0xFF101713),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF53403A)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SwockColors.red.withValues(alpha: .12),
                border: Border.all(
                  color: SwockColors.red.withValues(alpha: .5),
                ),
              ),
              child: const Icon(
                Icons.timer_off_outlined,
                color: SwockColors.red,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "TIME'S UP",
              style: TextStyle(
                color: SwockColors.red,
                fontFamily: 'monospace',
                letterSpacing: 2.2,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Add more VPN time to stay connected.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'The VPN disconnects in ${_left}s unless you add time.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: SwockColors.muted, height: 1.45),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _cooldown == 0
                        ? () => Navigator.of(context).pop(true)
                        : null,
                icon: const Icon(Icons.add_alarm_rounded),
                label: Text(
                  _cooldown == 0 ? 'ADD + TIME' : 'WAIT ${_cooldown}s',
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    ),
  );
}
