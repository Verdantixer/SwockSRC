import 'dart:convert';

enum VpnProtocol { shadowsocks, swock, vless, vmess, trojan }

enum TransportMode { auto, tcp, websocket, websocketTls }

enum ProxyType { none, http, socks5 }

enum DnsMode { system, custom }

enum KeyExchangeProtocol { curve25519 }

enum CipherSuite { chacha20Poly1305, chacha20IetfPoly1305 }

class EncryptionConfig {
  final KeyExchangeProtocol keyExchange;
  final CipherSuite cipherSuite;
  final bool endToEndEncrypted;
  final bool requiresCertificatePinning;

  const EncryptionConfig({
    this.keyExchange = KeyExchangeProtocol.curve25519,
    this.cipherSuite = CipherSuite.chacha20Poly1305,
    this.endToEndEncrypted = true,
    this.requiresCertificatePinning = false,
  });

  factory EncryptionConfig.fromJson(Map<String, dynamic> json) {
    return EncryptionConfig(
      keyExchange: KeyExchangeProtocol.values.firstWhere(
        (element) =>
            element.name == (json['keyExchange'] as String? ?? 'curve25519'),
        orElse: () => KeyExchangeProtocol.curve25519,
      ),
      cipherSuite: CipherSuite.values.firstWhere(
        (element) =>
            element.name ==
            (json['cipherSuite'] as String? ?? 'chacha20Poly1305'),
        orElse: () => CipherSuite.chacha20Poly1305,
      ),
      endToEndEncrypted: json['endToEndEncrypted'] as bool? ?? true,
      requiresCertificatePinning:
          json['requiresCertificatePinning'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'keyExchange': keyExchange.name,
    'cipherSuite': cipherSuite.name,
    'endToEndEncrypted': endToEndEncrypted,
    'requiresCertificatePinning': requiresCertificatePinning,
  };
}

class WebSocketConfig {
  final bool enabled;
  final String path;
  final String host;
  final Map<String, String> headers;
  final Map<String, String> connectionOptions;

  const WebSocketConfig({
    this.enabled = false,
    this.path = '/',
    this.host = '',
    this.headers = const {},
    this.connectionOptions = const {},
  });

  factory WebSocketConfig.fromJson(Map<String, dynamic> json) {
    return WebSocketConfig(
      enabled: json['enabled'] as bool? ?? false,
      path: (json['path'] as String?) ?? '/',
      host: (json['host'] as String?) ?? '',
      headers: Map<String, String>.from((json['headers'] as Map?) ?? const {}),
      connectionOptions: Map<String, String>.from(
        (json['connectionOptions'] as Map?) ?? const {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'path': path,
    'host': host,
    'headers': headers,
    'connectionOptions': connectionOptions,
  };
}

class TlsConfig {
  final bool enabled;
  final String sni;
  final bool allowInsecureCertificate;
  final String serverName;
  final List<String> alpn;

  const TlsConfig({
    this.enabled = false,
    this.sni = '',
    this.allowInsecureCertificate = false,
    this.serverName = '',
    this.alpn = const [],
  });

  factory TlsConfig.fromJson(Map<String, dynamic> json) {
    return TlsConfig(
      enabled: json['enabled'] as bool? ?? false,
      sni: json['sni'] as String? ?? '',
      allowInsecureCertificate:
          json['allowInsecureCertificate'] as bool? ?? false,
      serverName: json['serverName'] as String? ?? '',
      alpn: List<String>.from((json['alpn'] as List?) ?? const []),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'sni': sni,
    'allowInsecureCertificate': allowInsecureCertificate,
    'serverName': serverName,
    'alpn': alpn,
  };
}

class ProxyConfig {
  final ProxyType type;
  final String host;
  final int port;
  final String username;
  final String password;

  const ProxyConfig({
    this.type = ProxyType.none,
    this.host = '',
    this.port = 0,
    this.username = '',
    this.password = '',
  });

  factory ProxyConfig.fromJson(Map<String, dynamic> json) {
    return ProxyConfig(
      type: ProxyType.values.firstWhere(
        (element) => element.name == (json['type'] as String? ?? 'none'),
        orElse: () => ProxyType.none,
      ),
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
  };
}

class DnsConfig {
  final bool enabled;
  final DnsMode mode;
  final String primary;
  final String secondary;
  final String tertiary;

  const DnsConfig({
    this.enabled = false,
    this.mode = DnsMode.system,
    this.primary = '',
    this.secondary = '',
    this.tertiary = '',
  });

  factory DnsConfig.fromJson(Map<String, dynamic> json) {
    return DnsConfig(
      enabled: json['enabled'] as bool? ?? false,
      mode: DnsMode.values.firstWhere(
        (element) => element.name == (json['mode'] as String? ?? 'system'),
        orElse: () => DnsMode.system,
      ),
      primary: json['primary'] as String? ?? '',
      secondary: json['secondary'] as String? ?? '',
      tertiary: json['tertiary'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'primary': primary,
    'secondary': secondary,
    'tertiary': tertiary,
  };
}

class VpnProfile {
  final String id;
  final String name;
  final String server;
  final int port;
  final String serverPublicKey;
  final String clientPrivateKey;
  final String tunnelAddress;
  final String uuid;
  final int alterId;
  final String flow;
  final String security;
  final VpnProtocol protocol;
  final String cipher;
  final String password;
  final TransportMode transport;
  final WebSocketConfig webSocket;
  final TlsConfig tls;
  final ProxyConfig proxy;
  final DnsConfig dns;
  final EncryptionConfig encryption;
  final String metadata;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final bool favorite;
  final String? notes;
  final bool isSelected;

  const VpnProfile({
    required this.id,
    required this.name,
    required this.server,
    required this.port,
    this.serverPublicKey = '',
    this.clientPrivateKey = '',
    this.tunnelAddress = '',
    this.uuid = '',
    this.alterId = 0,
    this.flow = '',
    this.security = 'auto',
    this.protocol = VpnProtocol.swock,
    this.cipher = 'chacha20-poly1305',
    this.password = '',
    this.transport = TransportMode.auto,
    this.webSocket = const WebSocketConfig(),
    this.tls = const TlsConfig(),
    this.proxy = const ProxyConfig(),
    this.dns = const DnsConfig(),
    this.encryption = const EncryptionConfig(),
    this.metadata = '',
    required this.createdAt,
    required this.lastUsedAt,
    this.favorite = false,
    this.notes,
    this.isSelected = false,
  });

  bool get hasValidServer => server.trim().isNotEmpty;
  bool get hasValidPort => port > 0 && port <= 65535;

  VpnProfile copyWith({
    String? id,
    String? name,
    String? server,
    int? port,
    String? serverPublicKey,
    String? clientPrivateKey,
    String? tunnelAddress,
    String? uuid,
    int? alterId,
    String? flow,
    String? security,
    VpnProtocol? protocol,
    String? cipher,
    String? password,
    TransportMode? transport,
    WebSocketConfig? webSocket,
    TlsConfig? tls,
    ProxyConfig? proxy,
    DnsConfig? dns,
    EncryptionConfig? encryption,
    String? metadata,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    bool? favorite,
    String? notes,
    bool? isSelected,
  }) {
    return VpnProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      server: server ?? this.server,
      port: port ?? this.port,
      serverPublicKey: serverPublicKey ?? this.serverPublicKey,
      clientPrivateKey: clientPrivateKey ?? this.clientPrivateKey,
      tunnelAddress: tunnelAddress ?? this.tunnelAddress,
      uuid: uuid ?? this.uuid,
      alterId: alterId ?? this.alterId,
      flow: flow ?? this.flow,
      security: security ?? this.security,
      protocol: protocol ?? this.protocol,
      cipher: cipher ?? this.cipher,
      password: password ?? this.password,
      transport: transport ?? this.transport,
      webSocket: webSocket ?? this.webSocket,
      tls: tls ?? this.tls,
      proxy: proxy ?? this.proxy,
      dns: dns ?? this.dns,
      encryption: encryption ?? this.encryption,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      favorite: favorite ?? this.favorite,
      notes: notes ?? this.notes,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  factory VpnProfile.fromJson(Map<String, dynamic> json) {
    return VpnProfile(
      id:
          json['id'] as String? ??
          base64Url.encode(utf8.encode(DateTime.now().toIso8601String())),
      name: json['name'] as String? ?? 'Unnamed profile',
      server: json['server'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 443,
      serverPublicKey: json['serverPublicKey'] as String? ?? '',
      clientPrivateKey: json['clientPrivateKey'] as String? ?? '',
      tunnelAddress: json['tunnelAddress'] as String? ?? '',
      uuid: json['uuid'] as String? ?? '',
      alterId: (json['alterId'] as num?)?.toInt() ?? 0,
      flow: json['flow'] as String? ?? '',
      security: json['security'] as String? ?? 'auto',
      protocol: VpnProtocol.values.firstWhere(
        (element) =>
            element.name == (json['protocol'] as String? ?? 'swock'),
        orElse: () => VpnProtocol.swock,
      ),
      cipher: json['cipher'] as String? ?? 'chacha20-poly1305',
      password: json['password'] as String? ?? '',
      transport: TransportMode.values.firstWhere(
        (element) => element.name == (json['transport'] as String? ?? 'auto'),
        orElse: () => TransportMode.auto,
      ),
      webSocket:
          json['webSocket'] is Map
              ? WebSocketConfig.fromJson(json['webSocket'])
              : const WebSocketConfig(),
      tls:
          json['tls'] is Map
              ? TlsConfig.fromJson(json['tls'])
              : const TlsConfig(),
      proxy:
          json['proxy'] is Map
              ? ProxyConfig.fromJson(json['proxy'])
              : const ProxyConfig(),
      dns:
          json['dns'] is Map
              ? DnsConfig.fromJson(json['dns'])
              : const DnsConfig(),
      encryption:
          json['encryption'] is Map
              ? EncryptionConfig.fromJson(json['encryption'])
              : const EncryptionConfig(),
      metadata: json['metadata'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      lastUsedAt:
          DateTime.tryParse(json['lastUsedAt'] as String? ?? '') ??
          DateTime.now(),
      favorite: json['favorite'] as bool? ?? false,
      notes: json['notes'] as String?,
      isSelected: json['isSelected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'server': server,
    'port': port,
    'serverPublicKey': serverPublicKey,
    'clientPrivateKey': clientPrivateKey,
    'tunnelAddress': tunnelAddress,
    'uuid': uuid,
    'alterId': alterId,
    'flow': flow,
    'security': security,
    'protocol': protocol.name,
    'cipher': cipher,
    'password': password,
    'transport': transport.name,
    'webSocket': webSocket.toJson(),
    'tls': tls.toJson(),
    'proxy': proxy.toJson(),
    'dns': dns.toJson(),
    'encryption': encryption.toJson(),
    'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
    'lastUsedAt': lastUsedAt.toIso8601String(),
    'favorite': favorite,
    'notes': notes,
    'isSelected': isSelected,
  };
}
