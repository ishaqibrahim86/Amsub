import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';

class BonusScreen extends StatefulWidget {
  final double bonusBalance;  // passed from dashboard
  final double mainBalance;   // passed from dashboard
  final Function(double) onTransferSuccess;  // callback to update dashboard balances

  const BonusScreen({
    super.key,
    required this.bonusBalance,
    required this.mainBalance,
    required this.onTransferSuccess,
  });

  @override
  State<BonusScreen> createState() => _BonusScreenState();
}

class _BonusScreenState extends State<BonusScreen> {
  // Brand colors
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue = const Color(0xFF3B82F6);
  final Color lightPurple = const Color(0xFFF0EEFF);
  final Color darkText = const Color(0xFF1E293B);
  final Color lightText = const Color(0xFF64748B);

  final TextEditingController _amountController = TextEditingController();
  bool isLoading = false;
  bool isTransferring = false;
  String? errorMessage;

  // Local state for balances that refresh
  late double _bonusBalance;
  late double _mainBalance;

  List<Map<String, dynamic>> transferHistory = [];

  @override
  void initState() {
    super.initState();
    _bonusBalance = widget.bonusBalance;
    _mainBalance = widget.mainBalance;
    _fetchTransferHistory();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchTransferHistory() async {
    setState(() => isLoading = true);

    try {
      final token = await AuthService.getToken();
      if (token == null) return;

      final response = await http.get(
        Uri.parse('https://amsubnig.com/api/bonus_transfer/'),
        headers: {'Authorization': 'Token $token'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          transferHistory = data.map((item) => {
            'amount': item['amount']?.toString() ?? '0',
            'date': item['create_date']?.toString() ?? '',
            'status': item['Status'] ?? 'Completed',
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('History fetch error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _refreshBalances() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return;

      final response = await http.get(
        Uri.parse('https://amsubnig.com/api/user/'),
        headers: {'Authorization': 'Token $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userData = data['user'] as Map<String, dynamic>?;

        if (userData != null) {
          setState(() {
            _mainBalance = double.tryParse(userData['Account_Balance']?.toString() ?? '0') ?? 0.0;
            _bonusBalance = double.tryParse(userData['bonus_balance']?.toString() ?? '0') ?? 0.0;
          });

          // Update dashboard
          widget.onTransferSuccess(_mainBalance);
        }
      }
    } catch (e) {
      debugPrint('Balance refresh error: $e');
    }
  }

  Future<void> _transferBonus() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      setState(() { errorMessage = 'Enter amount'; });
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      setState(() { errorMessage = 'Enter valid amount'; });
      return;
    }

    if (amount > _bonusBalance) {
      setState(() { errorMessage = 'Amount exceeds your bonus balance'; });
      return;
    }

    setState(() {
      isTransferring = true;
      errorMessage = null;
    });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() { errorMessage = 'Session expired'; isTransferring = false; });
        return;
      }

      final response = await http.post(
        Uri.parse('https://amsubnig.com/api/bonus_transfer/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'amount': amount}),
      );

      if (response.statusCode == 201) {
        // Update local balances
        setState(() {
          _bonusBalance -= amount;
          _mainBalance += amount;
          _amountController.clear();
          isTransferring = false;
        });

        // Update dashboard
        widget.onTransferSuccess(_mainBalance);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('₦${amount.toStringAsFixed(2)} transferred to main wallet!'),
            backgroundColor: primaryPurple,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        // Refresh history and verify balances from server
        await _fetchTransferHistory();
        await _refreshBalances();
      } else {
        setState(() {
          errorMessage = 'Transfer failed: ${response.body}';
          isTransferring = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
        isTransferring = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Referral Bonus',
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
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: primaryPurple),
            onPressed: () async {
              await _refreshBalances();
              await _fetchTransferHistory();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current Balances Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryPurple, primaryBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: primaryPurple.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Your Balances',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Referral Bonus',
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₦${_bonusBalance.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.card_giftcard, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Bonus',
                              style: TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Main Wallet',
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₦${_mainBalance.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.account_balance, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Main',
                              style: TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Transfer Form Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: lightPurple,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.swap_horiz, color: primaryPurple, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Transfer to Main Wallet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: darkText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Amount Field
                  Text(
                    'Amount to Transfer',
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
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: darkText),
                      decoration: InputDecoration(
                        hintText: 'Enter amount',
                        hintStyle: TextStyle(color: lightText),
                        border: InputBorder.none,
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 4),
                          child: Text(
                            '₦',
                            style: TextStyle(
                              color: primaryPurple,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 40),
                        suffix: Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Text(
                            'MAX',
                            style: TextStyle(
                              color: primaryPurple,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 12),
                    child: Text(
                      'Available: ₦${_bonusBalance.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: lightText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Transfer Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (isTransferring || isLoading) ? null : _transferBonus,
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
                      child: isTransferring
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
                          const Text('Transferring...', style: TextStyle(fontSize: 16)),
                        ],
                      )
                          : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.arrow_forward, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Transfer Now',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Error Message
                  if (errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
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
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Transfer History Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: lightPurple,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.history, color: primaryPurple, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Transfer History',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: darkText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // History List
                  if (isLoading && transferHistory.isEmpty)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ))
                  else if (transferHistory.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.history_toggle_off, size: 48, color: lightText),
                            const SizedBox(height: 12),
                            Text(
                              'No transfers yet',
                              style: TextStyle(color: lightText, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: transferHistory.length,
                      itemBuilder: (context, index) {
                        final tx = transferHistory[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: lightPurple,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.arrow_forward, color: primaryPurple, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '₦${tx['amount']} transferred',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: darkText,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      tx['date'] ?? 'Date unknown',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: lightText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green[700], size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Completed',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}