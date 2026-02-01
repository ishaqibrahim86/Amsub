import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BuyAirtimeScreen extends StatefulWidget {
  const BuyAirtimeScreen({super.key});

  @override
  State<BuyAirtimeScreen> createState() => _BuyAirtimeScreenState();
}

class _BuyAirtimeScreenState extends State<BuyAirtimeScreen> {
  final _storage = FlutterSecureStorage();
  final phoneController = TextEditingController();
  final amountController = TextEditingController();
  bool bypassValidation = true;

  // Available networks
  List<Map<String, dynamic>> networks = [];

  // Selected values
  String? selectedNetwork;
  String? selectedAirtimeType; // 'VTU' or 'Share and Sell'

  bool isLoading = true;
  bool isSubmitting = false;

  // Discount-related variables
  String? userType;
  Map<String, dynamic>? vtuPercentages;
  Map<String, dynamic>? shareAndSellPercentages;
  bool isLoadingDiscounts = false;

  // Pre-filled amounts
  final List<int> prefilledAmounts = [100, 200, 500, 1000, 2000, 5000, 10000];
  int? selectedPrefilledAmount;

  // Airtime types
  final List<Map<String, String>> airtimeTypes = [
    {'value': 'VTU', 'label': 'VTU Airtime', 'description': 'Direct airtime recharge'},
    {'value': 'Share and Sell', 'label': 'Share & Sell', 'description': 'Transfer airtime to others'},
  ];

  // Step completion tracking
  bool get isNetworkSelected => selectedNetwork != null;
  bool get isTypeSelected => selectedAirtimeType != null;
  bool get isPhoneValid => phoneController.text.isNotEmpty &&
      RegExp(r'^0[7-9][0-1]\d{8}$').hasMatch(phoneController.text.trim());
  bool get isAmountValid => amountController.text.isNotEmpty &&
      (double.tryParse(amountController.text) ?? 0) >= 50;
  bool get canShowBuyButton => isNetworkSelected && isTypeSelected && isPhoneValid && isAmountValid;

  @override
  void initState() {
    super.initState();
    fetchNetworks();
  }

  Future<void> fetchNetworks() async {
    setState(() => isLoading = true);

    try {
      final token = await _storage.read(key: 'authToken');
      if (token == null) {
        showError('User not logged in');
        return;
      }

      final response = await http.get(
        Uri.parse('https://amsubnig.com/api/network-plans/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final networkKeys = ['MTN', 'GLO', 'AIRTEL', '9MOBILE', 'SMILE'];

        final List<Map<String, dynamic>> networkList = [];

        for (final key in networkKeys) {
          if (data.containsKey(key)) {
            final networkInfo = data[key]['network_info'] as Map<String, dynamic>;
            networkList.add({
              'key': key,
              'name': key,
              'id': networkInfo['id'] ?? _getNetworkIdFromKey(key),
              'icon': _getNetworkIcon(key),
              'color': _getNetworkColor(key),
            });
          }
        }

        setState(() {
          networks = networkList;
        });

        debugPrint('✅ Loaded ${networks.length} networks for airtime');
      } else {
        showError('Failed to load networks');
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      showError('Connection error');
    } finally {
      setState(() => isLoading = false);
    }
  }

  // NEW METHOD: Fetch discount percentages
  Future<void> fetchDiscountPercentages() async {
    if (isLoadingDiscounts) return;

    setState(() => isLoadingDiscounts = true);

    try {
      final token = await _storage.read(key: 'authToken');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('https://amsubnig.com/api/user-discounts/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          userType = data['user_type'];
          vtuPercentages = Map<String, dynamic>.from(data['vtu_percentages'] ?? {});
          shareAndSellPercentages = Map<String, dynamic>.from(data['share_and_sell_percentages'] ?? {});
        });

        debugPrint('✅ Loaded discounts for user type: $userType');
      }
    } catch (e) {
      debugPrint('❌ Error fetching discounts: $e');
      // Don't show error to user - discounts are optional display
    } finally {
      setState(() => isLoadingDiscounts = false);
    }
  }

  IconData _getNetworkIcon(String network) {
    switch (network.toUpperCase()) {
      case 'MTN': return Icons.network_cell;
      case 'GLO': return Icons.wifi;
      case 'AIRTEL': return Icons.signal_cellular_alt;
      case '9MOBILE': return Icons.phone_android;
      case 'SMILE': return Icons.sentiment_very_satisfied;
      default: return Icons.sim_card;
    }
  }

