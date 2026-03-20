import 'package:flutter/material.dart';
import 'change_password_screen.dart';
import 'change_pin_screen.dart';
import 'reset_pin_screen.dart';
import 'privacy_policy_screen.dart';
import 'app_lock_and_fingerprint_screen.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue   = const Color(0xFF3B82F6);
  final Color lightPurple   = const Color(0xFFF0EEFF);
  final Color darkText      = const Color(0xFF1E293B);
  final Color lightText     = const Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Security', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF6B4EFF),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF6B4EFF)),
        toolbarHeight: 48,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        children: [
          // ── Header ────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
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
                  child: const Icon(Icons.security, size: 22, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Protect Your Account',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage your app lock, password, and PIN settings',
                        style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Section title ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              'Security Options',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: lightText),
            ),
          ),

          // ── Tiles ──────────────────────────────────────────────────────
          _buildSecurityTile(
            icon: Icons.fingerprint,
            title: 'App Lock & Fingerprint',
            subtitle: 'Manage lock settings and biometric authentication',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppLockAndFingerprintScreen())),
          ),
          _buildSecurityTile(
            icon: Icons.lock_outline,
            title: 'Change Password',
            subtitle: 'Update your login password',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
          ),
          _buildSecurityTile(
            icon: Icons.pin_outlined,
            title: 'Change PIN',
            subtitle: 'Use your old PIN to set a new PIN',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePinScreen())),
          ),
          _buildSecurityTile(
            icon: Icons.restart_alt,
            title: 'Reset PIN',
            subtitle: 'Use your login password to reset PIN',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResetPinScreen())),
          ),
          _buildSecurityTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'Read our privacy policy',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
          ),

          const SizedBox(height: 14),

          // ── Security Tips ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tips_and_updates, color: primaryPurple, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Security Tips',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildTip(icon: Icons.fingerprint, text: 'Use fingerprint for quick and secure access'),
                _buildTip(icon: Icons.pin,         text: "Set a strong PIN that's hard to guess"),
                _buildTip(icon: Icons.security,    text: 'App lock protects your funds even if phone is lost'),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Bottom note ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: lightPurple,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: primaryPurple, size: 15),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'PIN is used for transactions and withdrawals. Keep it secure.',
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

  Widget _buildSecurityTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: lightPurple,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: primaryPurple, size: 18),
        ),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600, color: darkText, fontSize: 13),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: lightText, fontSize: 11),
        ),
        trailing: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: lightPurple, shape: BoxShape.circle),
          child: Icon(Icons.chevron_right, color: primaryPurple, size: 15),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildTip({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: lightPurple,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(icon, size: 12, color: primaryPurple),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: lightText, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}