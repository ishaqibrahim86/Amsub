import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../services/pin_auth_service.dart';

/// Beautiful 5-digit PIN entry dialog.
///
/// • Custom PIN keypad (no system keyboard)
/// • Shake animation on wrong PIN
/// • Calls  GET /api/checkpin/?pin=XXXXX
/// • On first success: offers to enable biometric for future transactions
/// • Returns true (authenticated) or false (cancelled / max attempts)
class PinAuthDialog extends StatefulWidget {
  const PinAuthDialog({super.key});

  @override
  State<PinAuthDialog> createState() => _PinAuthDialogState();
}

class _PinAuthDialogState extends State<PinAuthDialog>
    with SingleTickerProviderStateMixin {
  // ── Brand colors (keep in sync with your app theme) ─────────────────────
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);
  static const Color errorRed      = Color(0xFFEF4444);

  static const int _pinLength    = 5;
  static const int _maxAttempts  = 5;

  // ── State ────────────────────────────────────────────────────────────────
  final List<String> _digits = [];
  bool _isVerifying = false;
  bool _obscure     = true;
  String? _errorMsg;
  int _attempts     = 0;
  bool _locked      = false;

  // Shake animation
  late final AnimationController _shakeController;
  late final Animation<double>   _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  // ── Input logic ──────────────────────────────────────────────────────────

  void _addDigit(String d) {
    if (_locked || _isVerifying || _digits.length >= _pinLength) return;
    HapticFeedback.lightImpact();
    setState(() {
      _digits.add(d);
      _errorMsg = null;
    });
    if (_digits.length == _pinLength) _verifyPin();
  }

  void _removeDigit() {
    if (_locked || _isVerifying || _digits.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _digits.removeLast());
  }

  void _clearAll() {
    setState(() { _digits.clear(); _errorMsg = null; });
  }

  // ── API call ─────────────────────────────────────────────────────────────

  Future<void> _verifyPin() async {
    final pin = _digits.join();
    setState(() { _isVerifying = true; _errorMsg = null; });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        _handleError('Session expired. Please log in again.');
        return;
      }

      final response = await http
          .get(
        Uri.parse('https://amsubnig.com/api/checkpin/?pin=$pin'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
      )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        await _handleSuccess();
      } else if (response.statusCode == 400) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        _handleError(body['error']?.toString() ?? 'Incorrect PIN');
      } else {
        _handleError('Verification failed. Please try again.');
      }
    } catch (_) {
      _handleError('Network error. Check your connection.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _handleSuccess() async {
    HapticFeedback.mediumImpact();

    // Offer biometric enrollment only if:
    //  - device supports it
    //  - user has NOT already enabled it
    final supports     = await PinAuthService.deviceSupportsBiometrics();
    final alreadyOn    = await PinAuthService.isBiometricEnabled();

    if (supports && !alreadyOn && mounted) {
      final enable = await _showEnableBiometricDialog();
      if (enable == true) {
        await PinAuthService.setBiometricEnabled(true);
      }
    }

    if (mounted) Navigator.of(context).pop(true); // ✅ authenticated
  }

  void _handleError(String msg) {
    _attempts++;
    HapticFeedback.heavyImpact();

    if (_attempts >= _maxAttempts) {
      setState(() {
        _locked   = true;
        _errorMsg = 'Too many attempts. Please try again later.';
        _digits.clear();
      });
      // Auto-close after 3 s and return false
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.of(context).pop(false);
      });
      return;
    }

    setState(() {
      _errorMsg = '$msg  (${_maxAttempts - _attempts} attempts left)';
      _digits.clear();
    });
    _shakeController.forward(from: 0);
  }

  // ── Biometric enrollment prompt ──────────────────────────────────────────

  Future<bool?> _showEnableBiometricDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.fingerprint, color: primaryPurple, size: 26),
          SizedBox(width: 10),
          Text('Enable Fingerprint?', style: TextStyle(fontSize: 17)),
        ]),
        content: const Text(
          'Would you like to use your fingerprint instead of a PIN for future transactions? You can change this in Settings at any time.',
          style: TextStyle(fontSize: 14, color: lightText, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not Now', style: TextStyle(color: lightText)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  // ── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: primaryPurple.withOpacity(0.18),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 28),
                  _buildPinDots(),
                  const SizedBox(height: 12),
                  _buildErrorArea(),
                  const SizedBox(height: 20),
                  _buildKeypad(),
                  const SizedBox(height: 20),
                  _buildCancelButton(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryPurple, Color(0xFF9B7DFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transaction PIN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Enter your 5-digit security PIN',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          // Obscure toggle
          IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: Colors.white70,
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
            tooltip: _obscure ? 'Show PIN' : 'Hide PIN',
          ),
        ],
      ),
    );
  }

  // ── PIN dots ─────────────────────────────────────────────────────────────

  Widget _buildPinDots() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (_, child) {
        final offset = _shakeAnimation.value == 0
            ? 0.0
            : (8 * (0.5 - (_shakeAnimation.value % 1).abs())) *
            (_shakeAnimation.value < 0.5 ? 1 : -1);
        return Transform.translate(
          offset: Offset(offset * 12, 0),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_pinLength, (i) {
          final filled = i < _digits.length;
          final isLast = i == _digits.length - 1;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: filled ? 18 : 16,
            height: filled ? 18 : 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _locked
                  ? errorRed.withOpacity(0.3)
                  : filled
                  ? primaryPurple
                  : Colors.transparent,
              border: Border.all(
                color: _locked
                    ? errorRed
                    : filled
                    ? primaryPurple
                    : Colors.grey.shade300,
                width: 2,
              ),
              boxShadow: filled && !_locked
                  ? [BoxShadow(color: primaryPurple.withOpacity(0.4), blurRadius: 8, spreadRadius: 1)]
                  : [],
            ),
            // Show actual digit if not obscured and filled
            child: (!_obscure && filled)
                ? Center(
              child: Text(
                _digits[i],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
                : null,
          );
        }),
      ),
    );
  }

  // ── Error / status area ──────────────────────────────────────────────────

  Widget _buildErrorArea() {
    if (_isVerifying) {
      return const SizedBox(
        height: 32,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: primaryPurple,
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Verifying…',
              style: TextStyle(color: lightText, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_errorMsg != null) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: errorRed.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: errorRed.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: errorRed, size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _errorMsg!,
                  style: const TextStyle(color: errorRed, fontSize: 12),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox(height: 36);
  }

  // ── Keypad ───────────────────────────────────────────────────────────────

  static const _keypadLayout = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['C', '0', '⌫'],
  ];

  Widget _buildKeypad() {
    return Column(
      children: _keypadLayout.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) => _buildKey(key)).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKey(String key) {
    final isSpecial = key == '⌫' || key == 'C';
    final isDisabled = _locked || _isVerifying;

    return GestureDetector(
      onTap: isDisabled ? null : () {
        if (key == '⌫') {
          _removeDigit();
        } else if (key == 'C') {
          _clearAll();
        } else {
          _addDigit(key);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 72,
        height: 62,
        decoration: BoxDecoration(
          color: isDisabled
              ? Colors.grey.shade100
              : isSpecial
              ? lightPurple
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDisabled
                ? Colors.grey.shade200
                : isSpecial
                ? primaryPurple.withOpacity(0.2)
                : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: isDisabled
                  ? Colors.transparent
                  : Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: key == '⌫'
              ? Icon(
            Icons.backspace_outlined,
            size: 22,
            color: isDisabled ? Colors.grey.shade400 : primaryPurple,
          )
              : Text(
            key,
            style: TextStyle(
              fontSize: key == 'C' ? 14 : 22,
              fontWeight: FontWeight.w600,
              color: isDisabled
                  ? Colors.grey.shade400
                  : isSpecial
                  ? primaryPurple
                  : darkText,
              letterSpacing: key == 'C' ? 0.5 : 0,
            ),
          ),
        ),
      ),
    );
  }

  // ── Cancel button ────────────────────────────────────────────────────────

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: _isVerifying ? null : () => Navigator.of(context).pop(false),
        style: TextButton.styleFrom(
          foregroundColor: lightText,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: const Text(
          'Cancel',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}