import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vpn_profile.dart';
import '../../services/native_vpn_service.dart';
import '../../services/profile_service.dart';
import '../../services/sock_uri_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _serverController = TextEditingController();
  final _portController = TextEditingController(text: '443');
  final _serverPublicKeyController = TextEditingController();
  final _clientPrivateKeyController = TextEditingController();
  final _nativeVpn = NativeVpnService();
  final _profileService = ProfileService();
  String _state = 'disconnected';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _importPendingUri());
  }

  @override
  void dispose() {
    _serverController.dispose();
    _portController.dispose();
    _serverPublicKeyController.dispose();
    _clientPrivateKeyController.dispose();
    super.dispose();
  }

  Future<void> _toggleConnection() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_state == 'connected' || _state == 'connecting') {
        await _nativeVpn.disconnect();
        if (mounted) setState(() => _state = 'disconnected');
        return;
      }
      final port = int.tryParse(_portController.text.trim());
      final server = _serverController.text.trim();
      final serverPublicKey = _serverPublicKeyController.text
          .trim()
          .toLowerCase();
      final clientPrivateKey = _clientPrivateKeyController.text
          .trim()
          .toLowerCase();
      final keyPattern = RegExp(r'^[0-9a-f]{64}$');
      if (server.isEmpty ||
          port == null ||
          port < 1 ||
          port > 65535 ||
          !keyPattern.hasMatch(serverPublicKey) ||
          !keyPattern.hasMatch(clientPrivateKey)) {
        throw const FormatException(
          'Enter the server, port, and both 64-character X25519 keys.',
        );
      }
      final now = DateTime.now();
      final profile = VpnProfile(
        id: 'quick-connect',
        name: 'Quick connect',
        server: server,
        port: port,
        serverPublicKey: serverPublicKey,
        clientPrivateKey: clientPrivateKey,
        transport: TransportMode.tcp,
        createdAt: now,
        lastUsedAt: now,
      );
      await _nativeVpn.connect(profile);
      if (mounted) setState(() => _state = 'connecting');
    } on FormatException catch (error) {
      if (mounted) _showMessage(error.message);
    } on PlatformException catch (error) {
      if (mounted) _showMessage(error.message ?? 'VPN connection failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importProfile() async {
    final controller = TextEditingController();
    final uri = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Swock profile'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(hintText: 'swock://…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (uri == null || uri.trim().isEmpty) return;
    await _saveImportedProfile(uri);
  }

  Future<void> _importPendingUri() async {
    final uri = await _nativeVpn.getImportUri();
    if (uri != null && uri.trim().isNotEmpty) await _saveImportedProfile(uri);
  }

  Future<void> _saveImportedProfile(String uri) async {
    try {
      final profile = SwockUriService.importUri(uri);
      await _profileService.addProfile(profile);
      _serverController.text = profile.server;
      _portController.text = profile.port.toString();
      _serverPublicKeyController.text = profile.serverPublicKey;
      _clientPrivateKeyController.text = profile.clientPrivateKey;
      if (mounted) {
        _showMessage('Profile imported. Tap Connect to start the VPN.');
      }
    } on FormatException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(error.message ?? 'Could not import the Swock profile.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _state == 'connected';
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NPV TUNNEL',
              style: TextStyle(
                color: accent,
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'SWOCK VPN',
              style: TextStyle(
                color: Color(0xFF8B958E),
                fontFamily: 'monospace',
                fontSize: 10,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _importProfile,
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Import Swock URI',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
        children: [
          Text(
            'PROFILE',
            style: TextStyle(
              color: accent,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'State',
                style: TextStyle(color: Color(0xFFA7B0AA), fontSize: 15),
              ),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: connected ? accent : const Color(0xFF77817A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _state.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFFE2E8E4),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _serverController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Server host or IP'),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _serverPublicKeyController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Server public key (X25519 hex)',
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _clientPrivateKeyController,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Client private key (X25519 hex)',
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8),
            child: Text(
              'Keep this key private.',
              style: TextStyle(color: Color(0xFFA7B0AA), fontSize: 12),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Server port'),
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFF39413B), height: 1),
          const SizedBox(height: 18),
          const _ProtocolSummary(),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _busy ? null : _toggleConnection,
              icon: Icon(connected ? Icons.stop : Icons.power_settings_new),
              label: Text(connected ? 'Disconnect' : 'Connect'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: const Color(0xFF07120B),
                disabledBackgroundColor: const Color(0xFF3A4540),
                disabledForegroundColor: const Color(0xFF9AA49D),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtocolSummary extends StatelessWidget {
  const _ProtocolSummary();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProtocolRow(label: 'Transport', value: 'TCP'),
        SizedBox(height: 14),
        _ProtocolRow(label: 'Encryption', value: 'X25519 + ChaCha20-Poly1305'),
      ],
    );
  }
}

class _ProtocolRow extends StatelessWidget {
  const _ProtocolRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFA7B0AA), fontSize: 14),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Color(0xFFE2E8E4), fontSize: 14),
          ),
        ),
      ],
    );
  }
}
