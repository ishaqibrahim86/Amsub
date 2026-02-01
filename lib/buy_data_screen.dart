import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BuyDataScreen extends StatefulWidget {
  const BuyDataScreen({super.key});

  @override
  State<BuyDataScreen> createState() => _BuyDataScreenState();
}

class _BuyDataScreenState extends State<BuyDataScreen> {
  final _storage = FlutterSecureStorage();
  final phoneController = TextEditingController();
  bool bypassValidation = true; // Always true as requested
  String? _selectedPlanType;

  // Store API data
  List<Map<String, dynamic>> networks = [];
  Map<String, List<dynamic>> plansByNetwork = {};
  List<String> planTypes = ['All', 'SME', 'GIFTING', 'SME2', 'AWOOF GIFTING', 'CORPORATE GIFTING'];

  String? selectedNetworkKey;
  String? selectedPlanId;
  bool isLoading = true;
  bool isSubmitting = false;

  // New variables to track step completion
  bool get isPhoneValid => phoneController.text.isNotEmpty &&
      RegExp(r'^0[7-9][0-1]\d{8}$').hasMatch(phoneController.text.trim());

  bool get isPlanTypeSelected => _selectedPlanType != null;
  bool get isPlanSelected => selectedPlanId != null && selectedNetworkKey != null;
  bool get canShowBuyButton => selectedNetworkKey != null && isPhoneValid && isPlanTypeSelected && isPlanSelected;

  @override
  void initState() {
    super.initState();
    fetchAllNetworksAndPlans();
  }

