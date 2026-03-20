import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'edit_profile_screen.dart';
import '../services/auth_service.dart';
import 'security_screen.dart';
import 'contact_us_screen.dart';
import 'privacy_policy_simple_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue   = const Color(0xFF3B82F6);
  final Color lightPurple   = const Color(0xFFF0EEFF);
  final Color darkText      = const Color(0xFF1E293B);
  final Color lightText     = const Color(0xFF64748B);

  Map<String, dynamic>? userData;
  bool isLoading = true;
  String? errorMessage;
  late Color avatarColor;

  final List<Color> avatarColors = [
    const Color(0xFF6B4EFF), const Color(0xFF3B82F6),
    const Color(0xFF8B5CF6), const Color(0xFFEC4899),
    const Color(0xFF10B981), const Color(0xFFF59E0B),
  ];

  @override
  void initState() {
    super.initState();
    avatarColor = avatarColors[Random().nextInt(avatarColors.length)];
    _loadCachedProfile();
    _fetchUserProfile();
  }

  Future<http.Response> safeApiCall(Uri url, Map<String, String> headers) async {
    try {
      return await http.get(url, headers: headers).timeout(const Duration(seconds: 15));
    } catch (_) {
      await Future.delayed(const Duration(seconds: 2));
      return await http.get(url, headers: headers);
    }
  }

  Future<void> _loadCachedProfile() async {
    final prefs  = await SharedPreferences.getInstance();
    final cached = prefs.getString('profile_cache');
    if (cached == null) return;
    try {
      final data = jsonDecode(cached);
      if (!mounted) return;
      setState(() { userData = data as Map<String, dynamic>?; isLoading = false; });
    } catch (_) {}
  }

  Future<void> _fetchUserProfile() async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        if (mounted) setState(() { errorMessage = 'Session expired. Please login again.'; isLoading = false; });
        return;
      }

      final response = await safeApiCall(
        Uri.parse('https://amsubnig.com/api/user/'),
        {'Authorization': 'Token $token'},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data      = jsonDecode(response.body);
        final freshUser = data['user'] as Map<String, dynamic>?;
        final prefs     = await SharedPreferences.getInstance();
        await prefs.setString('profile_cache', jsonEncode(freshUser));
        if (mounted) setState(() { userData = freshUser; errorMessage = null; isLoading = false; });
      } else if (response.statusCode == 401) {
        if (mounted) setState(() { errorMessage = 'Session expired'; isLoading = false; });
      } else {
        if (userData == null && mounted) setState(() { errorMessage = 'Failed to load profile (${response.statusCode})'; isLoading = false; });
      }
    } catch (e) {
      debugPrint('Profile fetch error: $e');
      if (mounted && userData == null) setState(() { errorMessage = 'Network error. Showing cached data if available.'; isLoading = false; });
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(fontSize: 16)),
        content: const Text('Are you sure you want to logout?', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: lightText))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Logout', style: TextStyle(color: primaryPurple, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService.logout();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _deactivateAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Deactivate Account', style: TextStyle(color: primaryPurple, fontSize: 16)),
        content: const Text(
          'This will open WhatsApp so you can request account deactivation from our support team.',
          style: TextStyle(color: Colors.redAccent, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: lightText))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Proceed', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final formUri = Uri.parse('https://forms.gle/CXBuoGQm2mKMCeWj9');
      try {
        await launchUrl(formUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Could not open the form. Please try again.'),
            backgroundColor: primaryPurple,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
    }
  }

  Future<void> _rateApp() async {
    const packageName = 'com.aandmenterprise.amsubnig';
    final playStoreUri = Uri.parse('market://details?id=$packageName');
    final playStoreWebUri = Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
    try {
      if (await canLaunchUrl(playStoreUri)) {
        await launchUrl(playStoreUri);
      } else {
        await launchUrl(playStoreWebUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Could not open Play Store'),
          backgroundColor: primaryPurple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  Future<void> _shareApp() async {
    const packageName = 'com.aandmenterprise.amsubnig';
    await Share.share(
      'Check out AMSUBNIG — the easiest way to buy data, airtime, and more in Nigeria! 🚀\n\nDownload it here:\nhttps://play.google.com/store/apps/details?id=$packageName',
      subject: 'Try AMSUBNIG',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return Scaffold(backgroundColor: Colors.white, body: _buildSkeletonProfile());

    if (errorMessage != null && userData == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, size: 56, color: lightText),
                const SizedBox(height: 16),
                Text(errorMessage!, style: TextStyle(color: lightText, fontSize: 14), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _fetchUserProfile,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final user     = userData ?? {};
    final fullName = user['FullName']?.toString() ?? 'User';
    final username = user['username']?.toString() ?? '@user';
    final email    = user['email']?.toString() ?? '';
    final phone    = user['Phone']?.toString() ?? '';
    final category = user['user_type']?.toString() ?? 'Standard User';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: primaryPurple,
        elevation: 0,
        toolbarHeight: 48,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, size: 20), onPressed: _fetchUserProfile),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchUserProfile,
        color: primaryPurple,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // ── Compact header ──────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryPurple, primaryBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(color: primaryPurple.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: Column(
                  children: [
                    // Avatar
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: avatarColor,
                        child: Text(
                          fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 34, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Name
                    Text(fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 3),
                    Text(username, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    const SizedBox(height: 10),
                    // Email + phone chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        if (email.isNotEmpty) _buildStatChip(Icons.email_outlined, email),
                        if (phone.isNotEmpty) _buildStatChip(Icons.phone_outlined, phone),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Category badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified, color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text(category, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ── Settings & Preferences ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(Icons.settings_outlined, 'Settings & Preferences'),
                    const SizedBox(height: 10),
                    _buildMenuTile(Icons.edit_outlined, 'Edit Profile', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditProfileScreen(
                            currentFullName: user['FullName'] ?? '',
                            currentPhone: user['Phone'] ?? '',
                            currentAddress: user['Address'] ?? '',
                          ),
                        ),
                      ).then((_) => _fetchUserProfile());
                    }),
                    _buildMenuTile(Icons.security_outlined, 'Security', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityScreen()));
                    }),
                    _buildMenuTile(Icons.privacy_tip_outlined, 'Privacy Policy', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicySimpleScreen()));
                    }),
                    _buildMenuTile(Icons.help_outline, 'Help & Support', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ContactUsScreen(
                        username: user['username']?.toString(),
                        email: user['email']?.toString(),
                      )));
                    }),
                    _buildMenuTile(Icons.star_border_rounded, 'Rate Us', _rateApp),
                    _buildMenuTile(Icons.share_outlined, 'Share App', _shareApp),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ── Danger Zone ─────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.withOpacity(0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        const Text('Danger Zone', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.redAccent)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildDangerTile(Icons.logout_rounded, 'Log Out', _logout),
                    _buildDangerTile(Icons.delete_forever_rounded, 'Deactivate Account', _deactivateAccount),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Footer ──────────────────────────────────────────────────
              Text('Version 1.0.1  •  AMSUBNIG', style: TextStyle(fontSize: 11, color: lightText)),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────

  Widget _buildSkeletonProfile() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 240,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Container(width: 28, height: 28, color: Colors.white),
                const SizedBox(width: 10),
                Container(width: 160, height: 16, color: Colors.white),
              ]),
            ),
            const SizedBox(height: 12),
            ...List.generate(5, (_) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(height: 52, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
            )),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(height: 110, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: primaryPurple, size: 16),
        ),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: darkText)),
      ],
    );
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, color: primaryPurple, size: 17),
        ),
        title: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText)),
        trailing: Icon(Icons.chevron_right_rounded, color: primaryPurple, size: 20),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDangerTile(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Colors.red, size: 16),
        ),
        title: Text(title, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, color: Colors.red, size: 18),
        onTap: onTap,
      ),
    );
  }
}