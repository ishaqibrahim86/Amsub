import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io'; // For SocketException
import 'dart:math'; // For min() function

class ElectricityPaymentScreen extends StatefulWidget {
  const ElectricityPaymentScreen({super.key});

  @override
  State<ElectricityPaymentScreen> createState() => _ElectricityPaymentScreenState();
}

class _ElectricityPaymentScreenState extends State<ElectricityPaymentScreen> {
  final _storage = FlutterSecureStorage();
  final meterNumberController = TextEditingController();
  final phoneController = TextEditingController();
  final amountController = TextEditingController();

  // Disco options - UPDATED to match Django database
  final List<Map<String, dynamic>> discos = [
    {'id': 1, 'name': 'Ikeja Electric', 'code': 'ikeja-electric', 'color': Colors.blue},
    {'id': 2, 'name': 'Eko Electric', 'code': 'eko-electric', 'color': Colors.green},
    {'id': 8, 'name': 'Kaduna Electric', 'code': 'kaduna-electric', 'color': Colors.orange},
    {'id': 4, 'name': 'Kano Electric', 'code': 'kano-electric', 'color': Colors.teal}, // Fixed: ID 4 = Kano
    {'id': 6, 'name': 'Port Harcourt Electric', 'code': 'portharcourt-electric', 'color': Colors.purple}, // Fixed: ID 5 = Port Harcourt
    {'id': 9, 'name': 'Jos Electric', 'code': 'jos-electric', 'color': Colors.red},
    {'id': 7, 'name': 'Ibadan Electric', 'code': 'ibadan-electric', 'color': Colors.brown}, // Fixed: ID 7 = Ibadan
    {'id': 3, 'name': 'Abuja Electric', 'code': 'abuja-electric', 'color': Colors.indigo},
    {'id': 5, 'name': 'Enugu Electric', 'code': 'enugu-electric', 'color': Colors.black},
  ];

  // Meter types - UPDATED with correct capitalization
  final List<Map<String, dynamic>> meterTypes = [
    {'id': 'prepaid', 'name': 'Prepaid Meter', 'variation_code': 'Prepaid'}, // Capitalized
    {'id': 'postpaid', 'name': 'Postpaid Meter', 'variation_code': 'Postpaid'}, // Capitalized
  ];

  int? selectedDiscoId;
  String? selectedMeterType;
  String? customerName;
  String? customerAddress;
  bool isLoading = false;
  bool isValidating = false;
  bool isSubmitting = false;
  bool isValidationSuccess = false;

  // Payment receipt
  Map<String, dynamic>? paymentReceipt;
  bool showReceipt = false;

  // Track validated meter type separately
  String? _validatedMeterType; // 'Prepaid' or 'Postpaid'

  @override
  void dispose() {
    meterNumberController.dispose();
    phoneController.dispose();
    amountController.dispose();
    super.dispose();
  }

