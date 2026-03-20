import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';
import 'main_screen.dart';
import 'login_screen.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback? onUnlock;
  final String? username;

  const LockScreen({super.key, this.onUnlock, this.username});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  // Brand colors
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue = const Color(0xFF3B82F6);
  final Color lightPurple = const Color(0xFFF0EEFF);
  final Color darkText = const Color(0xFF1E293B);
  final Color lightText = const Color(0xFF64748B);

  final LocalAuthentication auth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();
  final _passwordController = TextEditingController();

  String? _username;
  String? _fullName;
  String? _errorMessage;
  bool _isAuthenticating = false;
  bool _canUseBiometrics = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkBiometrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryBiometricUnlock();
    });
  }

  Future<void> _loadUserData() async {
    if (widget.username != null && widget.username!.isNotEmpty) {
      setState(() {
        _username = widget.username;
      });
    } else {
      final storedUsername = await _storage.read(key: 'username');
      final storedFullName = await _storage.read(key: 'full_name');

      if (mounted) {
        setState(() {
          _username = storedUsername ?? 'User';
          _fullName = storedFullName;
        });
      }
    }

    final storedFullName = await _storage.read(key: 'full_name');
    if (mounted) {
      setState(() {
        _fullName = storedFullName;
      });
    }

    debugPrint('=== LOADED USER DATA ===');
    debugPrint('Username: $_username');
    debugPrint('Full Name: $_fullName');
  }

  Future<void> _checkBiometrics() async {
    try {
      final canAuthenticate = await auth.canCheckBiometrics;
      final isDeviceSupported = await auth.isDeviceSupported();

      if (mounted) {
        setState(() {
          _canUseBiometrics = canAuthenticate && isDeviceSupported;
        });

        debugPrint('=== BIOMETRIC DEBUG INFO ===');
        debugPrint('Can use biometrics: $_canUseBiometrics');
        debugPrint('Device supports biometrics: $isDeviceSupported');

        final availableBiometrics = await auth.getAvailableBiometrics();
        debugPrint('Biometric types available: $availableBiometrics');
      }
    } catch (e) {
      debugPrint('❌ Biometrics check error: $e');
    }
  }

  Future<void> _tryBiometricUnlock() async {
    if (!_canUseBiometrics || _isAuthenticating) return;
    if (!mounted) return;

    debugPrint('🔐 Attempting biometric authentication...');
    setState(() => _isAuthenticating = true);

    try {
      final didAuthenticate = await auth.authenticate(
        localizedReason: 'Scan your fingerprint to unlock',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (didAuthenticate && mounted) {
        debugPrint('✅ Biometric authentication successful');
        _unlockAndGoToMainScreen();
      } else if (mounted) {
        setState(() {
          _errorMessage = 'Biometric authentication failed';
          _isAuthenticating = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Biometric authentication error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Biometric error. Use password.';
          _isAuthenticating = false;
        });
      }
    }
  }

  Future<void> _verifyPassword() async {
    final enteredPassword = _passwordController.text.trim();
    if (enteredPassword.isEmpty) {
      if (mounted) setState(() => _errorMessage = 'Enter your password');
      return;
    }

    if (!mounted) return;

    setState(() => _isAuthenticating = true);

    try {
      final response = await http.post(
        Uri.parse('https://amsubnig.com/rest-auth/login/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': _username ?? 'Admin',
          'password': enteredPassword,
        }),
      );

      if (response.statusCode == 200 && mounted) {
        final result = json.decode(response.body);

        await AuthService.saveToken(result['key'] ?? result['token']);

        if (_username != null && _username != 'User') {
          await _storage.write(key: 'username', value: _username);
        }

        if (result['user'] != null && result['user']['full_name'] != null) {
          await _storage.write(key: 'full_name', value: result['user']['full_name']);
          if (mounted) {
            setState(() {
              _fullName = result['user']['full_name'];
            });
          }
        }

        _unlockAndGoToMainScreen();
      } else if (mounted) {
        setState(() {
          _errorMessage = 'Incorrect password';
          _isAuthenticating = false;
          _passwordController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error';
          _isAuthenticating = false;
        });
      }
    }
  }

  void _unlockAndGoToMainScreen() {
    if (!mounted) return;

    widget.onUnlock?.call();

    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  Future<void> _signOut() async {
    await AuthService.logout();
    if (mounted) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
        Navigator.pushReplacementNamed(context, '/login');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  Future<void> _switchAccount() async {
    await AuthService.logout();
    if (mounted) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
        Navigator.pushReplacementNamed(context, '/login');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  String _getDisplayName() {
    if (_fullName != null && _fullName!.isNotEmpty) {
      return _fullName!.toUpperCase();
    }
    return _username?.toUpperCase() ?? 'USER';
  }

  String _getInitial() {
    if (_fullName != null && _fullName!.isNotEmpty) {
      return _fullName![0].toUpperCase();
    }
    return _username?.substring(0, 1).toUpperCase() ?? 'U';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Avatar with user initial - Brand gradient
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [primaryPurple, primaryBlue],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryPurple.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _getInitial(),
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Welcome Header
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Welcome',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w300,
                          color: lightText,
                        ),
                      ),
                      Text(
                        'Back, ${_getDisplayName()}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: darkText,
                        ),
                      ),
                      if (_fullName != null && _fullName!.isNotEmpty && _username != null)
                        Text(
                          '@$_username',
                          style: TextStyle(
                            fontSize: 16,
                            color: lightText,
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Subtitle
                Center(
                  child: Text(
                    'Sign in to your account to continue',
                    style: TextStyle(
                      fontSize: 16,
                      color: lightText,
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Password Label
                Text(
                  'Password',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: darkText,
                  ),
                ),
                const SizedBox(height: 8),

                // Password Field with Eye Icon
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _errorMessage != null ? Colors.red : Colors.grey[200]!,
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: TextStyle(color: darkText),
                    decoration: InputDecoration(
                      hintText: 'Enter your password',
                      hintStyle: TextStyle(color: lightText),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      prefixIcon: Icon(
                        Icons.lock_outline,
                        color: primaryPurple,
                        size: 22,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_passwordController.text.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.close, color: lightText, size: 20),
                              onPressed: () {
                                setState(() {
                                  _passwordController.clear();
                                  _errorMessage = null;
                                });
                              },
                            ),
                          IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: lightText,
                              size: 22,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    onChanged: (value) {
                      if (_errorMessage != null) {
                        setState(() => _errorMessage = null);
                      }
                    },
                    onSubmitted: (_) => _verifyPassword(),
                  ),
                ),

                // Error Message
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 16),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                // Forgot Password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/forgot-password');
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: primaryPurple,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Sign In Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isAuthenticating ? null : _verifyPassword,
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
                    child: _isAuthenticating
                        ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Signing In...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                        : const Text(
                      'Sign In',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // OR Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Or login with',
                        style: TextStyle(
                          color: lightText,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
                  ],
                ),

                const SizedBox(height: 20),

                // Fingerprint Button
                if (_canUseBiometrics)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _isAuthenticating ? null : _tryBiometricUnlock,
                      icon: Icon(
                        Icons.fingerprint,
                        size: 28,
                        color: primaryPurple,
                      ),
                      label: Text(
                        'Use Fingerprint',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: primaryPurple,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: primaryPurple.withOpacity(0.3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 40),

                // Switch Account
                Center(
                  child: TextButton(
                    onPressed: _switchAccount,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                    ),
                    child: RichText(
                      text: TextSpan(
                        text: 'Not ${_getDisplayName()}? ',
                        style: TextStyle(
                          color: lightText,
                          fontSize: 15,
                        ),
                        children: [
                          TextSpan(
                            text: 'Switch Account',
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

                const SizedBox(height: 8),

                // Sign Out Link
                Center(
                  child: TextButton(
                    onPressed: _signOut,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                    ),
                    child: RichText(
                      text: TextSpan(
                        text: 'Want to use a different account? ',
                        style: TextStyle(
                          color: lightText,
                          fontSize: 15,
                        ),
                        children: [
                          TextSpan(
                            text: 'Sign Out',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
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

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }
}