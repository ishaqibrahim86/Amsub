import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pin_auth_service.dart';

class AppLockAndFingerprintScreen extends StatefulWidget {
  const AppLockAndFingerprintScreen({super.key});

  @override
  State<AppLockAndFingerprintScreen> createState() => _AppLockAndFingerprintScreenState();
}

class _AppLockAndFingerprintScreenState extends State<AppLockAndFingerprintScreen> {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color primaryBlue   = Color(0xFF3B82F6);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  bool _lockEnabled        = true;
  bool _biometricEnabled   = false;
  bool _deviceHasBiometric = false;
  bool _isLoading          = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs     = await SharedPreferences.getInstance();
    final supported = await PinAuthService.deviceSupportsBiometrics();
    final bioOn     = await PinAuthService.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _lockEnabled        = prefs.getBool('lock_enabled') ?? true;
      _deviceHasBiometric = supported;
      _biometricEnabled   = bioOn;
      _isLoading          = false;
    });
  }

  Future<void> _toggleLock(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lock_enabled', value);
    setState(() => _lockEnabled = value);
    _snack(value ? '🔒 App lock enabled' : '🔓 App lock disabled', value ? primaryPurple : Colors.orange);
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final verified = await PinAuthService.verify(context);
      if (!verified) return;
    }
    await PinAuthService.setBiometricEnabled(value);
    setState(() => _biometricEnabled = value);
    if (!mounted) return;
    _snack(
      value ? '👆 Fingerprint for transactions enabled' : '🔑 Fingerprint disabled — PIN required',
      value ? primaryPurple : Colors.orange,
    );
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      duration: const Duration(seconds: 2),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('App Lock & Fingerprint', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: primaryPurple,
        elevation: 0,
        toolbarHeight: 48,
        iconTheme: const IconThemeData(color: primaryPurple),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryPurple))
          : ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        children: [
          // ── Header ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [primaryPurple, primaryBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: primaryPurple.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_rounded, size: 22, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Access & Lock',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Control how you unlock the app and confirm transactions',
                        style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── App Lock card ─────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2)),
              ],
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  title: Text(
                    'App Lock',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: darkText),
                  ),
                  subtitle: Text(
                    _lockEnabled
                        ? 'App will lock when closed. Use PIN or fingerprint to unlock.'
                        : 'App will not lock when closed. Less secure.',
                    style: TextStyle(color: _lockEnabled ? primaryPurple : lightText, fontSize: 11),
                  ),
                  value: _lockEnabled,
                  onChanged: _toggleLock,
                  secondary: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _lockEnabled ? lightPurple : primaryPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _lockEnabled ? Icons.lock : Icons.lock_open,
                      color: _lockEnabled ? primaryPurple : primaryBlue,
                      size: 18,
                    ),
                  ),
                  activeColor: primaryPurple,
                  activeTrackColor: primaryPurple.withOpacity(0.5),
                ),
                if (_lockEnabled)
                  _infoBanner(
                    icon: Icons.info_outline,
                    text: 'App lock is ON by default for your security. You can disable it anytime.',
                    iconColor: primaryPurple,
                    bgColor: lightPurple,
                    borderColor: primaryPurple.withOpacity(0.2),
                    textColor: darkText,
                  ),
              ],
            ),
          ),

          // ── Fingerprint card ──────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2)),
              ],
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  title: Text(
                    'Fingerprint for Transactions',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: darkText),
                  ),
                  subtitle: Text(
                    !_deviceHasBiometric
                        ? 'No fingerprint enrolled on this device.'
                        : _biometricEnabled
                        ? 'Use your fingerprint instead of PIN to confirm purchases and transfers.'
                        : 'PIN will be required before every transaction.',
                    style: TextStyle(
                      color: !_deviceHasBiometric
                          ? lightText
                          : _biometricEnabled
                          ? primaryPurple
                          : lightText,
                      fontSize: 11,
                    ),
                  ),
                  value: _deviceHasBiometric && _biometricEnabled,
                  onChanged: _deviceHasBiometric ? _toggleBiometric : null,
                  secondary: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: (_biometricEnabled && _deviceHasBiometric)
                          ? lightPurple
                          : primaryPurple.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.fingerprint,
                      color: (_biometricEnabled && _deviceHasBiometric) ? primaryPurple : lightText,
                      size: 18,
                    ),
                  ),
                  activeColor: primaryPurple,
                  activeTrackColor: primaryPurple.withOpacity(0.5),
                ),

                if (_deviceHasBiometric && _biometricEnabled)
                  _infoBanner(
                    icon: Icons.check_circle_outline,
                    text: "Fingerprint is active. You'll be prompted to scan before every purchase or transfer.",
                    iconColor: Colors.green,
                    bgColor: const Color(0xFFE8F5E9),
                    borderColor: Colors.green.withOpacity(0.3),
                    textColor: const Color(0xFF1B5E20),
                  ),

                if (_deviceHasBiometric && !_biometricEnabled)
                  _infoBanner(
                    icon: Icons.info_outline,
                    text: 'Enable to skip PIN entry and use your fingerprint for faster, secure transactions.',
                    iconColor: primaryPurple,
                    bgColor: lightPurple,
                    borderColor: primaryPurple.withOpacity(0.2),
                    textColor: darkText,
                  ),

                if (!_deviceHasBiometric)
                  _infoBanner(
                    icon: Icons.fingerprint,
                    text: "No fingerprint enrolled on this device. Set one up in your phone's Settings to use this feature.",
                    iconColor: Colors.grey.shade400,
                    bgColor: Colors.grey.shade50,
                    borderColor: Colors.grey.shade200,
                    textColor: lightText,
                  ),
              ],
            ),
          ),

          // ── Bottom tip ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: lightPurple,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info, color: primaryPurple, size: 15),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Enabling fingerprint requires PIN verification once to ensure only you can activate it.',
                    style: TextStyle(fontSize: 12, color: darkText, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _infoBanner({
    required IconData icon,
    required String text,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(color: textColor, fontSize: 11, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}