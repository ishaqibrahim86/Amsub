import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';

class ResetPinScreen extends StatefulWidget {
  const ResetPinScreen({super.key});

  @override
  State<ResetPinScreen> createState() => _ResetPinScreenState();
}

class _ResetPinScreenState extends State<ResetPinScreen> {
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue   = const Color(0xFF3B82F6);
  final Color lightPurple   = const Color(0xFFF0EEFF);
  final Color darkText      = const Color(0xFF1E293B);
  final Color lightText     = const Color(0xFF64748B);

  final _formKey              = GlobalKey<FormState>();
  final _passwordController   = TextEditingController();
  final _newPinController     = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool    _isSaving        = false;
  String? _error;
  String? _success;
  bool    _obscurePassword = true;
  bool    _obscureNew      = true;
  bool    _obscureConfirm  = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _resetPin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isSaving = true; _error = null; _success = null; });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() { _error = 'Session expired. Please login again.'; _isSaving = false; });
        return;
      }

      final url = Uri.parse(
        'https://amsubnig.com/api/resetpin/?'
            'password=${_passwordController.text}&'
            'pin1=${_newPinController.text}&'
            'pin2=${_confirmPinController.text}',
      );

      final response = await http.get(url, headers: {'Authorization': 'Token $token'});

      if (response.statusCode == 200) {
        final resp = jsonDecode(response.body);
        setState(() { _success = resp['message'] ?? 'PIN reset successfully!'; _isSaving = false; });
        _passwordController.clear();
        _newPinController.clear();
        _confirmPinController.clear();

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('PIN reset successfully'),
          backgroundColor: primaryPurple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        Future.delayed(const Duration(seconds: 1), () { if (mounted) Navigator.pop(context); });
      } else {
        String errorMsg = 'Failed to reset PIN';
        try {
          final resp = jsonDecode(response.body);
          errorMsg = resp['error'] ?? errorMsg;
        } catch (_) { errorMsg = 'Server error (${response.statusCode})'; }
        setState(() { _error = errorMsg; _isSaving = false; });
      }
    } catch (_) {
      setState(() { _error = 'Network error. Please check your connection.'; _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Reset PIN', style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: primaryPurple,
        elevation: 0,
        toolbarHeight: 48,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: primaryPurple, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ────────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryPurple, primaryBlue],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: primaryPurple.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: const Icon(Icons.restart_alt, color: Colors.white, size: 34),
                  ),
                ),

                const SizedBox(height: 14),

                const Center(child: Text('Reset Your PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    'Use your password to reset your transaction PIN',
                    style: TextStyle(fontSize: 12, color: lightText),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 22),

                // ── Password field ─────────────────────────────────────────
                _buildFieldLabel('Password'),
                const SizedBox(height: 6),
                _buildInputField(
                  controller: _passwordController,
                  hint: 'Enter your account password',
                  obscure: _obscurePassword,
                  icon: Icons.lock_outline,
                  onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                  isPin: false,
                  validator: (val) => (val == null || val.isEmpty) ? 'Please enter your password' : null,
                ),

                const SizedBox(height: 14),

                // ── New PIN field ──────────────────────────────────────────
                _buildFieldLabel('New PIN'),
                const SizedBox(height: 6),
                _buildInputField(
                  controller: _newPinController,
                  hint: 'Enter new 5-digit PIN',
                  obscure: _obscureNew,
                  icon: Icons.pin_outlined,
                  onToggle: () => setState(() => _obscureNew = !_obscureNew),
                  isPin: true,
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Please enter new PIN';
                    if (val.length != 5) return 'PIN must be exactly 5 digits';
                    if (!RegExp(r'^[0-9]+$').hasMatch(val)) return 'PIN must contain only numbers';
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                // ── Confirm PIN field ──────────────────────────────────────
                _buildFieldLabel('Confirm New PIN'),
                const SizedBox(height: 6),
                _buildInputField(
                  controller: _confirmPinController,
                  hint: 'Confirm new 5-digit PIN',
                  obscure: _obscureConfirm,
                  icon: Icons.pin_outlined,
                  onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  isPin: true,
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Please confirm new PIN';
                    if (val != _newPinController.text) return 'PINs do not match';
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                // ── Requirements box ──────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: lightPurple,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primaryPurple.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.info_outline, color: primaryPurple, size: 15),
                        const SizedBox(width: 6),
                        Text('PIN Requirements', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: darkText)),
                      ]),
                      const SizedBox(height: 8),
                      _buildRequirement('Must be exactly 5 digits'),
                      _buildRequirement('Numbers only (0-9)'),
                      _buildRequirement('Use your account password to verify'),
                      _buildRequirement('Keep your new PIN secure'),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ── Error / Success banners ───────────────────────────────
                if (_error != null) ...[
                  _statusBanner(
                    icon: Icons.error_outline,
                    text: _error!,
                    iconColor: Colors.red.shade700,
                    bgColor: Colors.red.shade50,
                    borderColor: Colors.red.shade200,
                    textColor: Colors.red.shade700,
                  ),
                  const SizedBox(height: 10),
                ],
                if (_success != null) ...[
                  _statusBanner(
                    icon: Icons.check_circle,
                    text: _success!,
                    iconColor: Colors.green.shade700,
                    bgColor: Colors.green.shade50,
                    borderColor: Colors.green.shade200,
                    textColor: Colors.green.shade700,
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Submit button ─────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _resetPin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryPurple,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[400],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 3,
                      shadowColor: primaryPurple.withOpacity(0.5),
                    ),
                    child: _isSaving
                        ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('Resetting...', style: TextStyle(fontSize: 14)),
                    ])
                        : const Text('Reset PIN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 12),

                Center(
                  child: Text(
                    'PIN is used for transactions and withdrawals',
                    style: TextStyle(fontSize: 11, color: lightText, fontStyle: FontStyle.italic),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────

  Widget _buildFieldLabel(String label) => Text(
    label,
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText),
  );

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required IconData icon,
    required VoidCallback onToggle,
    required bool isPin,
    required String? Function(String?) validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: isPin ? TextInputType.number : TextInputType.text,
        maxLength: isPin ? 5 : null,
        style: TextStyle(color: darkText, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: lightText, fontSize: 13),
          border: InputBorder.none,
          prefixIcon: Icon(icon, color: primaryPurple, size: 18),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: lightText, size: 18),
            onPressed: onToggle,
          ),
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
        validator: validator,
      ),
    );
  }

  Widget _statusBanner({
    required IconData icon,
    required String text,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 12))),
      ]),
    );
  }

  Widget _buildRequirement(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.check_circle, color: primaryPurple, size: 12),
        const SizedBox(width: 7),
        Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: lightText))),
      ]),
    );
  }
}