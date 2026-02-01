import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'buy_data_screen.dart';
import 'buy_airtime_screen.dart';
import 'buy_electricity_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String userEmail;
  final double balance;
  final double referralBonus;

  const DashboardScreen({
    super.key,
    required this.userEmail,
    required this.balance,
    required this.referralBonus,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _storage = FlutterSecureStorage();

  double actualBalance = 0.0;
  double referralBonus = 0.0;
  List<Map<String, dynamic>> bankAccounts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    actualBalance = widget.balance;
    referralBonus = widget.referralBonus;
    fetchAccountDetails();
  }

  Future<void> fetchAccountDetails() async {
    try {
      final token = await _storage.read(key: 'authToken');
      if (token == null) {
        print('No auth token found');
        return;
      }

      print('Fetching user details with token: ${token.substring(0, 10)}...');

      final response = await http.get(
        Uri.parse('https://amsubnig.com/api/user/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
      );

      print('Response Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        // Debug: Print all keys to see structure
        print('Response keys: ${data.keys.toList()}');

        // Check if 'user' key exists
        if (data.containsKey('user')) {
          final Map<String, dynamic> userData = data['user'];

          // Debug: Print user keys
          print('User keys: ${userData.keys.toList()}');

          // Extract balance from user object - check multiple possible field names
          double? balance;
          String? balanceField;

          // Try different field names
          if (userData.containsKey('Account_Balance')) {
            balance = double.tryParse(userData['Account_Balance'].toString());
            balanceField = 'Account_Balance';
          } else if (userData.containsKey('account_balance')) {
            balance = double.tryParse(userData['account_balance'].toString());
            balanceField = 'account_balance';
          } else if (userData.containsKey('wallet_balance')) {
            balance = double.tryParse(userData['wallet_balance'].toString());
            balanceField = 'wallet_balance';
          } else if (userData.containsKey('balance')) {
            balance = double.tryParse(userData['balance'].toString());
            balanceField = 'balance';
          }

          print('Balance field found: $balanceField, Value: $balance');

          // Extract other user info
          double? bonus = double.tryParse((userData['bonus_balance'] ?? '0').toString());

          // Extract bank accounts if available (adjust based on actual API structure)
          List<Map<String, dynamic>> accounts = [];
          if (data.containsKey('banks')) {
            // Assuming banks is a list
            final banks = data['banks'];
            if (banks is List) {
              accounts = List<Map<String, dynamic>>.from(banks);
            }
          }

          setState(() {
            actualBalance = balance ?? widget.balance;
            referralBonus = bonus ?? widget.referralBonus;
            bankAccounts = accounts;
            isLoading = false;
          });

          print('Updated balance: $actualBalance, bonus: $referralBonus');

        } else {
          print('"user" key not found in response');
          setState(() {
            isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User data not found in response')),
          );
        }
      } else {
        print('API Error: ${response.statusCode}');
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch data: ${response.statusCode}')),
        );
      }
    } catch (e) {
      print('Account fetch error: $e');
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                isLoading = true;
              });
              fetchAccountDetails();
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {},
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back,', style: TextStyle(fontSize: 16)),
            Text(widget.userEmail,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('Available Balance', style: TextStyle(color: Colors.grey)),
            Text('₦${actualBalance.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.green)),
            Text('Referral Bonus: ₦${referralBonus.toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _dashboardButton('Fund Wallet', Icons.account_balance_wallet),
                _dashboardButton('Transactions', Icons.receipt_long),
                _dashboardButton('Wallet Summary', Icons.history),
                _dashboardButton('More', Icons.more_horiz),
              ],
            ),
            const SizedBox(height: 20),
            _bankCard(),
            const SizedBox(height: 20),
            Text('What would you like to do?',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                _gridItem('Buy Data', Icons.wifi, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const BuyDataScreen()),
                  );
                }),
                _gridItem('Data Coupon', Icons.confirmation_number, () {}),
                _gridItem('Buy Airtime', Icons.call, () {
                    Navigator.push(
                    context,
                    MaterialPageRoute(
                    builder: (context) => const BuyAirtimeScreen()),
                    );
                    }),
                _gridItem('Cable TV', Icons.tv, () {}),
                _gridItem('Bill Payment', Icons.lightbulb, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ElectricityPaymentScreen()),
                  );
                }),
                _gridItem('Education Pin', Icons.school, () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardButton(String label, IconData icon) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: Colors.orange.shade100,
          child: Icon(icon, color: Colors.orange),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _gridItem(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: Colors.blue),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _bankCard() {
    if (bankAccounts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Account Information',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('No bank accounts found in response'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fund Your Wallet With Any Of These Accounts',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ...bankAccounts.map((account) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade700,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account['accountNumber'] ?? 'N/A',
                        style: TextStyle(color: Colors.white, fontSize: 18)),
                    Text('ACCOUNT NAME',
                        style: TextStyle(color: Colors.white70)),
                    Text(account['accountName'] ?? 'N/A',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₦50 charge', style: TextStyle(color: Colors.white70)),
                    Text(account['bankName'] ?? 'N/A',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}