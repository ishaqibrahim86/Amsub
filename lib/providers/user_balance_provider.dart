// providers/user_balance_provider.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../services/auth_service.dart';

class UserBalanceProvider extends ChangeNotifier {
  double _balance = 0.0;
  double _bonusBalance = 0.0;
  Timer? _balanceTimer;
  bool _isInitialized = false;

  double get balance => _balance;
  double get bonusBalance => _bonusBalance;

  UserBalanceProvider() {
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    // Fetch immediately on start
    _fetchBalance();
    // Then every 3 seconds
    _balanceTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchBalance(isBackground: true);
    });
  }

  Future<void> _fetchBalance({bool isBackground = false}) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return;

      final response = await http.get(
        Uri.parse('https://amsubnig.com/api/user/'),
        headers: {'Authorization': 'Token $token'},
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'] ?? {};

        final newBalance = double.tryParse(user['Account_Balance']?.toString() ?? '0') ?? 0.0;
        final newBonus = double.tryParse(user['bonus_balance']?.toString() ?? '0') ?? 0.0;

        // Only update and notify if values actually changed
        if (_balance != newBalance || _bonusBalance != newBonus) {
          _balance = newBalance;
          _bonusBalance = newBonus;

          if (isBackground) {
            // Use addPostFrameCallback to avoid calling setState during build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              notifyListeners();
            });
          } else {
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('Balance fetch error: $e');
    }
  }

  // Manual refresh method
  Future<void> refresh() async {
    await _fetchBalance(isBackground: false);
  }

  // Update balance after transactions
  void updateBalance(double newBalance, double newBonusBalance) {
    _balance = newBalance;
    _bonusBalance = newBonusBalance;
    notifyListeners();
  }

  @override
  void dispose() {
    _balanceTimer?.cancel();
    super.dispose();
  }
}