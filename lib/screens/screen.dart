import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
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
  // ────────────────────────────────────────────────
  //  Brand colors (same as dashboard)
  // ────────────────────────────────────────────────
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue   = const Color(0xFF3B82F6);
  final Color lightPurple   = const Color(0xFFF0EEFF);
  final Color darkText      = const Color(0xFF1E293B);
  final Color lightText     = const Color(0xFF64748B);

  Map<String, dynamic>? userData;
  bool isLoading = true;
  String? errorMessage;

  // Random avatar background (consistent per session)
  late Color avatarColor;

  final List<Color> avatarColors = [
    const Color(0xFF6B4EFF),
    const Color(0xFF3B82F6),
    const Color(0xFF8B5CF6),
    const Color(0xFFEC4899),
    const Color(0xFF10B981),
    const Color(0xFFF59E0B),
  ];

  @override
  void initState() {
    super.initState();
    avatarColor = avatarColors[Random().nextInt(avatarColors.length)];
    _loadCachedProfile();     // instant UI
    _fetchUserProfile();      // background refresh
  }

  // ────────────────────────────────────────────────
  //  Smart retry helper (same pattern as dashboard)
  // ────────────────────────────────────────────────
  Future<http.Response> safeApiCall(
      Uri url,
      Map<String, String> headers,
      ) async {
    try {
      return await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      await Future.delayed(const Duration(seconds: 2));
      return await http.get(url, headers: headers);
    }
  }

  Future<void> _loadCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('profile_cache');
    if (cached == null) return;

    try {
      final data = jsonDecode(cached);
      if (!mounted) return;

      setState(() {
        userData = data as Map<String, dynamic>?;
        isLoading = false;
      });
    } catch (_) {
      // silent fail — cache corrupted → will be overwritten by network
    }
  }

  Future<void> _fetchUserProfile() async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            errorMessage = 'Session expired. Please login again.';
            isLoading = false;
          });
        }
        return;
      }

      final response = await safeApiCall(
        Uri.parse('https://amsubnig.com/api/user/'),
        {'Authorization': 'Token $token'},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final freshUser = data['user'] as Map<String, dynamic>?;

        // Cache it
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_cache', jsonEncode(freshUser));

        if (mounted) {
          setState(() {
            userData = freshUser;
            errorMessage = null;
            isLoading = false;
          });
        }
      } else if (response.statusCode == 401) {
        if (mounted) {
          setState(() {
            errorMessage = 'Session expired';
            isLoading = false;
          });
        }
      } else {
        // Keep showing cache if we have it — only show error if no cache
        if (userData == null) {
          if (mounted) {
            setState(() {
              errorMessage = 'Failed to load profile (${response.statusCode})';
              isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Profile fetch error: $e');
      if (mounted && userData == null) {
        setState(() {
          errorMessage = 'Network error. Showing cached data if available.';
          isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: lightText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Logout', style: TextStyle(color: primaryPurple, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  Future<void> _deactivateAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Deactivate Account', style: TextStyle(color: primaryPurple)),
        content: const Text(
          'This action will deactivate your account.\nYou can reactivate later by logging in.\n\nAre you sure?',
          style: TextStyle(color: Colors.redAccent),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: lightText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Deactivate', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Account deactivation requested'),
            backgroundColor: primaryPurple,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: _buildSkeletonProfile(),
      );
    }

    if (errorMessage != null && userData == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, size: 72, color: lightText),
                const SizedBox(height: 24),
                Text(
                  errorMessage!,
                  style: TextStyle(color: lightText, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _fetchUserProfile,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // We have data (or fallback cached data)
    final user = userData ?? {};
    final fullName = user['FullName']?.toString() ?? 'User';
    final username = user['username']?.toString() ?? '@user';
    final email    = user['email']?.toString() ?? '';
    final phone    = user['Phone']?.toString() ?? '';
    final category = user['user_type']?.toString() ?? 'Standard User';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: primaryPurple,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchUserProfile,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchUserProfile,
        color: primaryPurple,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // ─── Header Gradient Section ───
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryPurple, primaryBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(36),
                    bottomRight: Radius.circular(36),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryPurple.withOpacity(0.28),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: CircleAvatar(
                        radius: 58,
                        backgroundColor: avatarColor,
                        child: Text(
                          fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 52,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      username,
                      style: const TextStyle(fontSize: 16, color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        if (email.isNotEmpty) _buildStatChip(Icons.email_outlined, email.split('@').first),
                        if (phone.isNotEmpty) _buildStatChip(Icons.phone_outlined, phone),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            category,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Account Information
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(Icons.person_outline, 'Account Information'),
                    const SizedBox(height: 12),
                    _buildInfoTile(Icons.email_outlined, 'Email', email),
                    if (phone.isNotEmpty) _buildInfoTile(Icons.phone_outlined, 'Phone', phone),
                    _buildInfoTile(Icons.calendar_today_outlined, 'Member Since', '2024'),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Settings & Preferences
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(Icons.settings_outlined, 'Settings & Preferences'),
                    const SizedBox(height: 12),
                    _buildMenuTile(Icons.edit_outlined, 'Edit Profile', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditProfileScreen(
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
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactUsScreen()));
                    }),
                    _buildMenuTile(Icons.star_border_rounded, 'Rate Us', () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: const Text('Redirecting to store...'), backgroundColor: primaryPurple),
                      );
                    }),
                    _buildMenuTile(Icons.share_outlined, 'Share App', () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: const Text('Share feature coming soon'), backgroundColor: primaryPurple),
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Danger Zone
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.withOpacity(0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Danger Zone',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDangerTile(Icons.logout_rounded, 'Log Out', _logout),
                    const SizedBox(height: 12),
                    _buildDangerTile(Icons.delete_forever_rounded, 'Deactivate Account', _deactivateAccount),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Footer version
              Text(
                'Version 1.0.1  •  AMSUBNIG',
                style: TextStyle(fontSize: 13, color: lightText),
              ),

              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonProfile() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header skeleton
            Container(
              height: 340,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(36),
                  bottomRight: Radius.circular(36),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Section header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(width: 32, height: 32, color: Colors.white),
                  const SizedBox(width: 12),
                  Container(width: 180, height: 20, color: Colors.white),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Info tile
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Menu items
            ...List.generate(5, (_) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Container(
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            )),
            const SizedBox(height: 32),
            // Danger zone
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: lightPurple,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: primaryPurple, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: darkText,
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: lightPurple,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: primaryPurple, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 13, color: lightText)),
                const SizedBox(height: 4),
                Text(
                  value.isNotEmpty ? value : '—',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: darkText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: lightPurple,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: primaryPurple, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: darkText),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: primaryPurple, size: 26),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDangerTile(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.red, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.red,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.red, size: 20),
        onTap: onTap,
      ),
    );
  }
}