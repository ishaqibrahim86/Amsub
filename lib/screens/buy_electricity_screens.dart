import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import '../services/auth_service.dart';

class ElectricityPaymentScreens extends StatefulWidget {
  const ElectricityPaymentScreens({super.key});

  @override
  State<ElectricityPaymentScreens> createState() =>
      _ElectricityPaymentScreensState();
}

class _ElectricityPaymentScreensState extends State<ElectricityPaymentScreens> {
  // ── Brand colors ──────────────────────────────────────────────────────────
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  final meterNumberController = TextEditingController();
  final phoneController       = TextEditingController();
  final amountController      = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _amountSectionKey = GlobalKey();

  // ── Hardcoded DISCOs — always constant, no API needed ─────────────────────
  static const List<Map<String, dynamic>> discos = [
    {'id': 1,  'name': 'Ikeja Electric',   'image': 'assets/images/ikedc.png',  'color': Color(0xFF0067B1)},
    {'id': 2,  'name': 'Eko Electric',     'image': 'assets/images/ekedc.png',  'color': Color(0xFF00A859)},
    {'id': 3,  'name': 'Kano Electric',    'image': 'assets/images/kedco.png',  'color': Color(0xFF6B4EFF)},
    {'id': 4,  'name': 'Port Harcourt',    'image': 'assets/images/phedc.png',  'color': Color(0xFFEF4444)},
    {'id': 5,  'name': 'Jos Electric',     'image': 'assets/images/jed.png',    'color': Color(0xFFF59E0B)},
    {'id': 6,  'name': 'Ibadan Electric',  'image': 'assets/images/ibedc.png',  'color': Color(0xFF8B5CF6)},
    {'id': 7,  'name': 'Kaduna Electric',  'image': 'assets/images/kaedco.png', 'color': Color(0xFF06B6D4)},
    {'id': 8,  'name': 'Abuja Electric',   'image': 'assets/images/aedc.png',   'color': Color(0xFFEC4899)},
    {'id': 9,  'name': 'Enugu Electric',   'image': 'assets/images/eedc.png',   'color': Color(0xFF10B981)},
    {'id': 10, 'name': 'Benin Electric',   'image': 'assets/images/bedc.png',   'color': Color(0xFFE97C10)},
  ];

  final List<Map<String, dynamic>> meterTypes = [
    {'id': 'prepaid',  'name': 'Prepaid',  'variation_code': 'Prepaid',  'icon': Icons.electric_meter},
    {'id': 'postpaid', 'name': 'Postpaid', 'variation_code': 'Postpaid', 'icon': Icons.receipt_long},
  ];

  int?    selectedDiscoId;
  String? selectedMeterType;
  String? customerName;
  String? customerAddress;

  bool isLoadingBalance    = false;   // spins only on balance card
  bool isValidating        = false;
  bool isSubmitting        = false;
  bool isValidationSuccess = false;

