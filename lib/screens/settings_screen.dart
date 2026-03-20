// screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _lockEnabled = true; // Default to true
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLockSetting();
  }

  Future<void> _loadLockSetting() async {
    final prefs = await SharedPreferences.getInstance();
    // Get setting, default to true if not set
    setState(() {
      _lockEnabled = prefs.getBool('lock_enabled') ?? true;
      _isLoading = false;
    });

    print('=== LOADED LOCK SETTING ===');
    print('Lock enabled: $_lockEnabled');
  }

  Future<void> _toggleLock(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lock_enabled', value);
    setState(() {
      _lockEnabled = value;
    });

    // Show confirmation message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value
            ? '🔒 App lock enabled'
            : '🔓 App lock disabled'),
        duration: const Duration(seconds: 2),
        backgroundColor: value ? Colors.green : Colors.orange,
      ),
    );

    print('=== TOGGLED LOCK SETTING ===');
    print('Lock now: $value');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        children: [
          const SizedBox(height: 20),

          // App Lock Card
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text(
                      'App Lock',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _lockEnabled
                          ? 'App will lock when closed. Use PIN or fingerprint to unlock.'
                          : 'App will not lock when closed. Less secure.',
                      style: TextStyle(
                        color: _lockEnabled ? Colors.green[700] : Colors.grey[600],
                      ),
                    ),
                    value: _lockEnabled,
                    onChanged: _toggleLock,
                    secondary: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _lockEnabled ? Colors.green[50] : Colors.blue[50],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _lockEnabled ? Icons.lock : Icons.lock_open,
                        color: _lockEnabled ? Colors.green : Colors.blue,
                      ),
                    ),
                    activeColor: Colors.green,
                  ),

                  // Info text
                  if (_lockEnabled)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue[100]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue[700],
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'App lock is ON by default for your security. You can disable it anytime.',
                                style: TextStyle(
                                  color: Colors.blue[800],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Security tips
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Security Tips',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 12),
                _buildTip(
                  icon: Icons.fingerprint,
                  text: 'Use fingerprint for quick and secure access',
                ),
                _buildTip(
                  icon: Icons.pin,
                  text: 'Set a strong PIN that\'s hard to guess',
                ),
                _buildTip(
                  icon: Icons.security,
                  text: 'App lock protects your funds even if phone is lost',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTip({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: Colors.blue[600],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}