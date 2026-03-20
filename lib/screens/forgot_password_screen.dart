import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // Brand colors
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue = const Color(0xFF3B82F6);
  final Color lightPurple = const Color(0xFFF0EEFF);
  final Color darkText = const Color(0xFF1E293B);
  final Color lightText = const Color(0xFF64748B);

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  String? _successMessage;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _successMessage = null;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('https://amsubnig.com/rest-auth/password/reset/'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': _emailController.text.trim(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _successMessage = 'Password reset link has been sent to your email!';
          _isLoading = false;
        });

        // Auto pop after 4 seconds
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        try {
          final errorBody = jsonDecode(response.body);
          setState(() {
            _errorMessage = errorBody['email']?[0] ??
                errorBody['detail'] ??
                errorBody['non_field_errors']?[0] ??
                'Failed to send reset link. Please try again.';
            _isLoading = false;
          });
        } catch (_) {
          setState(() {
            _errorMessage = 'Server error. Please try again later.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Forgot Password',
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
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),

                  // Icon with brand gradient
                  Center(
                    child: Container(
                      width: 120,
                      height: 120,
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
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  const Center(
                    child: Text(
                      "Reset Your Password",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Subtitle
                  Center(
                    child: Text(
                      "Enter your email address and we'll send you a link to reset your password.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: lightText,
                        height: 1.4,
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Email Field Label
                  Text(
                    'Email Address',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: darkText,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Email Field
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(color: darkText),
                      decoration: InputDecoration(
                        hintText: 'example@domain.com',
                        hintStyle: TextStyle(color: lightText),
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.email_outlined, color: primaryPurple, size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _resetPassword(),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _resetPassword,
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
                      child: _isLoading
                          ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 2.5,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text('Sending...', style: TextStyle(fontSize: 16)),
                        ],
                      )
                          : const Text(
                        'Send Reset Link',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Success Message
                  if (_successMessage != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: TextStyle(color: Colors.green[700], fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Error Message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(16),
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
                              _errorMessage!,
                              style: TextStyle(color: Colors.red[700], fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Back to Login
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                      ),
                      child: RichText(
                        text: TextSpan(
                          text: 'Remember your password? ',
                          style: TextStyle(
                            color: lightText,
                            fontSize: 15,
                          ),
                          children: [
                            TextSpan(
                              text: 'Sign In',
                              style: TextStyle(
                                color: primaryPurple,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // App name footer
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'AMSUBNIG',
                      style: TextStyle(
                        fontSize: 12,
                        color: lightText.withOpacity(0.5),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}