  Color _getNetworkColor(String network) {
    switch (network.toUpperCase()) {
      case 'MTN': return const Color(0xFFFFCC00);
      case 'GLO': return const Color(0xFF00B140);
      case 'AIRTEL': return const Color(0xFFE40046);
      case '9MOBILE': return const Color(0xFF00A859);
      case 'SMILE': return const Color(0xFF00AEEF);
      default: return Colors.blue;
    }
  }

  int _getNetworkIdFromKey(String key) {
    final idMap = {
      'MTN': 1,
      'GLO': 2,
      'AIRTEL': 3,
      '9MOBILE': 4,
      'SMILE': 5,
    };
    return idMap[key] ?? 1;
  }

  // NEW METHOD: Calculate discounted amount
  double calculateDiscountedAmount(double amount) {
    if (selectedNetwork == null || selectedAirtimeType == null || amount <= 0) {
      return amount;
    }

    // Get the percentage based on network and airtime type
    double percentage = 100.0; // Default to 100% (no discount)

    if (selectedAirtimeType == 'VTU' && vtuPercentages != null) {
      percentage = double.tryParse(vtuPercentages![selectedNetwork!].toString()) ?? 100.0;
    } else if (selectedAirtimeType == 'Share and Sell' && shareAndSellPercentages != null) {
      percentage = double.tryParse(shareAndSellPercentages![selectedNetwork!].toString()) ?? 100.0;
    }

    // Calculate the actual amount user will pay
    final discountedAmount = amount * percentage / 100;

    return discountedAmount;
  }

  // NEW METHOD: Get discount percentage text
  String getDiscountPercentageText() {
    if (selectedNetwork == null || selectedAirtimeType == null) {
      return '';
    }

    double percentage = 100.0;

    if (selectedAirtimeType == 'VTU' && vtuPercentages != null) {
      percentage = double.tryParse(vtuPercentages![selectedNetwork!].toString()) ?? 100.0;
    } else if (selectedAirtimeType == 'Share and Sell' && shareAndSellPercentages != null) {
      percentage = double.tryParse(shareAndSellPercentages![selectedNetwork!].toString()) ?? 100.0;
    }

    // Return the discount percentage (100 - percentage)
    final discount = 100 - percentage;
    return discount > 0 ? '${discount.toStringAsFixed(1)}% discount' : '';
  }