  String? _validatedMeterType;
  double  walletBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    meterNumberController.dispose();
    phoneController.dispose();
    amountController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Background load: only wallet balance + phone (DISCOs are hardcoded) ──
  Future<void> _loadAll() async {
    setState(() => isLoadingBalance = true);
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      final response = await http.get(
        Uri.parse('https://amsubnig.com/api/user/'),
        headers: {'Authorization': 'Token $token'},
      );
      if (response.statusCode == 200) {
        final data  = jsonDecode(response.body);
        final phone = data['user']?['Phone']?.toString() ?? '';
        if (phone.isNotEmpty && mounted) phoneController.text = phone;
        walletBalance = double.tryParse(
            data['user']?['Account_Balance']?.toString() ?? '0') ?? 0.0;
      }
    } catch (_) {
      // Silently fail — user can still operate
    } finally {
      if (mounted) setState(() => isLoadingBalance = false);
    }
  }

  void _scrollToAmountSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _amountSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            alignment: 0.1);
      }
    });
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copied!'),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Validate ──────────────────────────────────────────────────────────────
  Future<void> validateMeter() async {
    if (selectedDiscoId == null)   return showError('Please select a DISCO');
    if (selectedMeterType == null) return showError('Please select meter type');
    final meterNumber = meterNumberController.text.trim();
    if (meterNumber.isEmpty)    return showError('Enter meter number');
    if (meterNumber.length < 6) return showError('Meter number too short');
    final phone = phoneController.text.trim();
    if (phone.isEmpty) return showError('Enter phone number');
    if (!RegExp(r'^0[7-9][0-1]\d{8}$').hasMatch(phone)) {
      return showError('Enter valid Nigerian number (e.g. 08012345678)');
    }

    setState(() {
      isValidating        = true;
      isValidationSuccess = false;
      customerName        = null;
      customerAddress     = null;
      _validatedMeterType = null;
    });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        showError('Session expired.');
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      final meterTypeStr = selectedMeterType == 'prepaid' ? 'Prepaid' : 'Postpaid';

      final response = await http.post(
        Uri.parse('https://amsubnig.com/api/validate-meter/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'disco_id':     selectedDiscoId,
          'meter_type':   meterTypeStr,
          'meter_number': meterNumber,
          'phone':        phone,
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          setState(() {
            isValidationSuccess = true;
            customerName        = data['customer_name']?.toString();
            customerAddress     = data['customer_address']?.toString();
            _validatedMeterType = meterTypeStr;
          });
          await _showValidationSuccessDialog(
            customerName: customerName ?? 'Customer',
            discoName: discos.firstWhere(
                    (d) => d['id'] == selectedDiscoId,
                orElse: () => {'name': 'N/A'})['name'].toString(),
            meterNumber:  meterNumber,
            meterType:    meterTypeStr,
            phone:        phone,
          );
          _scrollToAmountSection();
        } else {
          showError('Validation failed: ${data['message'] ?? 'Meter not found'}');
        }
      } else {
        try {
          final err = jsonDecode(response.body) as Map<String, dynamic>;
          showError(err['message']?.toString() ?? 'Validation failed (${response.statusCode})');
        } catch (_) {
          showError('Validation failed (${response.statusCode})');
        }
      }
    } on SocketException { showError('Network error. Check your connection.'); }
    catch (_)            { showError('An unexpected error occurred.'); }
    finally {
      if (mounted) setState(() => isValidating = false);
    }
  }

  Future<void> _showValidationSuccessDialog({
    required String customerName,
    required String discoName,
    required String meterNumber,
    required String meterType,
    required String phone,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Purple gradient header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryPurple, Color(0xFF9B7DFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.verified_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Meter Validated!',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  _dialogRow(Icons.person,               'Customer',    customerName),
                  const Divider(height: 16),
                  _dialogRow(Icons.electrical_services,  'DISCO',       discoName),
                  const Divider(height: 16),
                  _dialogRow(Icons.numbers,              'Meter No.',   meterNumber),
                  const Divider(height: 16),
                  _dialogRow(Icons.electric_meter,       'Meter Type',  meterType),
                  const Divider(height: 16),
                  _dialogRow(Icons.phone,                'Phone',       phone),
                  if (customerAddress != null && customerAddress!.isNotEmpty) ...[
                    const Divider(height: 16),
                    _dialogRow(Icons.location_on, 'Address', customerAddress!),
                  ],
                ]),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_rounded, color: Colors.amber, size: 18),
                  SizedBox(width: 10),
                  Expanded(child: Text('Enter amount below and proceed to pay',
                      style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w500, fontSize: 13))),
                ]),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Continue', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _dialogRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 18, color: lightText),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: lightText, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: darkText)),
      ])),
    ]);
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> submitPayment() async {
    if (!isValidationSuccess) return showError('Please validate meter first');
    final currentType = selectedMeterType == 'prepaid' ? 'Prepaid' : 'Postpaid';
    if (_validatedMeterType != null && _validatedMeterType != currentType) {
      return showError('Meter type changed after validation. Please re-validate.');
    }

    final meterNumber = meterNumberController.text.trim();
    final phone       = phoneController.text.trim();
    final amountStr   = amountController.text.trim();
    final amountValue = double.tryParse(amountStr);

    if (meterNumber.isEmpty)                       return showError('Enter meter number');
    if (phone.isEmpty)                             return showError('Enter phone number');
    if (amountValue == null || amountValue <= 0)   return showError('Enter valid amount');
    if (amountValue < 500)                         return showError('Minimum amount is ₦500');

    final meterTypeForPayment = _validatedMeterType ?? currentType;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: lightPurple, shape: BoxShape.circle),
              child: const Icon(Icons.bolt_rounded, color: primaryPurple, size: 28),
            ),
            const SizedBox(height: 14),
            const Text('Confirm Payment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _confirmRow('Meter No.', meterNumber),
                _confirmRow('Type',      meterTypeForPayment),
                _confirmRow('Amount',    '₦$amountStr'),
                _confirmRow('DISCO', discos.firstWhere(
                        (d) => d['id'] == selectedDiscoId,
                    orElse: () => {'name': 'Unknown'})['name'].toString()),
              ]),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ) ?? false;

    if (!proceed) return;

    setState(() => isSubmitting = true);
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        showError('Session expired.');
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final response = await http.post(
        Uri.parse('https://amsubnig.com/api/bill-payment/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'disco_name':       selectedDiscoId,
          'meter_number':     meterNumber,
          'Customer_Phone':   phone,
          'amount':           amountValue.toString(),
          'MeterType':        meterTypeForPayment,
          'customer_name':    customerName ?? '',
          'customer_address': customerAddress ?? '',
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Capture before reset
        showSuccess('✅ Payment successful!');
        _resetForm();
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => _ElectricityReceiptDialog(receipt: data),
          );
        }
      } else if (response.statusCode == 400) {
        final err = jsonDecode(response.body) as Map<String, dynamic>;
        showError('Payment failed: ${_extractError(err)}');
      } else {
        showError('Payment failed (${response.statusCode})');
      }
    } catch (_) {
      showError('Network error. Please try again.');
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 80,
            child: Text(label, style: const TextStyle(fontSize: 12, color: lightText))),
        const SizedBox(width: 8),
        Expanded(child: Text(value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: darkText))),
      ]),
    );
  }

  String _extractError(Map<String, dynamic> r) {
    for (final f in ['MeterType','disco_name','meter_number','amount','error','detail']) {
      if (r.containsKey(f)) {
        final v = r[f]; return v is List ? v.first.toString() : v.toString();
      }
    }
    return 'Unknown error';
  }

  void _resetForm() {
    meterNumberController.clear();
    amountController.clear();
    setState(() {
      selectedDiscoId     = null;
      selectedMeterType   = null;
      _validatedMeterType = null;
      isValidationSuccess = false;
      customerName        = null;
      customerAddress     = null;
    });
  }

  void showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  void showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(children: [
      Icon(icon, color: primaryPurple, size: 20),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
    ]);
  }

  // ── DISCO grid ─────────────────────────────────────────────────────────────
  Widget _buildDiscoGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.1,
      ),
      itemCount: discos.length,
      itemBuilder: (_, i) {
        final disco      = discos[i];
        final isSelected = selectedDiscoId == disco['id'];
        final color      = (disco['color'] as Color?) ?? primaryPurple;
        final imagePath  = disco['image']?.toString() ?? '';

        return GestureDetector(
          onTap: () => setState(() {
            selectedDiscoId     = disco['id'];
            isValidationSuccess = false;
            _validatedMeterType = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.12) : Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: isSelected ? color : Colors.grey[200]!,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [BoxShadow(
                color: isSelected ? color.withOpacity(0.18) : Colors.black.withOpacity(0.04),
                blurRadius: 8, offset: const Offset(0, 2),
              )],
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Expanded(
                  child: Center(
                    child: imagePath.isNotEmpty
                        ? Image.asset(imagePath, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.bolt_rounded, size: 32, color: color))
                        : Icon(Icons.bolt_rounded, size: 32, color: color),
                  ),
                ),
                Text(
                  disco['name'].toString().split(' ').first,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: isSelected ? color : darkText),
                ),
                if (isSelected) ...[
                  const SizedBox(height: 2),
                  const Icon(Icons.check_circle_rounded, size: 14, color: Colors.green),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }

  // ── Meter type selector ───────────────────────────────────────────────────
  Widget _buildMeterTypeSelector() {
    return Row(
      children: meterTypes.map((type) {
        final isSelected = selectedMeterType == type['id'];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              selectedMeterType   = type['id'] as String;
              isValidationSuccess = false;
              _validatedMeterType = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: isSelected ? lightPurple : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? primaryPurple : Colors.grey[200]!,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [BoxShadow(
                  color: isSelected ? primaryPurple.withOpacity(0.12) : Colors.black.withOpacity(0.03),
                  blurRadius: 8, offset: const Offset(0, 2),
                )],
              ),
              child: Column(children: [
                Icon(type['icon'] as IconData, size: 30,
                    color: isSelected ? primaryPurple : lightText),
                const SizedBox(height: 8),
                Text(type['name'] as String,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                        color: isSelected ? primaryPurple : darkText)),
                if (_validatedMeterType == type['variation_code']) ...[
                  const SizedBox(height: 4),
                  const Icon(Icons.verified_rounded, size: 14, color: Colors.green),
                ],
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Customer info card ────────────────────────────────────────────────────
  Widget _buildCustomerInfoCard() {
    final discoName = discos.firstWhere(
            (d) => d['id'] == selectedDiscoId, orElse: () => {'name': 'N/A'})['name'].toString();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade50, Colors.green.shade100.withOpacity(0.4)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.verified_rounded, color: Colors.green, size: 20),
          SizedBox(width: 8),
          Text('Meter Validated',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green)),
        ]),
        const SizedBox(height: 12),
        _infoRow('Name',      customerName ?? 'Customer',        Icons.person),
        _infoRow('Meter No.', meterNumberController.text.trim(), Icons.numbers),
        _infoRow('Phone',     phoneController.text.trim(),       Icons.phone),
        _infoRow('DISCO',     discoName,                         Icons.electrical_services),
        _infoRow('Type',
            _validatedMeterType ?? (selectedMeterType == 'prepaid' ? 'Prepaid' : 'Postpaid'),
            Icons.electric_meter),
        if (customerAddress != null && customerAddress!.isNotEmpty)
          _infoRow('Address', customerAddress!, Icons.location_on),
      ]),
    );
  }

  Widget _infoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: lightText),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: lightText, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }

  // ── Input field ────────────────────────────────────────────────────────────
  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    bool readOnly = false,
    Widget? prefix,
    String? suffix,
    void Function(String)? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: readOnly ? Colors.grey[100] : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Icon(icon, color: primaryPurple, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller:   controller,
            keyboardType: keyboard,
            readOnly:     readOnly,
            style: TextStyle(color: readOnly ? Colors.grey[500] : darkText),
            decoration: InputDecoration(
              hintText:   hint,
              hintStyle:  const TextStyle(color: lightText),
              border:     InputBorder.none,
              prefix:     prefix,
              suffixText: suffix,
              suffixStyle: const TextStyle(color: lightText, fontSize: 13),
            ),
            onChanged: onChanged,
          ),
        ),
      ]),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        title: const Text('Pay Electricity Bill',
            style: TextStyle(color: darkText, fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: primaryPurple),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // ── Wallet balance card ──────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryPurple, Color(0xFF9B7DFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: primaryPurple.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Wallet Balance',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 6),
                      isLoadingBalance
                          ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                          : Text('₦${walletBalance.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold)),
                    ]),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(children: [
                        Icon(Icons.account_balance_wallet,
                            color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('Available',
                            style: TextStyle(color: Colors.white, fontSize: 12)),
                      ]),
                    ),
                  ],
                ),
              ),

              // ── Scrollable content ───────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // 1. DISCO
                      _buildSectionHeader('1. Select DISCO', Icons.electrical_services),
                      const SizedBox(height: 12),
                      _buildDiscoGrid(),
                      const SizedBox(height: 24),

                      // 2. Meter type
                      _buildSectionHeader('2. Meter Type', Icons.electric_meter),
                      const SizedBox(height: 12),
                      _buildMeterTypeSelector(),
                      const SizedBox(height: 24),

                      // 3. Meter number
                      _buildSectionHeader('3. Meter Number', Icons.numbers),
                      const SizedBox(height: 12),
                      _buildInputField(
                        controller: meterNumberController,
                        hint:     'Enter meter number',
                        icon:     Icons.confirmation_number_rounded,
                        keyboard: TextInputType.number,
                        readOnly: isValidationSuccess,
                        onChanged: (_) => setState(() {
                          isValidationSuccess = false;
                          _validatedMeterType = null;
                        }),
                      ),
                      const SizedBox(height: 16),

                      // 4. Phone
                      _buildSectionHeader('4. Phone Number', Icons.phone),
                      const SizedBox(height: 12),
                      _buildInputField(
                        controller: phoneController,
                        hint:     '08012345678',
                        icon:     Icons.phone_rounded,
                        keyboard: TextInputType.phone,
                        readOnly: isValidationSuccess,
                        onChanged: (_) => setState(() {
                          isValidationSuccess = false;
                          _validatedMeterType = null;
                        }),
                      ),
                      const SizedBox(height: 20),

                      // Validate button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: isValidating ? null : validateMeter,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryPurple,
                            disabledBackgroundColor: lightText,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 4,
                            shadowColor: primaryPurple.withOpacity(0.4),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: isValidating
                                ? const Row(
                                key: ValueKey('v_loading'),
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(width: 20, height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2.5)),
                                  SizedBox(width: 12),
                                  Text('Validating…',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                ])
                                : const Row(
                                key: ValueKey('v_idle'),
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.verified_rounded, size: 20),
                                  SizedBox(width: 10),
                                  Text('VALIDATE METER',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                ]),
                          ),
                        ),
                      ),

                      // Customer info card
                      if (isValidationSuccess && customerName != null) ...[
                        const SizedBox(height: 24),
                        _buildCustomerInfoCard(),
                      ],

                      // 5. Amount
                      if (isValidationSuccess) ...[
                        const SizedBox(height: 24),
                        SizedBox(key: _amountSectionKey, height: 0),
                        _buildSectionHeader('5. Amount (min ₦500)', Icons.payments),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: amountController,
                          hint:     '500',
                          icon:     Icons.payments_rounded,
                          keyboard: TextInputType.number,
                          prefix: const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Text('₦',
                                style: TextStyle(fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: primaryPurple)),
                          ),
                          suffix: 'NGN',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 20),

                        // Pay Now button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : submitPayment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryPurple,
                              disabledBackgroundColor: lightText,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 8,
                              shadowColor: primaryPurple.withOpacity(0.45),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: isSubmitting
                                  ? const Row(
                                  key: ValueKey('p_loading'),
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(width: 22, height: 22,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2.5)),
                                    SizedBox(width: 12),
                                    Text('Processing…',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ])
                                  : Row(
                                  key: const ValueKey('p_idle'),
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.shopping_cart_rounded, size: 22),
                                    const SizedBox(width: 10),
                                    Text(
                                      amountController.text.isNotEmpty
                                          ? 'PAY NOW  •  ₦${amountController.text}'
                                          : 'PAY NOW',
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ]),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],          // closes outer Column children
          ),            // closes outer Column

          // Full-screen processing overlay
          if (isSubmitting)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.55),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(
                        color: primaryPurple.withOpacity(0.25),
                        blurRadius: 24, offset: const Offset(0, 8),
                      )],
                    ),
                    child: const Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 52, height: 52,
                          child: CircularProgressIndicator(color: primaryPurple, strokeWidth: 4)),
                      SizedBox(height: 20),
                      Text('Processing Payment…',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
                      SizedBox(height: 6),
                      Text('Please do not close the app',
                          style: TextStyle(fontSize: 13, color: lightText)),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt dialog with save-to-gallery
// ─────────────────────────────────────────────────────────────────────────────
class _ElectricityReceiptDialog extends StatefulWidget {
  final Map<String, dynamic> receipt;
  const _ElectricityReceiptDialog({required this.receipt});

  @override
  State<_ElectricityReceiptDialog> createState() => _ElectricityReceiptDialogState();
}

class _ElectricityReceiptDialogState extends State<_ElectricityReceiptDialog> {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  final GlobalKey _captureKey = GlobalKey();
  bool _isSaving = false;

  Future<void> _saveToGallery() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final boundary =
      _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Render boundary not found');
      final image    = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode image');
      final pngBytes = byteData.buffer.asUint8List();
      final tempDir  = await getTemporaryDirectory();
      final file     = File(
          '${tempDir.path}/elec_receipt_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);
      final hasAccess = await Gal.hasAccess(toAlbum: false);
      if (!hasAccess) await Gal.requestAccess(toAlbum: false);
      await Gal.putImage(file.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Receipt saved to gallery'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } on GalException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ ${e.type.toString().split('.').last}'),
          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not save image'),
          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copied!'),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r           = widget.receipt;
    final rawStatus   = r['Status']?.toString() ?? 'pending';
    final statusLower = rawStatus.toLowerCase();
    final isSuccess   = statusLower == 'successful' || statusLower == 'success';
    final isPending   = statusLower == 'pending'    || statusLower == 'processing';
    final statusColor = isSuccess ? Colors.green : isPending ? Colors.orange : Colors.red;
    final statusIcon  = isSuccess ? Icons.check_circle_rounded
        : isPending ? Icons.hourglass_top_rounded : Icons.cancel_rounded;

    final token     = r['token']?.toString() ?? '';
    final amountStr = r['amount']?.toString() ?? '0';
    final paidStr   = r['paid_amount']?.toString() ?? amountStr;
    final transId   = r['ident']?.toString() ?? 'N/A';
    final isPrepaid = r['MeterType']?.toString() == 'Prepaid';
    final hasToken  = token.isNotEmpty && isPrepaid;

    final dateRaw = r['create_date']?.toString();
    final dateStr = dateRaw != null
        ? DateTime.tryParse(dateRaw)?.toLocal().toString().split('.').first ?? dateRaw
        : DateTime.now().toString().split('.').first;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryPurple, Color(0xFF9B7DFF)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.receipt_long, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Payment Receipt',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
            ]),
          ),

          // Capturable body
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _captureKey,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Dynamic status hero
                    Center(
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: statusColor.withAlpha(20), shape: BoxShape.circle),
                          child: Icon(statusIcon, color: statusColor, size: 40),
                        ),
                        const SizedBox(height: 8),
                        Text(rawStatus.toUpperCase(),
                            style: TextStyle(color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13, letterSpacing: 1.2)),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // Token box at the TOP (prepaid only)
                    if (hasToken) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.withOpacity(0.5)),
                        ),
                        child: Column(children: [
                          const Row(children: [
                            Icon(Icons.vpn_key_rounded, color: Colors.amber, size: 18),
                            SizedBox(width: 8),
                            Text('TOKEN NUMBER',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                                    color: Colors.amber, letterSpacing: 1)),
                          ]),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(children: [
                              Expanded(
                                child: SelectableText(token,
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                                        letterSpacing: 2, color: darkText),
                                    textAlign: TextAlign.center),
                              ),
                              GestureDetector(
                                onTap: () => _copy(token, 'Token'),
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(Icons.copy_rounded, color: primaryPurple, size: 20),
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 8),
                          const Text('Enter this token on your prepaid meter to recharge',
                              style: TextStyle(fontSize: 12, color: lightText),
                              textAlign: TextAlign.center),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],

                    const Divider(),
                    const SizedBox(height: 12),

                    _row('Transaction ID', transId,                      Icons.receipt,          copyable: true),
                    _row('Customer',       r['customer_name'] ?? 'N/A',  Icons.person),
                    _row('Meter No.',      r['meter_number'] ?? 'N/A',   Icons.numbers),
                    _row('DISCO',          r['package'] ?? 'N/A',        Icons.electrical_services),
                    _row('Meter Type',     r['MeterType'] ?? 'N/A',      Icons.electric_meter),
                    _row('Amount',         '₦$amountStr',                Icons.payments),
                    if (paidStr != amountStr)
                      _row('You Paid', '₦$paidStr',                      Icons.price_check),
                    _row('Phone',          r['Customer_Phone'] ?? 'N/A', Icons.phone),
                    _row('Date',           dateStr,                      Icons.calendar_today),
                    _row('Status',         rawStatus,                    Icons.info_outline),
                  ]),
                ),
              ),
            ),
          ),

          // Action buttons
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _saveToGallery,
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(_isSaving ? 'Saving…' : 'Save'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Done'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, IconData icon, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Icon(icon, size: 18, color: lightText),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: lightText, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          SelectableText(value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: darkText)),
        ])),
        if (copyable && value != 'N/A')
          GestureDetector(
            onTap: () => _copy(value, label),
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.copy_rounded, size: 18, color: primaryPurple),
            ),
          ),
      ]),
    );
  }
}