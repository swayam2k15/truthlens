import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/crypto/key_manager.dart';

/// Settings screen for configuring TruthLens behavior.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _settingsBox = Hive.box('truthlens_settings');
  String? _publicKey;

  @override
  void initState() {
    super.initState();
    _loadPublicKey();
  }

  Future<void> _loadPublicKey() async {
    final key = await KeyManager.instance.getPublicKeyBase64();
    setState(() => _publicKey = key);
  }

  bool _getSetting(String key, {bool defaultValue = true}) {
    return _settingsBox.get(key, defaultValue: defaultValue) as bool;
  }

  Future<void> _setSetting(String key, bool value) async {
    await _settingsBox.put(key, value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Identity section
          _SectionHeader('Identity'),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Device ID'),
            subtitle: Text(
              KeyManager.instance.deviceId,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: KeyManager.instance.deviceId));
                _showSnack('Device ID copied');
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Public Key'),
            subtitle: Text(
              _publicKey ?? 'Loading...',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 20),
              onPressed: _publicKey != null
                  ? () {
                      Clipboard.setData(ClipboardData(text: _publicKey!));
                      _showSnack('Public key copied');
                    }
                  : null,
            ),
          ),
          const Divider(),

          // Capture settings
          _SectionHeader('Capture'),
          SwitchListTile(
            secondary: const Icon(Icons.location_on),
            title: const Text('Include GPS Location'),
            subtitle: const Text('Embeds coordinates in proof metadata'),
            value: _getSetting('gps_enabled'),
            onChanged: (v) => _setSetting('gps_enabled', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.sensors),
            title: const Text('Capture Sensor Data'),
            subtitle: const Text(
                'Accelerometer, gyroscope, magnetometer snapshots'),
            value: _getSetting('sensors_enabled'),
            onChanged: (v) => _setSetting('sensors_enabled', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.access_time),
            title: const Text('NTP Time Sync'),
            subtitle: const Text('Verify device clock against NTP servers'),
            value: _getSetting('ntp_enabled'),
            onChanged: (v) => _setSetting('ntp_enabled', v),
          ),
          const Divider(),

          // Verification settings
          _SectionHeader('Verification'),
          SwitchListTile(
            secondary: const Icon(Icons.schedule),
            title: const Text('Auto RFC 3161 Timestamp'),
            subtitle: const Text('Request trusted timestamp on every capture'),
            value: _getSetting('auto_tsa'),
            onChanged: (v) => _setSetting('auto_tsa', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.link),
            title: const Text('Auto Blockchain Anchor'),
            subtitle: const Text(
                'Anchor proof hash to Polygon (requires wallet)'),
            value: _getSetting('auto_blockchain', defaultValue: false),
            onChanged: (v) => _setSetting('auto_blockchain', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.description),
            title: const Text('Generate C2PA Manifest'),
            subtitle:
                const Text('Attach C2PA Content Credentials to media'),
            value: _getSetting('auto_c2pa'),
            onChanged: (v) => _setSetting('auto_c2pa', v),
          ),
          const Divider(),

          // TSA Configuration
          _SectionHeader('Advanced'),
          ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('TSA Servers'),
            subtitle: const Text('freetsa.org, digicert.com, sectigo.com'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _showSnack('TSA configuration coming soon');
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: const Text('Blockchain Wallet'),
            subtitle: const Text('Configure Polygon/Ethereum wallet'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _showSnack('Wallet configuration coming soon');
            },
          ),
          const Divider(),

          // About
          _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('TruthLens'),
            subtitle: const Text('Version 1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Open Source'),
            subtitle: const Text('View on GitHub'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () {
              _showSnack('GitHub link coming soon');
            },
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
