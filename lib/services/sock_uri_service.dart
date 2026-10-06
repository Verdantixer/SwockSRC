import 'package:uuid/uuid.dart';

import '../models/vpn_profile.dart';

class SwockUriService {
  static final RegExp _keyPattern = RegExp(r'^[0-9a-f]{64}$');

  static VpnProfile importUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'swock') {
      throw const FormatException('Enter a valid swock:// profile URI.');
    }
    final server = uri.host.trim();
    final port = int.tryParse(uri.queryParameters['port'] ?? '') ?? uri.port;
    final serverPublicKey = (uri.queryParameters['spk'] ?? '').toLowerCase();
    final clientPrivateKey = (uri.queryParameters['cpk'] ?? '').toLowerCase();
    final expiresAt = DateTime.tryParse(uri.queryParameters['exp'] ?? '');
    final requestedTransport = uri.queryParameters['transport'];
    final legacyWebSocket = uri.queryParameters['ws'] == '1';
    final legacyTls = uri.queryParameters['tls'] == '1';
    final transport = TransportMode.values.firstWhere(
      (mode) => mode.name == requestedTransport,
      orElse: () => legacyTls && legacyWebSocket
          ? TransportMode.websocketTls
          : legacyWebSocket
          ? TransportMode.websocket
          : TransportMode.tcp,
    );
    // Transport-aware URIs may omit legacy ws/tls flags. Apply both forms so
    // importing a URI always enables the matching app switches.
    final webSocketEnabled =
        legacyWebSocket ||
        transport == TransportMode.websocket ||
        transport == TransportMode.websocketTls;
    final tlsEnabled =
        legacyTls ||
        transport == TransportMode.websocketTls;
    if (server.isEmpty ||
        port < 1 ||
        port > 65535 ||
        !_keyPattern.hasMatch(serverPublicKey) ||
        !_keyPattern.hasMatch(clientPrivateKey)) {
      throw const FormatException(
        'This Swock profile URI is incomplete or invalid.',
      );
    }
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) {
      throw const FormatException('This Swock profile has expired.');
    }
    final now = DateTime.now();
    return VpnProfile(
      id: const Uuid().v4(),
      name: Uri.decodeComponent(uri.queryParameters['name'] ?? server),
      server: server,
      port: port,
      serverPublicKey: serverPublicKey,
      clientPrivateKey: clientPrivateKey,
      transport: transport,
      webSocket: WebSocketConfig(
        enabled: webSocketEnabled,
        host: uri.queryParameters['wshost'] ?? '',
        path: uri.queryParameters['wspath'] ?? '/',
      ),
      tls: TlsConfig(
        enabled: tlsEnabled,
        sni: uri.queryParameters['sni'] ?? '',
        serverName: uri.queryParameters['sni'] ?? '',
      ),
      dns: DnsConfig(
        enabled: uri.queryParameters['dns'] == '1',
        primary: uri.queryParameters['dns1'] ?? '',
        secondary: uri.queryParameters['dns2'] ?? '',
        tertiary: uri.queryParameters['dns3'] ?? '',
      ),
      metadata: expiresAt == null
          ? ''
          : 'Expires: ${expiresAt.toUtc().toIso8601String()}',
      createdAt: now,
      lastUsedAt: now,
      isSelected: true,
    );
  }
}
