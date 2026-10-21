import 'dart:convert';
import 'package:uuid/uuid.dart';

import '../models/vpn_profile.dart';

class SwockUriService {
  static final RegExp _keyPattern = RegExp(r'^[0-9a-f]{64}$');

  static VpnProfile importUri(String value) {
    final trimmed = value.trim();
    final lower = trimmed.toLowerCase();

    if (lower.startsWith('trojan://')) {
      return _importTrojanUri(trimmed);
    } else if (lower.startsWith('vless://')) {
      return _importVlessUri(trimmed);
    } else if (lower.startsWith('vmess://')) {
      return _importVmessUri(trimmed);
    } else if (lower.startsWith('ss://') || lower.startsWith('shadowsocks://')) {
      return _importShadowsocksUri(trimmed);
    } else if (lower.startsWith('swock://')) {
      return _importSwockUri(trimmed);
    }

    throw const FormatException('Enter a valid swock://, trojan://, vless://, vmess://, or ss:// profile URI.');
  }

  static VpnProfile _importSwockUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) throw const FormatException('Enter a valid swock:// profile URI.');
    final server = uri.host.trim();
    var port = int.tryParse(uri.queryParameters['port'] ?? '') ?? uri.port;
    if (port <= 0) port = 443;
    final serverPublicKey = (uri.queryParameters['spk'] ?? '').toLowerCase();
    final clientPrivateKey = (uri.queryParameters['cpk'] ?? '').toLowerCase();
    final tunnelAddress = (uri.queryParameters['ip'] ?? '').trim();
    final expiresAt = DateTime.tryParse(uri.queryParameters['exp'] ?? '');
    final requestedTransport = uri.queryParameters['transport'];
    final legacyWebSocket = uri.queryParameters['ws'] == '1';
    final legacyTls = uri.queryParameters['tls'] == '1';
    final transport = TransportMode.values.firstWhere(
      (mode) => mode.name == requestedTransport,
      orElse:
          () =>
              legacyTls && legacyWebSocket
                  ? TransportMode.websocketTls
                  : legacyWebSocket
                  ? TransportMode.websocket
                  : TransportMode.tcp,
    );
    final webSocketEnabled =
        legacyWebSocket ||
        transport == TransportMode.websocket ||
        transport == TransportMode.websocketTls;
    final tlsEnabled = legacyTls || transport == TransportMode.websocketTls;

    if (tlsEnabled && port == 80) port = 443;

    final sniParam = (uri.queryParameters['sni'] ?? '').trim();
    final wsHostParam = (uri.queryParameters['wshost'] ?? '').trim();
    final effectiveSni = sniParam.isNotEmpty ? sniParam : wsHostParam;
    final effectiveWsHost = wsHostParam.isNotEmpty ? wsHostParam : sniParam;

    if (server.isEmpty ||
        port < 1 ||
        port > 65535 ||
        !_keyPattern.hasMatch(serverPublicKey) ||
        !_keyPattern.hasMatch(clientPrivateKey)) {
      throw const FormatException('This Swock profile URI is incomplete or invalid.');
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
      protocol: VpnProtocol.swock,
      serverPublicKey: serverPublicKey,
      clientPrivateKey: clientPrivateKey,
      tunnelAddress: tunnelAddress,
      transport: transport,
      webSocket: WebSocketConfig(
        enabled: webSocketEnabled,
        host: effectiveWsHost,
        path: uri.queryParameters['wspath'] ?? '/',
      ),
      tls: TlsConfig(
        enabled: tlsEnabled,
        sni: effectiveSni,
        serverName: effectiveSni,
      ),
      dns: DnsConfig(
        enabled: uri.queryParameters['dns'] == '1',
        primary: uri.queryParameters['dns1'] ?? '',
        secondary: uri.queryParameters['dns2'] ?? '',
        tertiary: uri.queryParameters['dns3'] ?? '',
      ),
      metadata: expiresAt == null ? '' : 'Expires: ${expiresAt.toUtc().toIso8601String()}',
      createdAt: now,
      lastUsedAt: now,
      isSelected: true,
    );
  }

  static VpnProfile _importTrojanUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) throw const FormatException('Invalid trojan:// URI');
    final password = uri.userInfo;
    final server = uri.host;
    var port = uri.port > 0 ? uri.port : 443;
    final name = uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : 'Trojan-$server';
    final sni = (uri.queryParameters['sni'] ?? uri.queryParameters['peer'] ?? '').trim();
    final wsHost = (uri.queryParameters['host'] ?? sni).trim();
    final wsPath = Uri.decodeComponent(uri.queryParameters['path'] ?? '/');
    final type = uri.queryParameters['type'] ?? uri.queryParameters['headerType'] ?? 'ws';
    final security = uri.queryParameters['security'] ?? 'tls';
    final isTls = security == 'tls';
    final isWs = type == 'ws';

    if (isTls && port == 80) port = 443;

    final now = DateTime.now();
    return VpnProfile(
      id: const Uuid().v4(),
      name: name,
      server: server,
      port: port,
      protocol: VpnProtocol.trojan,
      password: password,
      transport: isWs && isTls ? TransportMode.websocketTls : (isWs ? TransportMode.websocket : TransportMode.tcp),
      webSocket: WebSocketConfig(
        enabled: isWs,
        host: wsHost.isNotEmpty ? wsHost : sni,
        path: wsPath.isNotEmpty ? wsPath : '/',
      ),
      tls: TlsConfig(
        enabled: isTls,
        sni: sni.isNotEmpty ? sni : wsHost,
        serverName: sni.isNotEmpty ? sni : wsHost,
        allowInsecureCertificate: uri.queryParameters['allowInsecure'] == '1',
      ),
      createdAt: now,
      lastUsedAt: now,
      isSelected: true,
    );
  }

  static VpnProfile _importVlessUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) throw const FormatException('Invalid vless:// URI');
    final uuid = uri.userInfo;
    final server = uri.host;
    var port = uri.port > 0 ? uri.port : 443;
    final name = uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : 'VLESS-$server';
    final sni = (uri.queryParameters['sni'] ?? '').trim();
    final wsHost = (uri.queryParameters['host'] ?? sni).trim();
    final wsPath = Uri.decodeComponent(uri.queryParameters['path'] ?? '/');
    final flow = uri.queryParameters['flow'] ?? '';
    final type = uri.queryParameters['type'] ?? 'ws';
    final security = uri.queryParameters['security'] ?? 'tls';
    final isTls = security == 'tls';
    final isWs = type == 'ws';

    if (isTls && port == 80) port = 443;

    final now = DateTime.now();
    return VpnProfile(
      id: const Uuid().v4(),
      name: name,
      server: server,
      port: port,
      protocol: VpnProtocol.vless,
      uuid: uuid,
      flow: flow,
      transport: isWs && isTls ? TransportMode.websocketTls : (isWs ? TransportMode.websocket : TransportMode.tcp),
      webSocket: WebSocketConfig(
        enabled: isWs,
        host: wsHost.isNotEmpty ? wsHost : sni,
        path: wsPath.isNotEmpty ? wsPath : '/',
      ),
      tls: TlsConfig(
        enabled: isTls,
        sni: sni.isNotEmpty ? sni : wsHost,
        serverName: sni.isNotEmpty ? sni : wsHost,
      ),
      createdAt: now,
      lastUsedAt: now,
      isSelected: true,
    );
  }

  static VpnProfile _importVmessUri(String value) {
    try {
      final raw = value.substring('vmess://'.length).trim();
      final decoded = utf8.decode(base64.decode(base64.normalize(raw)));
      final map = jsonDecode(decoded) as Map<String, dynamic>;

      final name = map['ps'] as String? ?? 'VMess-Server';
      final server = map['add'] as String? ?? '';
      var port = int.tryParse(map['port']?.toString() ?? '') ?? 443;
      final uuid = map['id'] as String? ?? '';
      final alterId = int.tryParse(map['aid']?.toString() ?? '') ?? 0;
      final net = map['net'] as String? ?? 'ws';
      final tls = map['tls'] as String? ?? '';
      final host = map['host'] as String? ?? '';
      final path = map['path'] as String? ?? '/';
      final sni = map['sni'] as String? ?? host;
      final isTls = tls == 'tls';
      final isWs = net == 'ws';

      if (isTls && port == 80) port = 443;

      final now = DateTime.now();
      return VpnProfile(
        id: const Uuid().v4(),
        name: name,
        server: server,
        port: port,
        protocol: VpnProtocol.vmess,
        uuid: uuid,
        alterId: alterId,
        transport: isWs && isTls ? TransportMode.websocketTls : (isWs ? TransportMode.websocket : TransportMode.tcp),
        webSocket: WebSocketConfig(
          enabled: isWs,
          host: host.isNotEmpty ? host : sni,
          path: path.isNotEmpty ? path : '/',
        ),
        tls: TlsConfig(
          enabled: isTls,
          sni: sni.isNotEmpty ? sni : host,
          serverName: sni.isNotEmpty ? sni : host,
        ),
        createdAt: now,
        lastUsedAt: now,
        isSelected: true,
      );
    } catch (_) {
      throw const FormatException('Invalid vmess:// URI format');
    }
  }

  static VpnProfile _importShadowsocksUri(String value) {
    try {
      final uri = Uri.parse(value);
      final name = uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : 'SS-${uri.host}';
      final server = uri.host;
      final port = uri.port > 0 ? uri.port : 8388;
      String cipher = 'aes-256-gcm';
      String password = '';

      if (uri.userInfo.isNotEmpty) {
        if (uri.userInfo.contains(':')) {
          final parts = uri.userInfo.split(':');
          cipher = parts[0];
          password = parts[1];
        } else {
          final decoded = utf8.decode(base64.decode(base64.normalize(uri.userInfo)));
          if (decoded.contains(':')) {
            final parts = decoded.split(':');
            cipher = parts[0];
            password = parts[1];
          }
        }
      }

      final now = DateTime.now();
      return VpnProfile(
        id: const Uuid().v4(),
        name: name,
        server: server,
        port: port,
        protocol: VpnProtocol.shadowsocks,
        cipher: cipher,
        password: password,
        createdAt: now,
        lastUsedAt: now,
        isSelected: true,
      );
    } catch (_) {
      throw const FormatException('Invalid ss:// URI format');
    }
  }
}