  // NEW METHOD: Get color based on user type
  Color _getUserTypeColor() {
    if (userType == null) return Colors.grey;

    switch (userType!.toLowerCase()) {
      case 'api':
        return Colors.purple;
      case 'topuser':
        return Colors.orange;
      case 'affilliate':
        return Colors.blue;
      case 'smart earner':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Future<void> submitPurchase() async {
    final phone = phoneController.text.trim();
    final amount = amountController.text.trim();
    final airtimeType = selectedAirtimeType;
    final network = selectedNetwork;

    if (selectedNetwork == null) {
      showError('Please select network');
      return;
    }

    if (selectedAirtimeType == null) {
      showError('Please select airtime type');
      return;
    }

    if (amount.isEmpty) {
      showError('Please enter amount');
      return;
    }

    final amountValue = double.tryParse(amount);
    if (amountValue == null || amountValue <= 0) {
      showError('Please enter valid amount');
      return;
    }

    final minAmount = selectedAirtimeType == 'VTU' ? 50 : 100;
    if (amountValue < minAmount) {
      showError('Minimum amount for ${selectedAirtimeType == 'VTU' ? 'VTU' : 'Share & Sell'} is ₦$minAmount');
      return;
    }

    if (phone.isEmpty) {
      showError('Please enter phone number');
      return;
    }

    if (!RegExp(r'^0[7-9][0-1]\d{8}$').hasMatch(phone)) {
      showError('Enter valid Nigerian number (e.g., 08136857222)');
      return;
    }

    setState(() => isSubmitting = true);

    try {
      final token = await _storage.read(key: 'authToken');
      if (token == null) {
        showError('Session expired. Please login again.');
        return;
      }

      // Find the selected network's ID
      final selectedNetworkData = networks.firstWhere(
            (net) => net['key'] == selectedNetwork,
        orElse: () => <String, dynamic>{},
      );

      if (selectedNetworkData.isEmpty || !selectedNetworkData.containsKey('id')) {
        showError('Invalid network selected');
        return;
      }

      final int networkId = selectedNetworkData['id'] as int;

      final apiAirtimeType = selectedAirtimeType == 'VTU' ? 'VTU' : 'Share and Sell';

      debugPrint('🎯 Submitting Airtime Purchase:');
      debugPrint('   Network ID: $networkId');
      debugPrint('   Type: $apiAirtimeType');
      debugPrint('   Amount: ₦$amount');
      debugPrint('   Phone: $phone');
      debugPrint('   Ported: $bypassValidation');

      final response = await http.post(
        Uri.parse('https://www.amsubnig.com/api/topup/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "network": networkId,
          "amount": amountValue.toInt(),
          "mobile_number": phone,
          "Ported_number": bypassValidation,
          "airtime_type": apiAirtimeType,
        }),
      );

      debugPrint('🔍 Response: ${response.statusCode} ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;

        showSuccess('✅ Airtime purchase successful!');

        // Pass the stored values to the receipt dialog
        _showReceiptDialog(result, amountValue, phone, airtimeType: airtimeType, network: network);

        // Clear form
        phoneController.clear();
        amountController.clear();
        setState(() {
          selectedAirtimeType = null;
          selectedNetwork = null;
          selectedPrefilledAmount = null;
        });
      } else {
        final errorBody = response.body.isNotEmpty ? jsonDecode(response.body) : {};
        final errorMsg = _extractErrorMessage(errorBody as Map<String, dynamic>);
        showError('Purchase failed: $errorMsg');
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      showError('Network error. Please try again.');
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  void _showReceiptDialog(
      Map<String, dynamic> receipt,
      double amount,
      String phone, {
        String? airtimeType,
        String? network,
      }) {
    final displayAirtimeType = airtimeType ?? selectedAirtimeType;
    final displayNetwork = network ?? selectedNetwork;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        displayAirtimeType == 'VTU' ? Icons.phone_android : Icons.people,
                        color: Colors.green,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Airtime Purchase Successful!',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        _receiptRow('Type', displayAirtimeType == 'VTU' ? 'VTU Airtime' : 'Share & Sell',
                            displayAirtimeType == 'VTU' ? Icons.phone_android : Icons.people),
                        _receiptDivider(),
                        _receiptRow('Network', displayNetwork ?? 'N/A', _getNetworkIcon(displayNetwork ?? '')),
                        _receiptDivider(),
                        _receiptRow('Amount', '₦$amount', Icons.attach_money),
                        _receiptDivider(),
                        _receiptRow('Phone', phone, Icons.phone),
                        _receiptDivider(),
                        _receiptRow('Status', receipt['Status'] ?? 'successful', Icons.check_circle),
                        _receiptDivider(),
                        if (receipt.containsKey('ident') && receipt['ident'] != null)
                          _receiptRow('Reference', receipt['ident'].toString(), Icons.receipt),
                      ],
                    ),
                  ),
                  if (receipt.containsKey('api_response') && receipt['api_response'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Message:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              receipt['api_response'].toString(),
                              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: Colors.grey[300]!),
                          ),
                          child: const Text('Close'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            phoneController.clear();
                            amountController.clear();
                            setState(() {
                              selectedAirtimeType = null;
                              selectedNetwork = null;
                              selectedPrefilledAmount = null;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Buy Again'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptDivider() {
    return Divider(height: 1, thickness: 1, color: Colors.grey[200]);
  }

  String _extractErrorMessage(Map<String, dynamic> response) {
    if (response.isEmpty) return 'Unknown error occurred';

    StringBuffer msg = StringBuffer();

    response.forEach((key, value) {
      if (value is List && value.isNotEmpty) {
        msg.writeln('$key: ${value.first}');
      } else if (value is String) {
        msg.writeln('$key: $value');
      }
    });

    if (msg.isNotEmpty) return msg.toString().trim();

    if (response.containsKey('error')) return response['error'].toString();
    if (response.containsKey('detail')) return response['detail'].toString();

    return 'Purchase failed. Please check your input.';
  }

  void showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate discounted amount for display
    final amountText = amountController.text.trim();
    final originalAmount = double.tryParse(amountText) ?? 0;
    final discountedAmount = calculateDiscountedAmount(originalAmount);
    final discountAmount = originalAmount - discountedAmount;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Buy Airtime'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Main content area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User type badge (only shown if discounts are loaded)
                  if (userType != null && !isLoadingDiscounts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _getUserTypeColor(),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person, size: 14, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  userType!.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (getDiscountPercentageText().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.green),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.discount, size: 14, color: Colors.green),
                                  const SizedBox(width: 6),
                                  Text(
                                    getDiscountPercentageText(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                  // 1. Select Network
                  _buildSectionHeader('1. Select Network', Icons.sim_card),
                  const SizedBox(height: 12),
                  _buildNetworkGrid(),

                  const SizedBox(height: 24),

                  // 2. Airtime Type
                  _buildSectionHeader('2. Airtime Type', Icons.category),
                  const SizedBox(height: 12),
                  _buildAirtimeTypeSelector(),

                  const SizedBox(height: 24),

                  // 3. Phone Number
                  _buildSectionHeader('3. Phone Number', Icons.phone),
                  const SizedBox(height: 12),
                  _buildPhoneInput(),

                  const SizedBox(height: 24),

                  // 4. Enter Amount
                  _buildSectionHeader('4. Enter Amount', Icons.attach_money),
                  const SizedBox(height: 12),
                  _buildAmountInput(),

                  // Pre-filled amounts
                  if (selectedAirtimeType != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          'Quick Select:',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildPrefilledAmounts(),
                      ],
                    ),

                  // Discount calculation preview
                  if (discountAmount > 0 && originalAmount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Original Price',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  '₦${originalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'You Pay',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                  ),
                                ),
                                Text(
                                  '₦${discountedAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),

          // Fixed Buy Button at the bottom
          if (canShowBuyButton) _buildFloatingBuyButton(originalAmount, discountedAmount, discountAmount),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _buildNetworkGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: networks.length,
      itemBuilder: (context, index) {
        final network = networks[index];
        final isSelected = selectedNetwork == network['key'];

        return GestureDetector(
          onTap: () {
            setState(() {
              selectedNetwork = network['key'];
              selectedPrefilledAmount = null;
              // Fetch discounts when network is selected
              fetchDiscountPercentages();
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? network['color'].withOpacity(0.2) : Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: isSelected ? network['color'] : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(network['icon'], size: 32, color: network['color']),
                const SizedBox(height: 8),
                Text(
                  network['name'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? network['color'] : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAirtimeTypeSelector() {
    return Column(
      children: airtimeTypes.map((type) {
        final isSelected = selectedAirtimeType == type['value'];
        return GestureDetector(
          onTap: () {
            setState(() {
              selectedAirtimeType = type['value'];
              selectedPrefilledAmount = null;
              // Fetch discounts when airtime type is selected
              if (selectedNetwork != null) {
                fetchDiscountPercentages();
              }
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue[50] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  type['value'] == 'VTU' ? Icons.phone_android : Icons.people,
                  color: isSelected ? Colors.blue : Colors.grey[600],
                  size: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type['label']!,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.blue : Colors.black87,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(type['description']!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                if (isSelected) const Icon(Icons.check_circle, color: Colors.green, size: 24),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPhoneInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: TextFormField(
        controller: phoneController,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          hintText: '08136857222',
          border: InputBorder.none,
          prefixIcon: Icon(Icons.phone, color: Colors.blue),
        ),
        onChanged: (value) {
          setState(() {}); // Trigger rebuild to update button visibility
        },
      ),
    );
  }

  Widget _buildAmountInput() {
    final amountText = amountController.text.trim();
    final originalAmount = double.tryParse(amountText) ?? 0;
    final discountedAmount = calculateDiscountedAmount(originalAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: TextFormField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: selectedAirtimeType == 'VTU' ? 'Enter amount (₦50 minimum)' : 'Enter amount (₦100 minimum)',
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.attach_money, color: Colors.green),
              suffixText: 'NGN',
            ),
            onChanged: (value) {
              setState(() {
                // Clear prefilled amount selection if user types manually
                if (value.isNotEmpty) {
                  selectedPrefilledAmount = null;
                }
              });
            },
          ),
        ),

        // Show discount info below the input field
        if (discountedAmount < originalAmount && originalAmount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 8),
            child: Text(
              'You will be charged ₦${discountedAmount.toStringAsFixed(2)} after discount',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPrefilledAmounts() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: prefilledAmounts.map((amount) {
        final isSelected = selectedPrefilledAmount == amount;
        return GestureDetector(
          onTap: () {
            setState(() {
              selectedPrefilledAmount = amount;
              amountController.text = amount.toString();
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? Colors.green : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? Colors.green : Colors.grey[300]!,
                width: 1,
              ),
            ),
            child: Text(
              '₦${amount.toStringAsFixed(0)}',
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFloatingBuyButton(double originalAmount, double discountedAmount, double discountAmount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: isSubmitting ? null : submitPurchase,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            disabledBackgroundColor: Colors.grey[400],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 5,
          ),
          child: isSubmitting
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: Colors.white),
          )
              : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone_android, size: 22),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'BUY AIRTIME',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (originalAmount > 0)
                    Text(
                      '₦${discountedAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
              if (discountAmount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Save ₦${discountAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}