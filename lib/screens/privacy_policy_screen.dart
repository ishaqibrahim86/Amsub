// screens/privacy_policy_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  // Brand colors
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue = const Color(0xFF3B82F6);
  final Color lightPurple = const Color(0xFFF0EEFF);
  final Color darkText = const Color(0xFF1E293B);
  final Color lightText = const Color(0xFF64748B);

  DateTime? _lastUpdated = DateTime(2026, 3, 1); // March 1, 2026

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'talk2amenterprise@gmail.com',
      query: 'subject=Privacy Policy Question',
    );
    try {
      await launchUrl(emailUri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open email app'),
            backgroundColor: primaryPurple,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: primaryPurple, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Privacy Policy',
          style: TextStyle(
            color: darkText,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with shield icon
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryPurple, primaryBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primaryPurple.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.privacy_tip,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Title
            const Center(
              child: Text(
                'Your Privacy Matters',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Last Updated
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: lightPurple,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.update, color: primaryPurple, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Last Updated: ${_lastUpdated!.day}/${_lastUpdated!.month}/${_lastUpdated!.year}',
                      style: TextStyle(
                        color: primaryPurple,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Introduction
            _buildSection(
              title: 'Introduction',
              icon: Icons.info_outline,
              content: '''
At AMSUBNIG (A and M Enterprise), we take your privacy seriously. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application and services. Please read this privacy policy carefully. If you do not agree with the terms of this privacy policy, please do not access the application.''',
            ),

            _buildSection(
              title: 'Information We Collect',
              icon: Icons.data_usage,
              content: '''
We may collect personal information that you voluntarily provide to us when you register for the application, express interest in obtaining information about us or our products and services, or otherwise contact us.

The personal information we may collect includes:
• Name and contact information (email, phone number)
• Account credentials (username, password)
• Payment information and transaction history
• Device information and IP address
• Location data (with your consent)''',
            ),

            _buildSection(
              title: 'How We Use Your Information',
              icon: Icons.analytics,
              content: '''
We use the information we collect to:
• Create and manage your account
• Process your transactions and send confirmations
• Respond to your comments and questions
• Send you technical notices and support messages
• Monitor and analyze trends, usage, and activities
• Detect and prevent fraudulent transactions
• Improve and optimize our application''',
            ),

            _buildSection(
              title: 'Sharing Your Information',
              icon: Icons.share,
              content: '''
We do not sell, trade, or rent your personal information to third parties. We may share information with:
• Service providers who perform services on our behalf
• Payment processors to complete transactions
• Law enforcement when required by law
• Business transfers in case of merger or acquisition''',
            ),

            _buildSection(
              title: 'Data Security',
              icon: Icons.security,
              content: '''
We implement appropriate technical and organizational security measures to protect your personal information. However, please note that no method of transmission over the internet or electronic storage is 100% secure. While we strive to use commercially acceptable means to protect your information, we cannot guarantee absolute security.''',
            ),

            _buildSection(
              title: 'Your Rights',
              icon: Icons.verified_user,
              content: '''
You have the right to:
• Access and receive a copy of your personal information
• Rectify inaccurate or incomplete information
• Delete your personal information
• Object to or restrict processing of your information
• Data portability
• Withdraw consent at any time''',
            ),

            _buildSection(
              title: "Children's Privacy",  // Fixed: Used double quotes to escape apostrophe
              icon: Icons.family_restroom,
              content: '''
Our application is not intended for individuals under the age of 13. We do not knowingly collect personal information from children. If we become aware that we have collected personal information from a child without verification of parental consent, we will delete that information.''',
            ),

            _buildSection(
              title: 'Changes to This Policy',
              icon: Icons.change_circle,
              content: '''
We may update this privacy policy from time to time. We will notify you of any changes by posting the new privacy policy on this page and updating the "Last Updated" date. You are advised to review this privacy policy periodically for any changes.''',
            ),

            const SizedBox(height: 24),

            // Contact Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryPurple.withOpacity(0.05), primaryBlue.withOpacity(0.05)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryPurple.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryPurple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.contact_mail, color: primaryPurple, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Contact Us',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: darkText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'If you have questions or concerns about this Privacy Policy, please contact us:',
                    style: TextStyle(
                      fontSize: 14,
                      color: lightText,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _launchEmail,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: primaryPurple.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: lightPurple,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.email, color: primaryPurple, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Email Us',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: lightText,
                                  ),
                                ),
                                Text(
                                  'talk2amenterprise@gmail.com',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: primaryPurple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.open_in_new, color: primaryPurple, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Footer note
            Center(
              child: Text(
                'By using AMSUBNIG (A and M Enterprise), you agree to this Privacy Policy.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: lightText,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required String content,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: lightPurple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: primaryPurple, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: darkText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(left: 34), // Align with title text
            child: Text(
              content,
              style: TextStyle(
                fontSize: 14,
                color: lightText,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}