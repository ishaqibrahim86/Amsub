import 'package:flutter/material.dart';
import 'privacy_policy_screen.dart';

class PrivacyPolicySimpleScreen extends StatelessWidget {
  const PrivacyPolicySimpleScreen({super.key});

  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color primaryBlue   = Color(0xFF3B82F6);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 48,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: primaryPurple, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Privacy Policy',
          style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.description, color: primaryPurple, size: 20),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              width: 70,
              height: 70,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryPurple, primaryBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.privacy_tip, color: Colors.white, size: 34),
            ),

            const SizedBox(height: 14),

            const Text(
              'Privacy Policy Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 14),

            // ── Summary cards ────────────────────────────────────────────
            _buildSummaryCard(icon: Icons.security,         title: 'Data Protection', description: 'Your data is encrypted and securely stored.'),
            _buildSummaryCard(icon: Icons.remove_red_eye,   title: 'No Tracking',     description: 'We do not track your activity outside our app.'),
            _buildSummaryCard(icon: Icons.lock,             title: 'Privacy First',   description: 'We never share your personal information.'),
            _buildSummaryCard(icon: Icons.update,           title: 'Stay Updated',    description: 'Policy updates are notified in advance.'),

            const SizedBox(height: 20),

            // ── Read full policy button ───────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 2,
                ),
                child: const Text('Read Full Privacy Policy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),

            const SizedBox(height: 16),

            // ── Agreement note ────────────────────────────────────────────
            Row(children: [
              const Icon(Icons.check_circle, color: primaryPurple, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'By continuing to use this app, you agree to our Privacy Policy.',
                  style: TextStyle(fontSize: 12, color: lightText),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: primaryPurple, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText)),
            const SizedBox(height: 2),
            Text(description, style: const TextStyle(fontSize: 12, color: lightText)),
          ]),
        ),
      ]),
    );
  }
}