  Future<void> fetchAllNetworksAndPlans() async {
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
        final Map<String, List<dynamic>> plansMap = {};

        for (final key in networkKeys) {
          if (data.containsKey(key)) {
            final networkInfo = data[key]['network_info'] as Map<String, dynamic>;
            final networkMap = <String, dynamic>{
              'key': key,
              'name': key,
              'icon': _getNetworkIcon(key),
              'color': _getNetworkColor(key),
              'id': networkInfo['id'] ?? _getNetworkIdFromKey(key),
            };

            networkInfo.forEach((key, value) {
              networkMap[key] = value;
            });

            networkList.add(networkMap);

            if (data[key]['data_plans'] != null) {
              plansMap[key] = List<dynamic>.from(data[key]['data_plans'] as List);
            }
          }
        }

        setState(() {
          networks = networkList;
          plansByNetwork = plansMap;
          _selectedPlanType = 'All';
        });

        debugPrint('✅ Loaded ${networks.length} networks');
      } else {
        showError('Failed to load plans');
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      showError('Connection error');
    } finally {
      setState(() => isLoading = false);
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

  Map<String, dynamic>? findSelectedPlan(String? planId) {
    if (planId == null || selectedNetworkKey == null) return null;

    final plans = plansByNetwork[selectedNetworkKey] ?? [];
    for (final plan in plans) {
      if (plan is Map && plan['id'].toString() == planId.toString()) {
        return plan as Map<String, dynamic>;
      }
    }
    return null;
  }

  List<dynamic> getFilteredPlans() {
    if (selectedNetworkKey == null) return [];

    final allPlans = plansByNetwork[selectedNetworkKey] ?? [];
    if (_selectedPlanType == 'All' || _selectedPlanType == null) {
      return allPlans;
    }

    return allPlans.where((plan) {
      final planMap = plan as Map<String, dynamic>;
      return planMap['plan_type']?.toString().toUpperCase() == _selectedPlanType?.toUpperCase();
    }).toList();
  }

  Future<void> submitPurchase() async {
    final selectedPlan = findSelectedPlan(selectedPlanId);

    if (selectedPlan == null) {
      showError('Please select a data plan');
      return;
    }

    final phone = phoneController.text.trim();
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

      final networkId = selectedPlan['network_id'] ??
          selectedPlan['network'] ??
          _getNetworkIdFromKey(selectedNetworkKey!);

      final response = await http.post(
        Uri.parse('https://amsubnig.com/api/data/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'plan': selectedPlan['id'],
          'network': networkId,
          'mobile_number': phone,
          'Ported_number': bypassValidation, // Always true
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;

        showSuccess('✅ Purchase Receipt!');

        // Show receipt
        _showReceiptDialog(result, selectedPlan, phone);

        phoneController.clear();
        setState(() => selectedPlanId = null);

      } else if (response.statusCode == 400) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final errorMsg = _extractErrorMessage(result);
        showError('❌ $errorMsg');
      } else if (response.statusCode == 403) {
        showError('❌ Insufficient balance');
      } else {
        showError('❌ Purchase failed');
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      showError('❌ Network error');
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  void _showReceiptDialog(Map<String, dynamic> receipt, Map<String, dynamic> plan, String phone) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('Purchase Receipt!', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _receiptRow('Plan', '${plan['plan_size']}${plan['plan_Volume']}', Icons.data_usage),
              _receiptRow('Amount', '₦${plan['plan_amount']}', Icons.attach_money),
              _receiptRow('Phone', phone, Icons.phone),
              _receiptRow('Network', selectedNetworkKey ?? '', _getNetworkIcon(selectedNetworkKey ?? '')),
              _receiptRow('Reference', receipt['ident'] ?? 'N/A', Icons.receipt),
              _receiptRow('Status', receipt['Status'] ?? 'successful', Icons.info),
              _receiptRow('Date', DateTime.now().toString().split('.').first, Icons.calendar_today),

              const SizedBox(height: 16),
              if (receipt.containsKey('api_response'))
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    receipt['api_response'] ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                selectedPlanId = null;
                phoneController.clear();
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Buy Again'),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _extractErrorMessage(Map<String, dynamic> response) {
    if (response.containsKey('error')) return response['error'].toString();
    if (response.containsKey('mobile_number')) return 'Invalid phone number';
    if (response.containsKey('plan')) return 'Invalid plan selected';
    if (response.containsKey('network')) return 'Invalid network';
    if (response.containsKey('detail')) return response['detail'].toString();
    return 'Unknown error occurred';
  }

  void showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredPlans = getFilteredPlans();
    final selectedPlan = findSelectedPlan(selectedPlanId);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Buy Data Bundle'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: isLoading
          ? _buildLoadingScreen()
          : Column(
        children: [
          // Main content area with scrolling
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Network Selection
                  _buildSectionHeader('1. Select Network', Icons.sim_card),
                  const SizedBox(height: 12),
                  _buildNetworkGrid(),

                  const SizedBox(height: 24),

                  // Phone Input
                  _buildSectionHeader('2. Enter Phone Number', Icons.phone),
                  const SizedBox(height: 12),
                  _buildPhoneInput(),

                  const SizedBox(height: 24),

                  // Plan Type Filter - Only show after network selected
                  if (selectedNetworkKey != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('3. Filter Plan Type', Icons.filter_list),
                        const SizedBox(height: 12),
                        _buildPlanTypeFilter(),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Plan Selection - Only show after network selected and plan type selected
                  if (selectedNetworkKey != null && isPlanTypeSelected)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('4. Select Data Plan', Icons.data_usage),
                        const SizedBox(height: 12),
                        if (filteredPlans.isEmpty)
                          _buildEmptyState()
                        else
                          _buildPlanList(filteredPlans),
                      ],
                    ),

                  // Selected Plan Summary
                  if (selectedPlan != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: _buildSelectedPlanCard(selectedPlan),
                    ),

                  // Add some bottom padding
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),

          // Fixed Buy Button at the bottom
          if (canShowBuyButton) _buildFloatingBuyButton(selectedPlan!),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Loading Data Plans...',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
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
        final isSelected = selectedNetworkKey == network['key'];

        return GestureDetector(
          onTap: () {
            setState(() {
              selectedNetworkKey = network['key'];
              selectedPlanId = null;
              _selectedPlanType = 'All';
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
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  network['icon'],
                  size: 32,
                  color: network['color'],
                ),
                const SizedBox(height: 8),
                Text(
                  network['name'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? network['color'] : Colors.black87,
                  ),
                ),
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.check_circle, size: 16, color: Colors.green),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlanTypeFilter() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: planTypes.map((type) {
        final isSelected = _selectedPlanType == type;
        return FilterChip(
          label: Text(type),
          selected: isSelected,
          onSelected: (selected) {
            setState(() => _selectedPlanType = type);
          },
          backgroundColor: Colors.white,
          selectedColor: Colors.blue[100],
          checkmarkColor: Colors.blue,
          labelStyle: TextStyle(
            color: isSelected ? Colors.blue : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          shape: StadiumBorder(
            side: BorderSide(
              color: isSelected ? Colors.blue : Colors.grey[300]!,
              width: isSelected ? 1.5 : 1,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPlanList(List<dynamic> plans) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: plans.length,
      itemBuilder: (context, index) {
        final plan = plans[index] as Map<String, dynamic>;
        final isSelected = selectedPlanId == plan['id'].toString();

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[50] : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: ListTile(
            title: Text('${plan['plan_size']}${plan['plan_Volume']}'),
            subtitle: Text('${plan['plan_type'] ?? 'Standard'} • ${plan['month_validate'] ?? '30'} days'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '₦${plan['plan_amount']}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                ),
                if (isSelected)
                  const Text('Selected', style: TextStyle(fontSize: 10, color: Colors.green)),
              ],
            ),
            onTap: () => setState(() => selectedPlanId = plan['id'].toString()),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Icon(Icons.data_exploration, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No plans available',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'Try selecting a different plan type',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedPlanCard(Map<String, dynamic> plan) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue[50]!, Colors.green[50]!],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_circle, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selected Plan',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  '${plan['plan_size']}${plan['plan_Volume']}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '₦${plan['plan_amount']} • ${plan['plan_type'] ?? 'Standard'}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () => setState(() => selectedPlanId = null),
            tooltip: 'Clear selection',
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: phoneController,
        keyboardType: TextInputType.phone,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Enter 11-digit Nigerian number',
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.phone, color: Colors.blue),
          suffixIcon: phoneController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear, size: 20),
            onPressed: () => phoneController.clear(),
          )
              : null,
        ),
        onChanged: (value) {
          setState(() {}); // Trigger rebuild to update button visibility
        },
      ),
    );
  }

  Widget _buildFloatingBuyButton(Map<String, dynamic> selectedPlan) {
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: 5,
            shadowColor: Colors.green.withOpacity(0.3),
          ),
          child: isSubmitting
              ? const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Processing...', style: TextStyle(fontSize: 16)),
            ],
          )
              : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shopping_cart, size: 22),
              const SizedBox(width: 12),
              const Text('BUY NOW', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(
                '₦${selectedPlan['plan_amount']}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
              ),
            ],
          ),
        ),
      ),
    );
  }
}