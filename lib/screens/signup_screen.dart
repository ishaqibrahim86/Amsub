import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/auth_service.dart';
import 'pin_setup_screen.dart'; // Create this screen

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  // Brand colors
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue = const Color(0xFF3B82F6);
  final Color lightPurple = const Color(0xFFF0EEFF);
  final Color darkText = const Color(0xFF1E293B);
  final Color lightText = const Color(0xFF64748B);

  final _formKey = GlobalKey<FormState>();
  final _storage = const FlutterSecureStorage();

  final fullNameController = TextEditingController();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final referralController = TextEditingController();
  final passwordController = TextEditingController();

  final FocusNode _usernameFocus = FocusNode();

  bool isLoading = false;
  bool _obscurePassword = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _usernameFocus.requestFocus();
    });
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final url = Uri.parse('https://amsubnig.com/rest-auth/registration/');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "username": usernameController.text.trim(),
          "email": emailController.text.trim(),
          "password1": passwordController.text,
          "password2": passwordController.text,
          "Phone": phoneController.text.trim(),
          "FullName": fullNameController.text.trim(),
          "Address": addressController.text.trim(),
          "referer_username": referralController.text.trim(),
        }),
      );

      print('Response code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final token = data['key'] as String?;

        if (token != null && token.isNotEmpty) {
          // Save token
          await AuthService.saveToken(token);

          // Save user data for later use
          await _storage.write(key: 'username', value: usernameController.text.trim());
          await _storage.write(key: 'full_name', value: fullNameController.text.trim());

          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Registration successful! Please set up your PIN.'),
                backgroundColor: primaryPurple,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );

            // Navigate to PIN Setup Screen
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const PinSetupScreen()),
            );
          }
        } else {
          setState(() {
            errorMessage = 'Registration failed: No token received';
            isLoading = false;
          });
        }
      } else {
        final decoded = jsonDecode(response.body);
        String errorMsg = 'Registration failed';

        // Extract error message from response
        if (decoded is Map) {
          if (decoded.containsKey('username')) {
            errorMsg = 'Username: ${decoded['username'] is List ? decoded['username'].first : decoded['username']}';
          } else if (decoded.containsKey('email')) {
            errorMsg = 'Email: ${decoded['email'] is List ? decoded['email'].first : decoded['email']}';
          } else if (decoded.containsKey('password1')) {
            errorMsg = 'Password: ${decoded['password1'] is List ? decoded['password1'].first : decoded['password1']}';
          } else if (decoded.containsKey('non_field_errors')) {
            errorMsg = decoded['non_field_errors'] is List
                ? decoded['non_field_errors'].first
                : decoded['non_field_errors'].toString();
          } else {
            errorMsg = decoded.values.first.toString();
          }
        }

        setState(() {
          errorMessage = errorMsg;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Exception during registration: $e');
      setState(() {
        errorMessage = 'Something went wrong. Please try again.';
        isLoading = false;
      });
    }
  }

  Widget _textField(TextEditingController controller, String label,
      {bool isPassword = false,
        TextInputType inputType = TextInputType.text,
        FocusNode? focusNode}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.replaceAll(' [Optional]', ''),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: darkText,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              obscureText: isPassword ? _obscurePassword : false,
              keyboardType: inputType,
              style: TextStyle(color: darkText),
              validator: (value) =>
              (value == null || value.isEmpty) && !label.contains('[Optional]')
                  ? 'Please enter ${label.replaceAll(' [Optional]', '')}'
                  : null,
              decoration: InputDecoration(
                hintText: 'Enter ${label.replaceAll(' [Optional]', '')}',
                hintStyle: TextStyle(color: lightText),
                border: InputBorder.none,
                prefixIcon: Icon(
                  _getIconForField(label),
                  color: primaryPurple,
                  size: 20,
                ),
                suffixIcon: isPassword
                    ? IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: lightText,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (label.contains('[Optional]'))
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 12),
              child: Text(
                'Optional',
                style: TextStyle(
                  fontSize: 11,
                  color: lightText,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getIconForField(String label) {
    if (label.contains('Full Name')) return Icons.person_outline;
    if (label.contains('Username')) return Icons.alternate_email;
    if (label.contains('Email')) return Icons.email_outlined;
    if (label.contains('Phone')) return Icons.phone_outlined;
    if (label.contains('Address')) return Icons.location_on_outlined;
    if (label.contains('Referral')) return Icons.card_giftcard;
    if (label.contains('Password')) return Icons.lock_outline;
    return Icons.edit;
  }

  @override
  void dispose() {
    _usernameFocus.dispose();
    fullNameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    addressController.dispose();
    referralController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Create Account',
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
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
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
                      Icons.person_add_outlined,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                const Center(
                  child: Text(
                    'Join AMSUBNIG Today',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                Center(
                  child: Text(
                    'Create an account to get started',
                    style: TextStyle(
                      fontSize: 14,
                      color: lightText,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Form Fields
                _textField(fullNameController, 'Full Name'),
                _textField(usernameController, 'Username', focusNode: _usernameFocus),
                _textField(emailController, 'Email Address', inputType: TextInputType.emailAddress),
                _textField(phoneController, 'Phone Number', inputType: TextInputType.phone),
                _textField(addressController, 'House Address'),
                _textField(referralController, 'Referral username [Optional]'),
                _textField(passwordController, 'Password', isPassword: true),

                const SizedBox(height: 16),

                // Error Message
                if (errorMessage != null)
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
                            errorMessage!,
                            style: TextStyle(color: Colors.red[700], fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Sign Up Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryPurple,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[400],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 3,
                      shadowColor: primaryPurple.withOpacity(0.5),
                    ),
                    child: isLoading
                        ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text('Creating Account...', style: TextStyle(fontSize: 16)),
                      ],
                    )
                        : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_add, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Sign Up',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Sign In Link
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(color: lightText),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Text(
                          'Sign In',
                          style: TextStyle(
                            color: primaryPurple,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Terms and Privacy
                Center(
                  child: Text(
                    'By signing up, you agree to our Terms and Privacy Policy',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: lightText,
                    ),
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