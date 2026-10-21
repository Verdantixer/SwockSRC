import 'package:shared_preferences/shared_preferences.dart';

class AdvancedSettings {
  const AdvancedSettings({
    this.adaptiveMtu = false,
    this.packetLossPrevention = false,
    this.callStability = false,
    this.lowLatency = false,
    this.stealthObfuscation = false,
  });

  final bool adaptiveMtu;
  final bool packetLossPrevention;
  final bool callStability;
  final bool lowLatency;
  final bool stealthObfuscation;

  AdvancedSettings copyWith({
    bool? adaptiveMtu,
    bool? packetLossPrevention,
    bool? callStability,
    bool? lowLatency,
    bool? stealthObfuscation,
  }) => AdvancedSettings(
    adaptiveMtu: adaptiveMtu ?? this.adaptiveMtu,
    packetLossPrevention: packetLossPrevention ?? this.packetLossPrevention,
    callStability: callStability ?? this.callStability,
    lowLatency: lowLatency ?? this.lowLatency,
    stealthObfuscation: stealthObfuscation ?? this.stealthObfuscation,
  );

  Map<String, bool> toJson() => {
    'adaptiveMtu': adaptiveMtu,
    'packetLossPrevention': packetLossPrevention,
    'callStability': callStability,
    'lowLatency': lowLatency,
    'stealthObfuscation': stealthObfuscation,
  };
}

class AdvancedSettingsService {
  static const _adaptiveMtuKey = 'advanced_adaptive_mtu';
  static const _packetLossKey = 'advanced_packet_loss_prevention';
  static const _callStabilityKey = 'advanced_call_stability';
  static const _lowLatencyKey = 'advanced_low_latency';
  static const _stealthObfuscationKey = 'advanced_stealth_obfuscation';

  Future<AdvancedSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AdvancedSettings(
      adaptiveMtu: prefs.getBool(_adaptiveMtuKey) ?? false,
      packetLossPrevention: prefs.getBool(_packetLossKey) ?? false,
      callStability: prefs.getBool(_callStabilityKey) ?? false,
      lowLatency: prefs.getBool(_lowLatencyKey) ?? false,
      stealthObfuscation: prefs.getBool(_stealthObfuscationKey) ?? false,
    );
  }

  Future<void> save(AdvancedSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adaptiveMtuKey, settings.adaptiveMtu);
    await prefs.setBool(_packetLossKey, settings.packetLossPrevention);
    await prefs.setBool(_callStabilityKey, settings.callStability);
    await prefs.setBool(_lowLatencyKey, settings.lowLatency);
    await prefs.setBool(_stealthObfuscationKey, settings.stealthObfuscation);
  }
}
