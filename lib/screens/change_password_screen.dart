import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue   = const Color(0xFF3B82F6);
  final Color lightPurple   = const Color(0xFFF0EEFF);
  final Color darkText      = const Color(0xFF1E293B);
  final Color lightText     = const Color(0xFF64748B);

  final _formKey                   = GlobalKey<FormState>();
  final _oldPasswordController     = TextEditingController();
  final _newPasswordController     = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool    _isSaving      = false;
  String? _error;
  String? _success;
  bool    _obscureOld     = true;
  bool    _obscureNew     = true;
  bool    _obscureConfirm = true;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isSaving = true; _error = null; _success = null; });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() { _error = 'Session expired. Please login again.'; _isSaving = false; });
        return;
      }

      final response = await http.post(
        Uri.parse('https://amsubnig.com/rest-auth/password/change/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'old_password':  _oldPasswordController.text,
          'new_password1': _newPasswordController.text,
          'new_password2': _confirmPasswordController.text,
        }),
      );

      if (response.statusCode == 200) {
        setState(() { _success = '✅ Password changed successfully!'; _isSaving = false; });
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Password updated successfully'),
          backgroundColor: primaryPurple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        Future.delayed(const Duration(seconds: 1), () { if (mounted) Navigator.pop(context); });
      } else {
        String errorMsg = 'Failed to change password';
        try {
          final resp = jsonDecode(response.body);
          if (resp is Map) {
            if (resp.containsKey('old_password'))       errorMsg = 'Old password is incorrect';
            else if (resp.containsKey('new_password1')) errorMsg = (resp['new_password1'] as List).firstOrNull?.toString() ?? 'Invalid new password';
            else if (resp.containsKey('new_password2')) errorMsg = 'Passwords do not match';
            else if (resp.containsKey('non_field_errors')) errorMsg = (resp['non_field_errors'] as List).firstOrNull?.toString() ?? errorMsg;
            else if (resp.containsKey('error'))         errorMsg = resp['error'].toString();
            else if (resp.containsKey('detail'))        errorMsg = resp['detail'].toString();
          }
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
        title: Text('Change Password', style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16)),
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
                    child: const Icon(Icons.lock_outline, color: Colors.white, size: 34),
                  ),
                ),

                const SizedBox(height: 14),

                const Center(
                  child: Text('Update Your Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    "Choose a strong password you haven't used before",
                    style: TextStyle(fontSize: 12, color: lightText),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 22),

                // ── Fields ────────────────────────────────────────────────
                _buildFieldLabel('Current Password'),
                const SizedBox(height: 6),
                _buildPasswordField(
                  controller: _oldPasswordController,
                  hint: 'Enter current password',
                  obscure: _obscureOld,
                  onToggle: () => setState(() => _obscureOld = !_obscureOld),
                  validator: (val) => val!.isEmpty ? 'Current password is required' : null,
                ),

                const SizedBox(height: 14),

                _buildFieldLabel('New Password'),
                const SizedBox(height: 6),
                _buildPasswordField(
                  controller: _newPasswordController,
                  hint: 'Enter new password',
                  obscure: _obscureNew,
                  onToggle: () => setState(() => _obscureNew = !_obscureNew),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'New password is required';
                    if (val.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),

                // Password strength
                if (_newPasswordController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 10),
                    child: Row(children: [
                      Icon(_getStrengthIcon(_newPasswordController.text), color: _getStrengthColor(_newPasswordController.text), size: 13),
                      const SizedBox(width: 5),
                      Text(_getStrengthText(_newPasswordController.text), style: TextStyle(fontSize: 11, color: _getStrengthColor(_newPasswordController.text))),
                    ]),
                  ),

                const SizedBox(height: 14),

                _buildFieldLabel('Confirm New Password'),
                const SizedBox(height: 6),
                _buildPasswordField(
                  controller: _confirmPasswordController,
                  hint: 'Confirm new password',
                  obscure: _obscureConfirm,
                  onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  validator: (val) => val != _newPasswordController.text ? 'Passwords do not match' : null,
                ),

                const SizedBox(height: 20),

                // ── Error / Success banners ────────────────────────────────
                if (_error != null) ...[
                  _statusBanner(
                    icon: Icons.error_outline,
                    text: _error!,
                    iconColor: Colors.red.shade700,
                    bgColor: Colors.red.shade50,
                    borderColor: Colors.red.shade200,
                    textColor: Colors.red.shade700,
                  ),
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 14),
                ],

                // ── Submit button ─────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _changePassword,
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
                      Text('Updating...', style: TextStyle(fontSize: 14)),
                    ])
                        : const Text('Update Password', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 16),

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
                        Text('Password Requirements', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: darkText)),
                      ]),
                      const SizedBox(height: 8),
                      _buildRequirement('At least 6 characters long'),
                      _buildRequirement('Should be different from old password'),
                      _buildRequirement('Use a mix of letters and numbers'),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
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

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    void Function(String)? onChanged,
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
        style: TextStyle(color: darkText, fontSize: 14),
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: lightText, fontSize: 13),
          border: InputBorder.none,
          prefixIcon: Icon(Icons.lock_outline, color: primaryPurple, size: 18),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: lightText, size: 18),
            onPressed: onToggle,
          ),
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

  // ── Password strength helpers ─────────────────────────────────────────────

  IconData _getStrengthIcon(String p) {
    if (p.length < 6) return Icons.error_outline;
    if (p.length < 8) return Icons.warning_amber;
    if (p.contains(RegExp(r'[0-9]')) && p.contains(RegExp(r'[A-Za-z]'))) return Icons.check_circle;
    return Icons.info_outline;
  }

  Color _getStrengthColor(String p) {
    if (p.length < 6) return Colors.red;
    if (p.length < 8) return Colors.orange;
    if (p.contains(RegExp(r'[0-9]')) && p.contains(RegExp(r'[A-Za-z]'))) return Colors.green;
    return Colors.blue;
  }

  String _getStrengthText(String p) {
    if (p.length < 6) return 'Too short';
    if (p.length < 8) return 'Could be stronger';
    if (p.contains(RegExp(r'[0-9]')) && p.contains(RegExp(r'[A-Za-z]'))) return 'Strong password';
    return 'Add numbers for stronger password';
  }
}