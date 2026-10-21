import 'package:flutter/material.dart';

import '../home/app_tutorial.dart';
import '../../theme/swock_widgets.dart';
import 'advanced_screen.dart';
import 'hotshare_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SwockColors.background,
    appBar: AppBar(
      toolbarHeight: 72,
      centerTitle: true,
      title: const Text(
        'SETTINGS',
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
        const Padding(
          padding: EdgeInsets.only(bottom: 10, left: 2),
          child: SwockHeading('OPTIONS'),
        ),
        _SettingsTile(
          icon: Icons.auto_stories_outlined,
          title: 'App tutorial',
          subtitle: 'Replay the quick guide to VPN time, Hotshare, and rewards',
          onTap: () => showAppTutorial(context),
        ),
        const SizedBox(height: 10),
        _SettingsTile(
          icon: Icons.wifi_tethering,
          title: 'Hotshare',
          subtitle: 'Share your VPN connection through a Wi-Fi hotspot',
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HotshareScreen()),
              ),
        ),
        const SizedBox(height: 10),
        _SettingsTile(
          icon: Icons.tune_rounded,
          title: 'Advanced',
          subtitle:
              'Adaptive MTU, packet-loss prevention, call stability and low latency',
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AdvancedScreen()),
              ),
        ),
      ],
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(7),
    child: SwockCard(
      minHeight: 72,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF163323),
              border: Border.all(
                color: SwockColors.green.withValues(alpha: .5),
              ),
            ),
            child: Icon(icon, color: SwockColors.green, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: SwockColors.muted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: SwockColors.faint),
        ],
      ),
    ),
  );
}
