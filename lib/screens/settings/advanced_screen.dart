import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/ad_service.dart';
import '../../services/advanced_settings_service.dart';
import '../../services/native_vpn_service.dart';
import '../../theme/swock_widgets.dart';

class AdvancedScreen extends StatefulWidget {
  const AdvancedScreen({super.key});

  @override
  State<AdvancedScreen> createState() => _AdvancedScreenState();
}

class _AdvancedScreenState extends State<AdvancedScreen> {
  final _service = AdvancedSettingsService();
  final _vpn = NativeVpnService();
  AdvancedSettings _settings = const AdvancedSettings();
  bool _loaded = false;
  bool _vpnRunning = false;
  bool _saving = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _service.load().then((settings) {
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loaded = true;
      });
    });
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final status = await _vpn.getStatus();
      if (!mounted) return;
      setState(() => _vpnRunning = status['state'] != 'disconnected');
    } on MissingPluginException {
      // The native bridge is unavailable in widget tests.
    } on PlatformException {
      // Keep the last known state until the next poll.
    }
  }

  Future<void> _update(AdvancedSettings next) async {
    if (_vpnRunning || _saving) return;
    final enabling =
        (!_settings.adaptiveMtu && next.adaptiveMtu) ||
        (!_settings.packetLossPrevention && next.packetLossPrevention) ||
        (!_settings.callStability && next.callStability) ||
        (!_settings.lowLatency && next.lowLatency) ||
        (!_settings.stealthObfuscation && next.stealthObfuscation);
    setState(() {
      _saving = true;
      _settings = next;
    });
    try {
      await _service.save(next);
      if (enabling && mounted) {
        final earned = await AdService.instance.offerTemporaryAdFree(
          context,
          occasion: 'Advanced Settings',
        );
        if (mounted && earned) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ads are paused for 30 minutes.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = _loaded && !_vpnRunning && !_saving;
    return Scaffold(
      backgroundColor: SwockColors.background,
      appBar: AppBar(
        toolbarHeight: 72,
        centerTitle: true,
        title: const Text(
          'ADVANCED',
          style: TextStyle(
            color: SwockColors.green,
            fontFamily: 'monospace',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 4,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SwockCard(
            minHeight: 64,
            child: Row(
              children: [
                Icon(
                  _vpnRunning ? Icons.lock_outline : Icons.tune_rounded,
                  color: _vpnRunning ? SwockColors.amber : SwockColors.green,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _vpnRunning
                        ? 'The VPN is running. Disconnect it to change these options.'
                        : 'These options apply the next time you connect.',
                    style: TextStyle(
                      color:
                          _vpnRunning ? SwockColors.amber : SwockColors.muted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _OptionCard(
            icon: Icons.shield_rounded,
            title: 'Stealth Anti-DPI Obfuscation',
            description:
                'Applies custom cryptographic packet signature randomization '
                'and size obfuscation to bypass strict ISP filtering, Deep Packet Inspection (DPI), '
                'and firewall throttling on restricted networks.',
            value: _settings.stealthObfuscation,
            enabled: editable,
            onChanged:
                (value) =>
                    _update(_settings.copyWith(stealthObfuscation: value)),
          ),
          const SizedBox(height: 10),
          _OptionCard(
            icon: Icons.straighten_rounded,
            title: 'Adaptive MTU',
            description:
                'Sizes the tunnel packets to your current network and connection '
                'type so they are not split on the way. Smoother streaming and '
                'fewer delayed packets while gaming.',
            value: _settings.adaptiveMtu,
            enabled: editable,
            onChanged:
                (value) => _update(_settings.copyWith(adaptiveMtu: value)),
          ),
          const SizedBox(height: 10),
          _OptionCard(
            icon: Icons.alt_route_rounded,
            title: 'Packet-Loss Prevention',
            description:
                'Watches the tunnel for packet loss and automatically switches '
                'to another server route when loss becomes excessive.',
            value: _settings.packetLossPrevention,
            enabled: editable,
            onChanged:
                (value) =>
                    _update(_settings.copyWith(packetLossPrevention: value)),
          ),
          const SizedBox(height: 10),
          _OptionCard(
            icon: Icons.call_outlined,
            title: 'Call Stability Mode',
            description:
                'Prioritizes consistent latency and packet delivery for voice '
                'and video calls. Keeps Wi-Fi in low-latency mode and recovers '
                'a stalled tunnel quickly.',
            value: _settings.callStability,
            enabled: editable,
            onChanged:
                (value) => _update(_settings.copyWith(callStability: value)),
          ),
          const SizedBox(height: 10),
          _OptionCard(
            icon: Icons.bolt_rounded,
            title: 'Low Latency Mode',
            description:
                'Prioritizes latency over maximum throughput. Sends every packet '
                'immediately with smaller buffers. Best for gaming; large '
                'downloads may be slightly slower.',
            value: _settings.lowLatency,
            enabled: editable,
            onChanged:
                (value) => _update(_settings.copyWith(lowLatency: value)),
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: const Duration(milliseconds: 200),
    opacity: enabled ? 1 : .6,
    child: SwockCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (value ? SwockColors.green : SwockColors.faint)
                      .withValues(alpha: .12),
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: value ? SwockColors.green : SwockColors.muted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 15)),
              ),
              Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeThumbColor: SwockColors.green,
                activeTrackColor: SwockColors.green.withValues(alpha: .3),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              color: SwockColors.muted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    ),
  );
}