  // Validate meter number
  Future<void> validateMeter() async {
    if (selectedDiscoId == null) {
      showError('Please select a DISCO');
      return;
    }

    if (selectedMeterType == null) {
      showError('Please select meter type');
      return;
    }

    final meterNumber = meterNumberController.text.trim();
    if (meterNumber.isEmpty) {
      showError('Please enter meter number');
      return;
    }

    if (meterNumber.length < 6) {
      showError('Meter number is too short');
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

    setState(() {
      isValidating = true;
      isValidationSuccess = false;
      customerName = null;
      customerAddress = null;
      _validatedMeterType = null; // Reset validated type
    });

    try {
      // Get the token from storage
      final String? token = await _storage.read(key: 'authToken');
      if (token == null) {
        showError('Session expired. Please login again.');
        return;
      }

      // Get meter type with correct capitalization
      final String meterTypeForValidation = selectedMeterType == 'prepaid' ? 'Prepaid' : 'Postpaid';

      debugPrint('🔍 Validation - selectedMeterType: $selectedMeterType');
      debugPrint('🔍 Validation - sending meter_type: $meterTypeForValidation');

      // Prepare request data
      final Map<String, dynamic> requestData = {
        'disco_id': selectedDiscoId,
        'meter_type': meterTypeForValidation, // Use capitalized version
        'meter_number': meterNumber,
        'phone': phone,
      };

      debugPrint('🔍 Sending validation request...');
      debugPrint('📤 Request Data: ${jsonEncode(requestData)}');

      final Stopwatch stopwatch = Stopwatch()..start();

      final response = await http.post(
        Uri.parse('https://amsubnig.com/api/validate-meter/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestData),
      ).timeout(const Duration(seconds: 45));

      stopwatch.stop();

      debugPrint('⏱️  Request took: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('📡 Response Status: ${response.statusCode}');
      debugPrint('📄 Full Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['status'] == 'success') {
          setState(() {
            isValidationSuccess = true;
            customerName = data['customer_name'];
            customerAddress = data['customer_address'];
            _validatedMeterType = meterTypeForValidation; // Store validated type
          });
          showSuccess('✅ Meter validated successfully!');

          debugPrint('✅ Customer Name: $customerName');
          debugPrint('✅ Customer Address: $customerAddress');
          debugPrint('✅ Validated Meter Type: $_validatedMeterType');
        } else {
          final errorMsg = data['message'] ?? 'Meter validation failed';
          showError('Validation failed: $errorMsg');
        }
      } else {
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          final errorMsg = errorData['message'] ?? 'Validation failed (${response.statusCode})';
          showError('Error ${response.statusCode}: $errorMsg');
        } catch (e) {
          showError('Validation failed with status: ${response.statusCode}');
        }
      }
    } on http.ClientException catch (e) {
      debugPrint('❌ HTTP client error: $e');
      showError('Connection error. Please check your internet connection.');
    } on SocketException catch (e) {
      debugPrint('❌ Network error: $e');
      showError('Network error. Please check your internet connection.');
    } catch (e) {
      debugPrint('❌ Unexpected error: $e');
      showError('An unexpected error occurred. Please try again.');
    } finally {
      setState(() => isValidating = false);
    }
  }

  // Submit payment to your Django API
  Future<void> submitPayment() async {
    if (!isValidationSuccess) {
      showError('Please validate meter first');
      return;
    }

    // Check if meter type has changed since validation
    final String currentMeterType = selectedMeterType == 'prepaid' ? 'Prepaid' : 'Postpaid';
    if (_validatedMeterType != null && _validatedMeterType != currentMeterType) {
      showError(
          'Meter type was changed after validation!\n\n'
              'Validated as: $_validatedMeterType\n'
              'Selected now: $currentMeterType\n\n'
              'Please re-validate the meter with the correct type.'
      );
      return;
    }

    final meterNumber = meterNumberController.text.trim();
    final phone = phoneController.text.trim();
    final amount = amountController.text.trim();

    if (meterNumber.isEmpty) {
      showError('Please enter meter number');
      return;
    }

    if (phone.isEmpty) {
      showError('Please enter phone number');
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

    // Minimum amount check
    if (amountValue < 500) {
      showError('Minimum amount is ₦500');
      return;
    }

    // Get meter type for payment - use validated type if available
    final String meterTypeForPayment = _validatedMeterType ?? currentMeterType;

    debugPrint('🔍 Payment - selectedMeterType: $selectedMeterType');
    debugPrint('🔍 Payment - validatedMeterType: $_validatedMeterType');
    debugPrint('🔍 Payment - sending MeterType: $meterTypeForPayment');

    // Show confirmation dialog
    final bool proceed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_user, color: Colors.blue),
            SizedBox(width: 10),
            Text('Confirm Payment Details'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please confirm these details:'),
            const SizedBox(height: 16),
            _confirmationRow('Meter Number', meterNumber),
            _confirmationRow('Meter Type', meterTypeForPayment),
            _confirmationRow('Amount', '₦$amount'),
            _confirmationRow('DISCO', discos.firstWhere(
                    (d) => d['id'] == selectedDiscoId,
                orElse: () => {'name': 'Unknown'}
            )['name'].toString()),
            const SizedBox(height: 8),
            Text(
              'Note: Payment will be processed as $meterTypeForPayment meter',
              style: TextStyle(
                color: Colors.orange[800],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('CONFIRM PAYMENT'),
          ),
        ],
      ),
    ) ?? false;

    if (!proceed) {
      return; // User cancelled
    }

    setState(() => isSubmitting = true);

    try {
      final token = await _storage.read(key: 'authToken');
      if (token == null) {
        showError('Session expired. Please login again.');
        return;
      }

      // Prepare request data matching your serializer
      final requestData = {
        'disco_name': selectedDiscoId,
        'meter_number': meterNumber,
        'Customer_Phone': phone,
        'amount': amountValue.toString(),
        'MeterType': meterTypeForPayment, // Use the validated type
        'customer_name': customerName ?? '',
        'customer_address': customerAddress ?? '',
      };

      debugPrint('🔍 Submitting payment: ${jsonEncode(requestData)}');

      // Call your Django API endpoint
      final response = await http.post(
        Uri.parse('https://amsubnig.com/api/bill-payment/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestData),
      );

      debugPrint('📡 Response status: ${response.statusCode}');
      debugPrint('📄 Response body: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        setState(() {
          paymentReceipt = data;
          showReceipt = true;
        });

        // Clear form for next transaction
        resetForm();
        showSuccess('Payment successful!');

      } else if (response.statusCode == 400) {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        final errorMsg = _extractErrorMessage(errorData);
        showError('Payment failed: $errorMsg');
      } else {
        showError('Payment failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Payment error: $e');
      showError('Network error. Please try again.');
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  Widget _confirmationRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _extractErrorMessage(Map<String, dynamic> response) {
    // Check for field-specific errors first
    for (final field in ['MeterType', 'disco_name', 'meter_number', 'amount', 'customer_name']) {
      if (response.containsKey(field)) {
        final error = response[field];
        if (error is List) {
          return '${field.replaceAll('_', ' ')}: ${error.first}';
        }
        return '${field.replaceAll('_', ' ')}: $error';
      }
    }

    if (response.containsKey('error')) return response['error'].toString();
    if (response.containsKey('detail')) return response['detail'].toString();
    if (response.containsKey('non_field_errors')) {
      final errors = response['non_field_errors'] as List<dynamic>;
      return errors.isNotEmpty ? errors.first.toString() : 'Unknown error';
    }
    return 'Unknown error occurred';
  }

  void resetForm() {
    meterNumberController.clear();
    phoneController.clear();
    amountController.clear();
    setState(() {
      selectedDiscoId = null;
      selectedMeterType = null;
      _validatedMeterType = null;
      isValidationSuccess = false;
      customerName = null;
      customerAddress = null;
    });
  }

  void showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildDiscoGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: discos.length,
      itemBuilder: (context, index) {
        final disco = discos[index];
        final isSelected = selectedDiscoId == disco['id'];

        return GestureDetector(
          onTap: () {
            setState(() {
              selectedDiscoId = disco['id'];
              isValidationSuccess = false;
              _validatedMeterType = null;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? (disco['color'] as Color).withOpacity(0.2) : Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: isSelected ? disco['color'] as Color : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bolt,
                  size: 32,
                  color: disco['color'] as Color,
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    disco['name'].toString().split(' ')[0],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? disco['color'] as Color : Colors.black87,
                    ),
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

  Widget _buildMeterTypeSelector() {
    return Row(
      children: meterTypes.map((type) {
        final isSelected = selectedMeterType == type['id'];
        return Expanded(
          child: GestureDetector(
            onTap: () {
              debugPrint('🎯 Meter type selected: ${type['id']} -> ${type['variation_code']}');
              setState(() {
                selectedMeterType = type['id'];
                isValidationSuccess = false;
                _validatedMeterType = null; // Clear validated type when changing selection
              });
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue[50] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.grey[300]!,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    type['id'] == 'prepaid' ? Icons.electric_meter : Icons.receipt_long,
                    color: isSelected ? Colors.blue : Colors.grey[600],
                    size: 24,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    type['name'],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.blue : Colors.black87,
                      fontSize: 12,
                    ),
                  ),
                  // Show current validated type if available
                  if (_validatedMeterType != null &&
                      _validatedMeterType == type['variation_code'])
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(Icons.verified, size: 16, color: Colors.green),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCustomerInfoCard() {
    final selectedDisco = discos.firstWhere(
          (d) => d['id'] == selectedDiscoId,
      orElse: () => {'name': 'N/A'},
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.green[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text(
                'Meter Validated',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow('Name', customerName ?? 'Customer', Icons.person),
          _infoRow('Address', customerAddress ?? 'Will be confirmed during payment', Icons.location_on),
          _infoRow('Meter No.', meterNumberController.text.trim(), Icons.numbers),
          _infoRow('Phone', phoneController.text.trim(), Icons.phone),
          _infoRow('DISCO', selectedDisco['name'].toString(), Icons.electrical_services),
          _infoRow(
            'Type',
            _validatedMeterType ?? (selectedMeterType == 'prepaid' ? 'Prepaid' : 'Postpaid'),
            Icons.electric_meter,
          ),
          // Add note if customer details are generic
          if (customerName == 'Customer' || customerAddress?.contains('will be confirmed') == true)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.info, size: 16, color: Colors.orange[800]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Full details will be confirmed during payment',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[800],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptDialog() {
    if (paymentReceipt == null) return const SizedBox.shrink();

    final token = paymentReceipt!['token']?.toString();
    final amount = paymentReceipt!['amount']?.toString() ?? '0';
    final paidAmount = paymentReceipt!['paid_amount']?.toString() ?? amount;
    final hasDiscount = double.parse(paidAmount) < double.parse(amount);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.receipt_long, color: Colors.green, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Payment Receipt',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                    _receiptRow('Transaction ID', paymentReceipt!['ident'] ?? 'N/A', Icons.receipt),
                    _receiptDivider(),
                    _receiptRow('Customer', paymentReceipt!['customer_name'] ?? 'N/A', Icons.person),
                    _receiptDivider(),
                    _receiptRow('Meter No.', paymentReceipt!['meter_number'] ?? 'N/A', Icons.numbers),
                    _receiptDivider(),
                    _receiptRow('DISCO', paymentReceipt!['package'] ?? 'N/A', Icons.electrical_services),
                    _receiptDivider(),
                    _receiptRow('Meter Type',
                        paymentReceipt!['MeterType'] == 'Prepaid' ? 'Prepaid' : 'Postpaid', // Updated
                        Icons.electric_meter
                    ),
                    _receiptDivider(),

                    // Price breakdown
                    if (hasDiscount)
                      Column(
                        children: [
                          _receiptRow('Amount', '₦$amount', Icons.money),
                          _receiptDivider(),
                          _receiptRow('You Paid', '₦$paidAmount', Icons.price_check),
                          _receiptDivider(),
                        ],
                      )
                    else
                      _receiptRow('Amount', '₦$paidAmount', Icons.attach_money),

                    // TOKEN SECTION (for prepaid meters)
                    if (token != null && token.isNotEmpty && paymentReceipt!['MeterType'] == 'Prepaid')
                      Column(
                        children: [
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.yellow[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange),
                            ),
                            child: Column(
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.vpn_key, color: Colors.orange, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'TOKEN NUMBER',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey[300]!),
                                  ),
                                  child: SelectableText(
                                    token,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Enter this token on your prepaid meter to recharge',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),

                    _receiptRow('Phone', paymentReceipt!['Customer_Phone'] ?? 'N/A', Icons.phone),
                    _receiptDivider(),
                    _receiptRow('Reference', paymentReceipt!['ident'] ?? 'N/A', Icons.tag),
                    _receiptDivider(),
                    _receiptRow('Date',
                        paymentReceipt!['create_date'] != null
                            ? DateTime.parse(paymentReceipt!['create_date']).toLocal().toString().split('.')[0]
                            : DateTime.now().toString().split('.')[0],
                        Icons.calendar_today
                    ),
                    _receiptDivider(),
                    _receiptRow('Status',
                      paymentReceipt!['Status'] == 'successful' ? 'Successful' : 'Pending',
                      paymentReceipt!['Status'] == 'successful' ? Icons.check_circle : Icons.pending,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => showReceipt = false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Close Receipt',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
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
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Pay Electricity Bill'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step 1: Select DISCO
                _buildSectionHeader('1. Select DISCO', Icons.electrical_services),
                const SizedBox(height: 12),
                _buildDiscoGrid(),

                const SizedBox(height: 24),

                // Step 2: Select Meter Type
                _buildSectionHeader('2. Meter Type', Icons.electric_meter),
                const SizedBox(height: 12),
                _buildMeterTypeSelector(),

                const SizedBox(height: 24),

                // Step 3: Meter Number
                _buildSectionHeader('3. Meter Number', Icons.numbers),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextFormField(
                    controller: meterNumberController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Enter meter number',
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.confirmation_number, color: Colors.blue),
                    ),
                    onChanged: (value) {
                      setState(() {
                        isValidationSuccess = false;
                        _validatedMeterType = null;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Step 4: Phone Number
                _buildSectionHeader('4. Phone Number', Icons.phone),
                const SizedBox(height: 12),
                Container(
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
                      setState(() {
                        isValidationSuccess = false;
                        _validatedMeterType = null;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Validate Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isValidating ? null : validateMeter,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      disabledBackgroundColor: Colors.grey[400],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: isValidating
                        ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)),
                        SizedBox(width: 12),
                        Text('Validating...', style: TextStyle(fontSize: 16)),
                      ],
                    )
                        : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified, size: 22),
                        SizedBox(width: 12),
                        Text('VALIDATE METER', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),

                // Show customer info after validation
                if (isValidationSuccess && customerName != null) ...[
                  const SizedBox(height: 24),
                  _buildCustomerInfoCard(),
                ],

                // Step 5: Enter Amount (only after validation)
                if (isValidationSuccess) ...[
                  const SizedBox(height: 24),
                  _buildSectionHeader('5. Enter Amount (₦500 minimum)', Icons.attach_money),
                  const SizedBox(height: 12),
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
                      decoration: const InputDecoration(
                        hintText: 'Enter amount',
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.attach_money, color: Colors.green),
                        suffixText: 'NGN',
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Pay Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isSubmitting ? null : submitPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        disabledBackgroundColor: Colors.grey[400],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 5,
                      ),
                      child: isSubmitting
                          ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)),
                          SizedBox(width: 12),
                          Text('Processing...', style: TextStyle(fontSize: 16)),
                        ],
                      )
                          : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bolt, size: 22),
                          const SizedBox(width: 12),
                          const Text('PAY NOW', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          if (amountController.text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '₦${amountController.text}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),

          // Receipt Dialog
          if (showReceipt) _buildReceiptDialog(),
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
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}