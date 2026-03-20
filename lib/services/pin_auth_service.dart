import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../widgets/pin_auth_dialog.dart';

/// Central PIN / biometric authentication service.
///
/// Usage (anywhere in the app, before a sensitive action):
/// ```dart
/// final ok = await PinAuthService.verify(context);
/// if (!ok) return;          // user cancelled or failed
/// // ... proceed with purchase / transfer / etc.
/// ```
class PinAuthService {
  PinAuthService._();

  static const _storage = FlutterSecureStorage();
  static const _biometricKey = 'pin_auth_biometric_enabled';
  static const _pinSetKey    = 'pin_auth_pin_set'; // future: local PIN cache

  static final _localAuth = LocalAuthentication();

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns `true` when the user has been successfully authenticated.
  /// Shows biometric prompt first (if enabled), falls back to PIN dialog.
  static Future<bool> verify(BuildContext context) async {
    // 1. Try biometric if the user has opted in
    if (await isBiometricEnabled()) {
      final bioOk = await _authenticateWithBiometric();
      if (bioOk) return true;
      // Fall through → show PIN as backup
    }

    // 2. Show PIN entry dialog
    if (!context.mounted) return false;
    return await _showPinDialog(context);
  }

  /// Whether the user has previously enabled biometric login.
  static Future<bool> isBiometricEnabled() async {
    final stored = await _storage.read(key: _biometricKey);
    return stored == 'true';
  }

  /// Explicitly enable / disable biometric (called from settings screen).
  static Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _biometricKey, value: enabled.toString());
  }

  /// Clear all stored auth preferences (call on logout).
  static Future<void> clear() async {
    await _storage.delete(key: _biometricKey);
    await _storage.delete(key: _pinSetKey);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Biometric helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns true if the device supports biometrics AND has enrolled biometrics.
  static Future<bool> deviceSupportsBiometrics() async {
    try {
      final canCheck  = await _localAuth.canCheckBiometrics;
      final isSupport = await _localAuth.isDeviceSupported();
      if (!canCheck || !isSupport) return false;

      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _authenticateWithBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Use your fingerprint to confirm this transaction',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PIN dialog
  // ─────────────────────────────────────────────────────────────────────────

  static Future<bool> _showPinDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (_) => const PinAuthDialog(),
    );
    return result == true;
  }
}