import 'package:flutter/services.dart';

class HotshareStatus {
  const HotshareStatus({
    this.state = 'stopped',
    this.message = 'Hotshare is off',
    this.ssid = '',
    this.password = '',
    this.host = '',
    this.port = HotshareService.port,
    this.clients = 0,
    this.bytes = 0,
  });

  factory HotshareStatus.fromMap(Map<String, dynamic> map) => HotshareStatus(
    state: map['state'] as String? ?? 'stopped',
    message: map['message'] as String? ?? '',
    ssid: map['ssid'] as String? ?? '',
    password: map['password'] as String? ?? '',
    host: map['host'] as String? ?? '',
    port: (map['port'] as num?)?.toInt() ?? HotshareService.port,
    clients: (map['clients'] as num?)?.toInt() ?? 0,
    bytes: (map['bytes'] as num?)?.toInt() ?? 0,
  );

  final String state;
  final String message;
  final String ssid;
  final String password;
  final String host;
  final int port;
  final int clients;
  final int bytes;

  bool get isRunning => state == 'running';
  bool get isStarting => state == 'starting';
  bool get isActive => isRunning || isStarting;
}

class HotshareService {
  HotshareService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.swock.vpn/channel');

  /// Hotspot credentials are fixed; Android prefixes the network name with `DIRECT-sw-`.
  static const name = 'SwockSpot';
  static const ssid = 'DIRECT-sw-$name';
  static const password = 'swocker123';
  static const port = 8080;

  final MethodChannel _channel;

  Future<bool> requestPermissions() async =>
      await _channel.invokeMethod<bool>('hotspotRequestPermissions') ?? false;

  Future<void> start() => _channel.invokeMethod<void>(
    'hotspotStart',
    <String, dynamic>{'name': name, 'password': password, 'port': port},
  );

  Future<void> stop() => _channel.invokeMethod<void>('hotspotStop');

  Future<HotshareStatus> status() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'hotspotStatus',
    );
    return result == null
        ? const HotshareStatus()
        : HotshareStatus.fromMap(result);
  }
}
