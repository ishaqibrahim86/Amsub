import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AirtimeToCashScreen extends StatefulWidget {
  const AirtimeToCashScreen({super.key});

  @override
  State<AirtimeToCashScreen> createState() => _AirtimeToCashScreenState();
}

class _AirtimeToCashScreenState extends State<AirtimeToCashScreen> {
  // Brand colors
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue = const Color(0xFF3B82F6);
  final Color lightPurple = const Color(0xFFF0EEFF);
  final Color darkText = const Color(0xFF1E293B);
  final Color lightText = const Color(0xFF64748B);

  final _formKey = GlobalKey<FormState>();
  String? _selectedNetwork;
  final _amountController = TextEditingController();
  bool _isProcessing = false;
  String? _error;

  final List<String> _networks = ['MTN', 'Airtel', 'Glo', '9mobile/T2'];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _sendToWhatsApp() async {
    if (!_formKey.currentState!.validate()) return;

    final network = _selectedNetwork!;
    final amount = _amountController.text.trim();

    final message = "Hi, AmsubNig,\nI would like to convert $network airtime of ₦$amount";

    final whatsappUrl = Uri.parse(
      'https://wa.me/+2348069450562?text=${Uri.encodeComponent(message)}',
    );

    setState(() => _isProcessing = true);

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(
          whatsappUrl,
          mode: LaunchMode.externalApplication,
        );
      } else {
        setState(() {
          _error = 'Cannot open WhatsApp link. Please open WhatsApp manually and paste the message.';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Airtime to Cash',
          style: TextStyle(color: darkText, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: primaryPurple,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: primaryPurple, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Icon
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
                      Icons.currency_exchange,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                const Center(
                  child: Text(
                    'Convert Airtime to Cash',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                Center(
                  child: Text(
                    'Select network and enter amount to convert',
                    style: TextStyle(
                      fontSize: 14,
                      color: lightText,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Network Selection
                Text(
                  'Select Network',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: darkText,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _selectedNetwork,
                    hint: Text(
                      'Choose network',
                      style: TextStyle(color: lightText),
                    ),
                    items: _networks.map((n) => DropdownMenuItem(
                      value: n,
                      child: Text(n, style: TextStyle(color: darkText)),
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedNetwork = val),
                    validator: (val) => val == null ? 'Select network' : null,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      prefixIcon: Icon(Icons.signal_cellular_alt),
                    ),
                    icon: Icon(Icons.arrow_drop_down, color: primaryPurple),
                  ),
                ),

                const SizedBox(height: 24),

                // Amount
                Text(
                  'Amount (₦)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: darkText,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextFormField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: darkText),
                    decoration: InputDecoration(
                      hintText: 'e.g. 5000',
                      hintStyle: TextStyle(color: lightText),
                      border: InputBorder.none,
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 16, right: 4),
                        child: Text(
                          '₦',
                          style: TextStyle(
                            color: primaryPurple,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Enter amount';
                      final amt = double.tryParse(val.trim());
                      if (amt == null || amt < 100) return 'Minimum ₦100';
                      if (amt > 50000) return 'Maximum ₦50,000';
                      return null;
                    },
                  ),
                ),

                // Amount limits indicator
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: lightPurple,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, color: primaryPurple, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Min ₦100 • Max ₦50,000 per request',
                        style: TextStyle(
                          fontSize: 11,
                          color: primaryPurple,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Error Message
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red[700], fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _sendToWhatsApp,
                    icon: _isProcessing
                        ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                        : const Icon(Icons.send),
                    label: Text(
                      _isProcessing ? 'Opening WhatsApp...' : 'Continue to WhatsApp',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryPurple, // Changed from WhatsApp green to brand purple
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[400],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 3,
                      shadowColor: primaryPurple.withOpacity(0.5),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Note
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: lightPurple,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryPurple.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: primaryPurple, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'How it works',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: darkText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '1. Select your network\n2. Enter the amount\n3. You\'ll be redirected to WhatsApp\n4. Send the message to complete request',
                              style: TextStyle(
                                fontSize: 12,
                                color: lightText,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}