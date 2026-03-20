import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactUsScreen extends StatefulWidget {
  final String? username;
  final String? email;

  const ContactUsScreen({super.key, this.username, this.email});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color primaryBlue   = Color(0xFF3B82F6);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  Future<void> _makePhoneCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      _snack('Could not open phone dialer');
    }
  }

  Future<void> _sendEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email, query: 'subject=Support Request&body=Hello, I need help with...');
    try {
      await launchUrl(uri);
    } catch (_) {
      _snack('Could not open email app');
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final clean    = phone.replaceAll(RegExp(r'\D'), '');
    final uName    = widget.username?.isNotEmpty == true ? widget.username! : 'a user';
    final uEmail   = widget.email?.isNotEmpty    == true ? widget.email!    : 'not provided';
    final message = Uri.encodeComponent(
      'Hello AMSUBNIG Support Team,\n\n'
          'I need assistance with my account and would like to speak with a support agent.\n\n'
          'Account Details:\n'
          '• Username: $uName\n'
          '• Email: $uEmail\n\n'
          'Please help me resolve my issue. Thank you.',
    );
    final appUri   = Uri.parse('whatsapp://send?phone=$clean&text=$message');
    final webUri   = Uri.parse('https://wa.me/$clean?text=$message');
    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      _snack('Please install WhatsApp to chat with us');
    }
  }

  void _openLiveChat() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Live Chat', style: TextStyle(fontSize: 15)),
        content: const Text(
          'Live chat coming soon! Please use WhatsApp or phone support for now.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: primaryPurple)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: primaryPurple,
      behavior: SnackBarBehavior.floating,
    ));
  }

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
          'Contact Us',
          style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Center(
              child: Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [primaryPurple, primaryBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.headset_mic, color: Colors.white, size: 34),
              ),
            ),
            const SizedBox(height: 12),
            const Center(child: Text('How can we help you?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const SizedBox(height: 4),
            Center(child: Text("We're here to assist you 24/7", style: TextStyle(fontSize: 12, color: lightText))),

            const SizedBox(height: 16),

            // ── 24/7 support banner ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [primaryPurple, Color(0xFF9B7DFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(children: [
                Icon(Icons.support_agent, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('24/7 Support Available', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    SizedBox(height: 2),
                    Text("We're always here — reach us any time, day or night.", style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ),
              ]),
            ),

            const SizedBox(height: 14),

            // ── Contact options (WhatsApp first) ─────────────────────────
            _buildContactOption(assetIcon: 'assets/images/whatsapp.png', title: 'WhatsApp',      value: '+2348069450562',              subtitle: 'Available 24/7 · Tap to chat', onTap: () => _openWhatsApp('+2348069450562')),
            _buildContactOption(icon: Icons.phone,                       title: 'Phone Support', value: '+2348069450562',              subtitle: 'Tap to call',                  onTap: () => _makePhoneCall('+2348069450562')),
            _buildContactOption(icon: Icons.email,                       title: 'Email Support', value: 'talk2amenterprise@gmail.com', subtitle: 'Tap to send email',            onTap: () => _sendEmail('talk2amenterprise@gmail.com')),
            _buildContactOption(icon: Icons.chat,                        title: 'Live Chat',     value: 'Chat with us now',            subtitle: '24/7 instant support',         onTap: _openLiveChat),

            const SizedBox(height: 18),

            // ── Office address ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: lightPurple,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.location_on, color: primaryPurple, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Office Address', style: TextStyle(fontWeight: FontWeight.bold, color: darkText, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('No. 5 opposite FCE Kano, Nigeria', style: TextStyle(color: lightText, fontSize: 12)),
                  ]),
                ),
              ]),
            ),

            const SizedBox(height: 12),

            // ── Business hours ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.access_time, color: primaryPurple, size: 16),
                    const SizedBox(width: 7),
                    const Text('Business Hours', style: TextStyle(fontWeight: FontWeight.bold, color: darkText, fontSize: 13)),
                  ]),
                  const SizedBox(height: 10),
                  _buildHoursRow('Monday - Friday', '8:00 AM - 8:00 PM'),
                  _buildHoursRow('Saturday',         '9:00 AM - 6:00 PM'),
                  _buildHoursRow('Sunday',           '10:00 AM - 4:00 PM'),
                  const SizedBox(height: 6),
                  Text('*24/7 support available for emergencies', style: TextStyle(fontSize: 11, color: lightText, fontStyle: FontStyle.italic)),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Response time badge ───────────────────────────────────────
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(30)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timer, color: primaryPurple, size: 14),
                  const SizedBox(width: 6),
                  const Text('Average response time: < 5 minutes', style: TextStyle(color: primaryPurple, fontWeight: FontWeight.w500, fontSize: 11)),
                ]),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildContactOption({
    IconData? icon,
    String? assetIcon,   // e.g. 'assets/images/whatsapp.png'
    required String title,
    required String value,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    assert(icon != null || assetIcon != null, 'Provide either icon or assetIcon');

    final leadingWidget = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(10)),
      child: assetIcon != null
          ? Image.asset(assetIcon, width: 18, height: 18)
          : Icon(icon, color: primaryPurple, size: 18),
    );

    final trailingIcon = assetIcon != null
        ? Icons.arrow_forward
        : icon == Icons.phone
        ? Icons.phone_in_talk
        : icon == Icons.email
        ? Icons.send
        : Icons.arrow_forward;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          leadingWidget,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 11, color: lightText)),
              const SizedBox(height: 1),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText)),
              const SizedBox(height: 1),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: primaryPurple, fontWeight: FontWeight.w500)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(color: lightPurple, shape: BoxShape.circle),
            child: Icon(trailingIcon, color: primaryPurple, size: 14),
          ),
        ]),
      ),
    );
  }

  Widget _buildHoursRow(String day, String hours) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(day,   style: TextStyle(color: lightText, fontSize: 12)),
          Text(hours, style: const TextStyle(color: darkText, fontWeight: FontWeight.w500, fontSize: 12)),
        ],
      ),
    );
  }
}