import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';

class EditProfileScreen extends StatefulWidget {
  final String currentFullName;
  final String currentPhone;
  final String currentAddress;

  const EditProfileScreen({
    super.key,
    required this.currentFullName,
    required this.currentPhone,
    required this.currentAddress,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue   = const Color(0xFF3B82F6);
  final Color lightPurple   = const Color(0xFFF0EEFF);
  final Color darkText      = const Color(0xFF1E293B);
  final Color lightText     = const Color(0xFF64748B);

  final _formKey = GlobalKey<FormState>();

  late TextEditingController _fullNameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _emailController;

  bool    _isSaving       = false;
  String? _errorMessage;
  String? _successMessage;
  String? _username;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.currentFullName);
    _phoneController    = TextEditingController(text: widget.currentPhone);
    _addressController  = TextEditingController(text: widget.currentAddress);
    _emailController    = TextEditingController();
    _fetchUserProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return;
      final response = await http.get(
        Uri.parse('https://amsubnig.com/rest-auth/user/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _fullNameController.text = data['FullName'] ?? widget.currentFullName;
          _phoneController.text    = data['Phone']    ?? widget.currentPhone;
          _addressController.text  = data['Address']  ?? widget.currentAddress;
          _emailController.text    = data['email']    ?? '';
          _username                = data['username'];
        });
      }
    } catch (e) { debugPrint('Error fetching profile: $e'); }
  }

  bool get _hasChanges =>
      _fullNameController.text != widget.currentFullName ||
          _phoneController.text    != widget.currentPhone    ||
          _addressController.text  != widget.currentAddress;

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasChanges) { setState(() => _errorMessage = 'No changes to save'); return; }

    setState(() { _isSaving = true; _errorMessage = null; _successMessage = null; });

    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        setState(() { _errorMessage = 'Session expired. Please login again.'; _isSaving = false; });
        return;
      }

      final response = await http.patch(
        Uri.parse('https://amsubnig.com/rest-auth/user/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'FullName': _fullNameController.text.trim(),
          'Phone':    _phoneController.text.trim(),
          'Address':  _addressController.text.trim(),
        }),
      );

      if (response.statusCode == 200 && mounted) {
        setState(() { _successMessage = '✅ Profile updated successfully!'; _isSaving = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Profile updated successfully'),
          backgroundColor: primaryPurple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        Navigator.pop(context, true);
      } else {
        setState(() { _errorMessage = 'Failed to update profile. Please try again.'; _isSaving = false; });
      }
    } catch (_) {
      setState(() { _errorMessage = 'Network error. Please check your connection.'; _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Edit Profile', style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: primaryPurple,
        elevation: 0,
        toolbarHeight: 48,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: primaryPurple, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: primaryPurple, size: 20),
            onPressed: _fetchUserProfile,
            tooltip: 'Refresh',
          ),
        ],
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
                    child: const Icon(Icons.person_outline, color: Colors.white, size: 34),
                  ),
                ),

                const SizedBox(height: 14),

                const Center(child: Text('Update Your Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                const SizedBox(height: 4),
                Center(child: Text('Make changes to your profile below', style: TextStyle(fontSize: 12, color: lightText))),

                const SizedBox(height: 22),

                // ── Username (read-only) ───────────────────────────────────
                if (_username != null) ...[
                  _buildFieldLabel('Username'),
                  const SizedBox(height: 6),
                  _buildReadOnlyField(
                    value: _username!,
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.info_outline, size: 12, color: lightText),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'To change your username, please contact our support team.',
                        style: TextStyle(fontSize: 11, color: lightText, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                ],

                // ── Email (read-only) ─────────────────────────────────────
                _buildFieldLabel('Email Address'),
                const SizedBox(height: 6),
                _buildReadOnlyField(
                  value: _emailController.text.isEmpty ? 'Loading...' : _emailController.text,
                  icon: Icons.email_outlined,
                  isEmpty: _emailController.text.isEmpty,
                ),

                const SizedBox(height: 14),

                // ── Full name ─────────────────────────────────────────────
                _buildFieldLabel('Full Name'),
                const SizedBox(height: 6),
                _buildEditableField(
                  controller: _fullNameController,
                  hint: 'Enter your full name',
                  icon: Icons.person_outline,
                  capitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your full name' : null,
                ),

                const SizedBox(height: 14),

                // ── Phone ─────────────────────────────────────────────────
                _buildFieldLabel('Phone Number'),
                const SizedBox(height: 6),
                _buildEditableField(
                  controller: _phoneController,
                  hint: 'Enter phone number',
                  icon: Icons.phone_outlined,
                  keyboard: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Please enter your phone number';
                    final d = v.replaceAll(RegExp(r'\D'), '');
                    if (d.length < 10 || d.length > 11) return 'Enter a valid 10-11 digit number';
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                // ── Address ───────────────────────────────────────────────
                _buildFieldLabel('Address'),
                const SizedBox(height: 6),
                _buildEditableField(
                  controller: _addressController,
                  hint: 'Enter your address',
                  icon: Icons.location_on_outlined,
                  maxLines: 3,
                  capitalization: TextCapitalization.sentences,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your address' : null,
                ),

                const SizedBox(height: 20),

                // ── Error / Success banners ───────────────────────────────
                if (_errorMessage != null) ...[
                  _statusBanner(
                    icon: Icons.error_outline,
                    text: _errorMessage!,
                    iconColor: Colors.red.shade700,
                    bgColor: Colors.red.shade50,
                    borderColor: Colors.red.shade200,
                    textColor: Colors.red.shade700,
                  ),
                  const SizedBox(height: 10),
                ],
                if (_successMessage != null) ...[
                  _statusBanner(
                    icon: Icons.check_circle,
                    text: _successMessage!,
                    iconColor: Colors.green.shade700,
                    bgColor: Colors.green.shade50,
                    borderColor: Colors.green.shade200,
                    textColor: Colors.green.shade700,
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Save button ───────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
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
                      Text('Saving...', style: TextStyle(fontSize: 14)),
                    ])
                        : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.save_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Save Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),

                const SizedBox(height: 10),

                // ── Cancel ────────────────────────────────────────────────
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: lightText, fontSize: 13)),
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

  Widget _buildReadOnlyField({required String value, required IconData icon, bool isEmpty = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(children: [
        Icon(icon, color: lightText, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: isEmpty ? lightText : darkText, fontSize: 14),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(10)),
          child: Text('Read only', style: TextStyle(color: primaryPurple, fontSize: 9, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _buildEditableField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType keyboard = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: TextFormField(
        controller: controller,
        style: TextStyle(color: darkText, fontSize: 14),
        keyboardType: keyboard,
        textCapitalization: capitalization,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: lightText, fontSize: 13),
          border: InputBorder.none,
          prefixIcon: Padding(
            padding: EdgeInsets.only(bottom: maxLines > 1 ? 32 : 0),
            child: Icon(icon, color: primaryPurple, size: 18),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: maxLines > 1 ? 16 : 0,
            vertical: 13,
          ),
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
}