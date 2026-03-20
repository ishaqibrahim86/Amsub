// screens/pin_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';
import 'main_screen.dart'; // Your main dashboard screen

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  // Brand colors
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue = const Color(0xFF3B82F6);
  final Color lightPurple = const Color(0xFFF0EEFF);
  final Color darkText = const Color(0xFF1E293B);
  final Color lightText = const Color(0xFF64748B);

  final _formKey = GlobalKey<FormState>();

  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _isSaving = false;
  bool _obscurePin = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _setupPin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() {
          _error = 'Session expired. Please login again.';
          _isSaving = false;
        });
        return;
      }

      // Based on your backend PINSETUPAPIView, it expects GET parameters
      final url = Uri.parse(
          'https://amsubnig.com/api/pin/?'
              'pin1=${_pinController.text}&'
              'pin2=${_confirmPinController.text}'
      );

      debugPrint('📤 Setting up PIN with URL: $url');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Token $token',
        },
      );

      debugPrint('📥 Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final resp = jsonDecode(response.body);

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(resp['message'] ?? 'PIN setup successfully!'),
              backgroundColor: primaryPurple,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );

          // Navigate to main dashboard
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainScreen()),
          );
        }
      } else {
        try {
          final resp = jsonDecode(response.body);
          setState(() {
            _error = resp['error'] ?? 'Failed to setup PIN';
            _isSaving = false;
          });
        } catch (e) {
          setState(() {
            _error = 'Server error (${response.statusCode})';
            _isSaving = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Network error. Please check your connection.';
        _isSaving = false;
      });
    }
  }

  Future<bool> _onWillPop() async {
    // Prevent going back to signup screen
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            'Setup Transaction PIN',
            style: TextStyle(color: darkText, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: primaryPurple,
          elevation: 0,
          automaticallyImplyLeading: false, // Remove back button
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
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
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.pin_outlined,
                        color: Colors.white,
                        size: 60,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Center(
                    child: Text(
                      'Set Your Transaction PIN',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Center(
                    child: Text(
                      'Your PIN will be used for all transactions',
                      style: TextStyle(
                        fontSize: 14,
                        color: lightText,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // PIN Field
                  Text(
                    'Create PIN',
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
                      controller: _pinController,
                      obscureText: _obscurePin,
                      keyboardType: TextInputType.number,
                      maxLength: 5,
                      style: TextStyle(color: darkText),
                      decoration: InputDecoration(
                        hintText: 'Enter 5-digit PIN',
                        hintStyle: TextStyle(color: lightText),
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.lock_outline, color: primaryPurple, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePin ? Icons.visibility_off : Icons.visibility,
                            color: lightText,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePin = !_obscurePin),
                        ),
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Please enter PIN';
                        }
                        if (val.length != 5) {
                          return 'PIN must be exactly 5 digits';
                        }
                        if (!RegExp(r'^[0-9]+$').hasMatch(val)) {
                          return 'PIN must contain only numbers';
                        }
                        return null;
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Confirm PIN Field
                  Text(
                    'Confirm PIN',
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
                      controller: _confirmPinController,
                      obscureText: _obscureConfirm,
                      keyboardType: TextInputType.number,
                      maxLength: 5,
                      style: TextStyle(color: darkText),
                      decoration: InputDecoration(
                        hintText: 'Confirm 5-digit PIN',
                        hintStyle: TextStyle(color: lightText),
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.lock_outline, color: primaryPurple, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                            color: lightText,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Please confirm PIN';
                        }
                        if (val != _pinController.text) {
                          return 'PINs do not match';
                        }
                        return null;
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // PIN Requirements Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: lightPurple,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryPurple.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: primaryPurple, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'PIN Requirements',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: darkText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildRequirementItem('Must be exactly 5 digits'),
                        _buildRequirementItem('Numbers only (0-9)'),
                        _buildRequirementItem('Keep your PIN secure and private'),
                        _buildRequirementItem('Never share your PIN with anyone'),
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

                  // Setup PIN Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _setupPin,
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
                      child: _isSaving
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
                          const Text('Setting up...', style: TextStyle(fontSize: 16)),
                        ],
                      )
                          : const Text(
                        'Complete Setup',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Skip for now (optional)
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const MainScreen()),
                        );
                      },
                      child: Text(
                        'Skip for now',
                        style: TextStyle(
                          color: lightText,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequirementItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: primaryPurple, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: lightText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}