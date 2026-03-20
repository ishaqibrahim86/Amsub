import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/pin_auth_service.dart'; // ← PIN auth
import '../providers/user_balance_provider.dart';

class ElectricityPaymentScreen extends StatefulWidget {
  const ElectricityPaymentScreen({super.key});

  @override
  State<ElectricityPaymentScreen> createState() => _ElectricityPaymentScreenState();
}

class _ElectricityPaymentScreenState extends State<ElectricityPaymentScreen> {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  final meterNumberController = TextEditingController();
  final phoneController       = TextEditingController();
  final amountController      = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _amountSectionKey = GlobalKey();

  List<Map<String, dynamic>> discos = [];

  // Meter types — icons removed, clean text-only pills
  static const List<Map<String, dynamic>> meterTypes = [
    {'id': 'prepaid',  'name': 'Prepaid',  'variation_code': 'Prepaid'},
    {'id': 'postpaid', 'name': 'Postpaid', 'variation_code': 'Postpaid'},
  ];

  int?    selectedDiscoId;
  String? selectedMeterType;
  String? customerName;
  String? customerAddress;

  bool isLoading           = true;
  bool isValidating        = false;
  bool isSubmitting        = false;
  bool isValidationSuccess = false;
  String? _validatedMeterType;

  // ── New UX state ──────────────────────────────────────────────────────────
  List<String>          _recentMeters = [];   // last 5 meter numbers used
  Map<String, dynamic>? _lastPurchase;        // quick-repeat banner

  // ── DISCO image map (real provider logos) ─────────────────────────────────
  static const Map<String, String> _discoImages = {
    'ekedc':  'assets/images/ekedc.png',
    'ikedc':  'assets/images/ikedc.png',
    'phedc':  'assets/images/phedc.png',
    'aedc':   'assets/images/aedc.png',
    'eedc':   'assets/images/eedc.png',
    'kedco':  'assets/images/kedco.png',
    'jed':    'assets/images/jed.png',
    'ibedc':  'assets/images/ibedc.png',
    'bedc':   'assets/images/bedc.png',
  };

  static const List<Color> _discoColors = [
    Color(0xFF6B4EFF), Color(0xFF3B82F6), Color(0xFF10B981),
    Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFF8B5CF6),
    Color(0xFF06B6D4), Color(0xFFEC4899), Color(0xFF14B8A6),
    Color(0xFF84CC16),
  ];

  @override
  void initState() {
    super.initState();
    _loadCachedData();
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

  // ── API helpers ───────────────────────────────────────────────────────────

  Future<http.Response> safeApiCall(Uri url, Map<String, String> headers) async {
    try {
      return await http.get(url, headers: headers).timeout(const Duration(seconds: 15));
    } catch (_) {
      await Future.delayed(const Duration(seconds: 2));
      return await http.get(url, headers: headers);
    }
  }

  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('electricity_cache');
    if (cached == null) return;
    try {
      final json    = jsonDecode(cached) as Map<String, dynamic>;
      final bal     = json['balance'] as double?;
      final discList= (json['discos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (int i = 0; i < discList.length; i++) {
        discList[i]['color'] = _discoColors[i % _discoColors.length];
      }
      if (!mounted) return;
      final bp = Provider.of<UserBalanceProvider>(context, listen: false);
      bp.updateBalance(bal ?? 0.0, bp.bonusBalance);

      final recentRaw    = prefs.getString('recent_elec_meters');
      final lastPurchRaw = prefs.getString('last_elec_purchase');
      setState(() {
        discos = discList; isLoading = false;
        if (recentRaw != null) _recentMeters = List<String>.from(jsonDecode(recentRaw) as List);
        if (lastPurchRaw != null) _lastPurchase = Map<String, dynamic>.from(jsonDecode(lastPurchRaw) as Map);
      });
    } catch (_) {}
  }

  /// Save meter number to recent list (max 5, deduped, most recent first)
  Future<void> _saveRecentMeter(String meter) async {
    final updated = [meter, ..._recentMeters.where((m) => m != meter)].take(5).toList();
    setState(() => _recentMeters = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recent_elec_meters', jsonEncode(updated));
  }

  /// Save last purchase for quick-repeat banner
  Future<void> _saveLastPurchase({required int discoId, required String discoName, required String meterType, required String meter, required String phone, required double amount}) async {
    final data = {'disco_id': discoId, 'disco_name': discoName, 'meter_type': meterType, 'meter': meter, 'phone': phone, 'amount': amount};
    setState(() => _lastPurchase = data);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_elec_purchase', jsonEncode(data));
  }

  Future<void> _loadAll() async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      final headers = {'Authorization': 'Token $token'};
      final results = await Future.wait([
        safeApiCall(Uri.parse('https://amsubnig.com/api/user/'), headers),
        safeApiCall(Uri.parse('https://amsubnig.com/api/disco-list/'), headers),
      ]);

      double? newBalance;
      List<Map<String, dynamic>> newDiscos = [];

      if (results[0].statusCode == 200) {
        final data  = jsonDecode(results[0].body);
        final phone = data['user']?['Phone']?.toString() ?? '';
        if (phone.isNotEmpty) phoneController.text = phone;
        newBalance = double.tryParse(data['user']?['Account_Balance']?.toString() ?? '0') ?? 0.0;
      }

      if (results[1].statusCode == 200) {
        final rawData = jsonDecode(results[1].body);
        List<dynamic> list = [];
        if (rawData is Map) {
          for (final k in ['discos', 'results', 'data']) {
            if (rawData[k] is List) { list = rawData[k] as List; break; }
          }
          if (list.isEmpty) {
            for (final v in rawData.values) { if (v is List) { list = v; break; } }
          }
        } else if (rawData is List) { list = rawData; }

        for (int i = 0; i < list.length; i++) {
          final item = list[i] as Map<String, dynamic>;
          final name = (item['name'] ?? item['disco_name'] ?? 'Unknown').toString();
          final code = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          // Match image by checking if any key is contained in the disco code
          String imageMatch = '';
          for (final key in _discoImages.keys) {
            final cleanKey = key.replaceAll(RegExp(r'[^a-z0-9]'), '');
            if (code.contains(cleanKey) || cleanKey.contains(code)) {
              imageMatch = _discoImages[key]!;
              break;
            }
          }
          newDiscos.add({'id': item['id'], 'name': name, 'code': code, 'image': imageMatch});
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('electricity_cache', jsonEncode({'balance': newBalance ?? 0.0, 'discos': newDiscos}));

      for (int i = 0; i < newDiscos.length; i++) {
        newDiscos[i]['color'] = _discoColors[i % _discoColors.length];
      }

      if (!mounted) return;
      final bp = Provider.of<UserBalanceProvider>(context, listen: false);
      if (newBalance != null) bp.updateBalance(newBalance, bp.bonusBalance);
      setState(() { if (newDiscos.isNotEmpty) discos = newDiscos; isLoading = false; });
    } catch (e) {
      debugPrint('Electricity fetch error: $e');
      if (mounted && discos.isEmpty) {
        showError('Failed to load data.');
        setState(() => isLoading = false);
      }
    }
  }

  void _scrollToAmountSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _amountSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut, alignment: 0.1);
      }
    });
  }

  // ── Validate meter ────────────────────────────────────────────────────────

  Future<void> validateMeter() async {
    if (selectedDiscoId == null)   return showError('Please select a DISCO');
    if (selectedMeterType == null) return showError('Please select meter type');
    final meter = meterNumberController.text.trim();
    final phone = phoneController.text.trim();
    if (meter.isEmpty || meter.length < 6) return showError('Enter a valid meter number');
    if (!RegExp(r'^0[7-9][0-1]\d{8}$').hasMatch(phone)) return showError('Enter valid Nigerian number (e.g. 08012345678)');

    setState(() { isValidating = true; isValidationSuccess = false; customerName = null; customerAddress = null; _validatedMeterType = null; });

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
        body: jsonEncode({'disco_id': selectedDiscoId, 'meter_type': meterTypeStr, 'meter_number': meter, 'phone': phone}),
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
          await _showValidationDialog(
            customerName: customerName ?? 'Customer',
            discoName: discos.firstWhere((d) => d['id'] == selectedDiscoId, orElse: () => {'name': 'N/A'})['name'].toString(),
            meterNumber: meter,
            meterType: meterTypeStr,
            phone: phone,
          );
          _scrollToAmountSection();
        } else {
          showError('Validation failed: ${data['message'] ?? 'Meter not found'}');
        }
      } else {
        try {
          final err = jsonDecode(response.body) as Map<String, dynamic>;
          showError(err['message']?.toString() ?? 'Validation failed (${response.statusCode})');
        } catch (_) { showError('Validation failed (${response.statusCode})'); }
      }
    } catch (_) { showError('Validation failed. Please try again.'); }
    finally { if (mounted) setState(() => isValidating = false); }
  }

  Future<void> _showValidationDialog({required String customerName, required String discoName, required String meterNumber, required String meterType, required String phone}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [primaryPurple, Color(0xFF9B7DFF)]), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.verified_rounded, color: Colors.white, size: 18)),
              const SizedBox(width: 10),
              const Expanded(child: Text('Meter Validated!', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  _dialogRow(Icons.person,              'Customer', customerName),
                  _divider(),
                  _dialogRow(Icons.electrical_services, 'DISCO',    discoName),
                  _divider(),
                  _dialogRow(Icons.numbers,             'Meter No.', meterNumber),
                  _divider(),
                  _dialogRow(Icons.electric_meter,      'Type',     meterType),
                  _divider(),
                  _dialogRow(Icons.phone,               'Phone',    phone),
                  if (customerAddress != null && customerAddress!.isNotEmpty) ...[_divider(), _dialogRow(Icons.location_on, 'Address', customerAddress!)],
                ]),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.withOpacity(0.4))),
                child: const Row(children: [Icon(Icons.info_rounded, color: Colors.amber, size: 16), SizedBox(width: 8), Expanded(child: Text('Enter amount below and proceed to pay', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w500, fontSize: 12)))]),
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Continue', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _dialogRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(icon, size: 16, color: lightText),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: lightText, letterSpacing: 0.5)),
        const SizedBox(height: 1),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText)),
      ])),
    ]),
  );

  Widget _divider() => const Divider(height: 10, thickness: 0.5);

  // ── Submit with PIN auth ──────────────────────────────────────────────────

  Future<void> submitPayment() async {
    final bp = Provider.of<UserBalanceProvider>(context, listen: false);
    final currentBalance = bp.balance;

    if (!isValidationSuccess) return showError('Please validate meter first');
    final currentType = selectedMeterType == 'prepaid' ? 'Prepaid' : 'Postpaid';
    if (_validatedMeterType != null && _validatedMeterType != currentType) {
      return showError('Meter type changed after validation. Please re-validate.');
    }

    final meter       = meterNumberController.text.trim();
    final phone       = phoneController.text.trim();
    final amountStr   = amountController.text.trim();
    final amountValue = double.tryParse(amountStr);

    if (meter.isEmpty)                             return showError('Enter meter number');
    if (phone.isEmpty)                             return showError('Enter phone number');
    if (amountValue == null || amountValue <= 0)   return showError('Enter valid amount');
    if (amountValue < 500)                         return showError('Minimum amount is ₦500');
    if (amountValue > currentBalance)              return showError('Insufficient balance');

    final meterTypeForPayment = _validatedMeterType ?? currentType;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: lightPurple, shape: BoxShape.circle), child: const Icon(Icons.bolt_rounded, color: primaryPurple, size: 26)),
            const SizedBox(height: 12),
            const Text('Confirm Payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _confirmRow('Meter No.', meter),
                _confirmRow('Type',      meterTypeForPayment),
                _confirmRow('Amount',    '₦$amountStr'),
                _confirmRow('DISCO',     discos.firstWhere((d) => d['id'] == selectedDiscoId, orElse: () => {'name': 'Unknown'})['name'].toString()),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11)), child: const Text('Cancel', style: TextStyle(fontSize: 13)))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 11)), child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
            ]),
          ]),
        ),
      ),
    ) ?? false;

    if (!proceed) return;

    // ── Step 2: PIN / biometric guard ─────────────────────────────────────
    final verified = await PinAuthService.verify(context);
    if (!verified) return;
    // ─────────────────────────────────────────────────────────────────────

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
          'meter_number':     meter,
          'Customer_Phone':   phone,
          'amount':           amountValue.toString(),
          'MeterType':        meterTypeForPayment,
          'customer_name':    customerName ?? '',
          'customer_address': customerAddress ?? '',
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        bp.updateBalance(currentBalance - amountValue, bp.bonusBalance);
        showSuccess('✅ Payment successful!');
        final discoName = discos.firstWhere((d) => d['id'] == selectedDiscoId, orElse: () => {'name': 'N/A'})['name'].toString();
        await _saveRecentMeter(meter);
        await _saveLastPurchase(discoId: selectedDiscoId!, discoName: discoName, meterType: meterTypeForPayment, meter: meter, phone: phone, amount: amountValue);
        _resetForm();
        if (mounted) showDialog(context: context, builder: (_) => _ElectricityReceiptDialog(receipt: data));
      } else if (response.statusCode == 400) {
        final err = jsonDecode(response.body) as Map<String, dynamic>;
        showError('Payment failed: ${_extractError(err)}');
      } else {
        showError('Payment failed (${response.statusCode})');
      }
    } catch (_) { showError('Network error. Please try again.'); }
    finally { if (mounted) setState(() => isSubmitting = false); }
  }

  Widget _confirmRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 76, child: Text(label, style: const TextStyle(fontSize: 11, color: lightText))),
      const SizedBox(width: 6),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText))),
    ]),
  );

  String _extractError(Map<String, dynamic> r) {
    for (final f in ['MeterType', 'disco_name', 'meter_number', 'amount', 'error', 'detail']) {
      if (r.containsKey(f)) { final v = r[f]; return v is List ? v.first.toString() : v.toString(); }
    }
    return 'Unknown error';
  }

  void _resetForm() {
    meterNumberController.clear();
    amountController.clear();
    setState(() {
      selectedDiscoId = null; selectedMeterType = null;
      _validatedMeterType = null; isValidationSuccess = false;
      customerName = null; customerAddress = null;
    });
  }

  void showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error, color: Colors.white), const SizedBox(width: 10), Expanded(child: Text(msg))]),
      backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  void showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 10), Expanded(child: Text(msg))]),
      backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  Widget _sectionHeader(String title, IconData icon) => Row(children: [
    Icon(icon, color: primaryPurple, size: 18),
    const SizedBox(width: 7),
    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: darkText)),
  ]);

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bp           = Provider.of<UserBalanceProvider>(context);
    final walletBalance= bp.balance;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        title: const Text('Pay Electricity Bill', style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        toolbarHeight: 48,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: primaryPurple, size: 20), onPressed: _loadAll)],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await _loadAll(); await bp.refresh(); },
        color: primaryPurple,
        child: Stack(children: [
          Column(children: [
            // ── Wallet card ───────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [primaryPurple, Color(0xFF9B7DFF)]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: primaryPurple.withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 5))],
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Wallet Balance', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('₦${walletBalance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ]),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(18)),
                  child: const Row(children: [Icon(Icons.account_balance_wallet, color: Colors.white, size: 14), SizedBox(width: 5), Text('Available', style: TextStyle(color: Colors.white, fontSize: 11))]),
                ),
              ]),
            ),

            Expanded(
              child: isLoading
                  ? _buildSkeletonLoading()
                  : SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // ── Quick repeat last purchase ────────────────
                  if (_lastPurchase != null) ...[
                    _buildLastPurchaseBanner(walletBalance),
                    const SizedBox(height: 16),
                  ],

                  // ── 1. DISCO grid ─────────────────────────────────
                  _sectionHeader('1. Select DISCO', Icons.electrical_services),
                  const SizedBox(height: 10),
                  _buildDiscoGrid(),
                  const SizedBox(height: 20),

                  // ── 2. Meter type ─────────────────────────────────
                  _sectionHeader('2. Meter Type', Icons.electric_meter),
                  const SizedBox(height: 10),
                  _buildMeterTypeSelector(),
                  const SizedBox(height: 20),

                  // ── 3. Meter number ───────────────────────────────
                  _sectionHeader('3. Meter Number', Icons.numbers),
                  const SizedBox(height: 8),
                  _buildInputField(
                    controller: meterNumberController,
                    hint: 'Enter meter number',
                    icon: Icons.confirmation_number_rounded,
                    keyboard: TextInputType.number,
                    readOnly: isValidationSuccess,
                    onChanged: (_) => setState(() { isValidationSuccess = false; _validatedMeterType = null; }),
                  ),
                  if (_recentMeters.isNotEmpty && !isValidationSuccess) ...[
                    const SizedBox(height: 8),
                    _buildRecentMeters(),
                  ],
                  const SizedBox(height: 14),

                  // ── 4. Phone number ───────────────────────────────
                  _sectionHeader('4. Phone Number', Icons.phone),
                  const SizedBox(height: 8),
                  _buildInputField(
                    controller: phoneController,
                    hint: '08012345678',
                    icon: Icons.phone_rounded,
                    keyboard: TextInputType.phone,
                    readOnly: isValidationSuccess,
                    onChanged: (_) => setState(() { isValidationSuccess = false; _validatedMeterType = null; }),
                  ),
                  const SizedBox(height: 16),

                  // ── Validate button ───────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isValidating ? null : validateMeter,
                      style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 3),
                      child: isValidating
                          ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)), SizedBox(width: 10), Text('Validating…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))])
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.verified_rounded, size: 18), SizedBox(width: 8), Text('VALIDATE METER', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]),
                    ),
                  ),

                  // ── Customer info card ────────────────────────────
                  if (isValidationSuccess && customerName != null) ...[
                    const SizedBox(height: 16),
                    _buildCustomerInfoCard(),
                  ],

                  // ── 5. Amount + pay ───────────────────────────────
                  if (isValidationSuccess) ...[
                    const SizedBox(height: 16),
                    SizedBox(key: _amountSectionKey, height: 0),
                    _sectionHeader('5. Amount (min ₦500)', Icons.payments),
                    const SizedBox(height: 8),
                    _buildInputField(
                      controller: amountController,
                      hint: '500',
                      icon: Icons.payments_rounded,
                      keyboard: TextInputType.number,
                      prefix: const Padding(padding: EdgeInsets.only(right: 5), child: Text('₦', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryPurple))),
                      suffix: 'NGN',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    const Text('Quick Amounts', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: lightText)),
                    const SizedBox(height: 8),
                    _buildQuickAmounts(walletBalance),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isSubmitting ? null : submitPayment,
                        style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 6),
                        child: isSubmitting
                            ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)), SizedBox(width: 10), Text('Processing…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))])
                            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.shopping_cart_rounded, size: 20), const SizedBox(width: 8), Text(amountController.text.isNotEmpty ? 'PAY NOW  •  ₦${amountController.text}' : 'PAY NOW', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]),
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ]),
              ),
            ),
          ]),

          // ── Processing overlay ────────────────────────────────────────────
          if (isSubmitting)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.55),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: primaryPurple.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 6))]),
                    child: const Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 46, height: 46, child: CircularProgressIndicator(color: primaryPurple, strokeWidth: 3.5)),
                      SizedBox(height: 16),
                      Text('Processing Payment…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: darkText)),
                      SizedBox(height: 4),
                      Text('Please do not close the app', style: TextStyle(fontSize: 11, color: lightText)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  // ── Quick repeat banner ─────────────────────────────────────────────────────
  Widget _buildLastPurchaseBanner(double balance) {
    final lp       = _lastPurchase!;
    final amount   = (lp['amount'] as num?)?.toDouble() ?? 0;
    final meter    = lp['meter']      as String? ?? '';
    final phone    = lp['phone']      as String? ?? '';
    final disco    = lp['disco_name'] as String? ?? '';
    final mtype    = lp['meter_type'] as String? ?? '';
    final discoId  = (lp['disco_id'] as num?)?.toInt();
    final canAfford= balance >= amount;

    return GestureDetector(
      onTap: canAfford ? () {
        setState(() {
          selectedDiscoId   = discoId;
          selectedMeterType = mtype == 'Prepaid' ? 'prepaid' : 'postpaid';
          meterNumberController.text = meter;
          phoneController.text       = phone;
          amountController.text      = amount.toStringAsFixed(0);
          isValidationSuccess        = false;
          _validatedMeterType        = null;
        });
      } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [primaryPurple.withOpacity(0.08), const Color(0xFF3B82F6).withOpacity(0.06)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primaryPurple.withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primaryPurple.withOpacity(0.12), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.replay_rounded, color: primaryPurple, size: 17)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Quick Repeat', style: TextStyle(fontSize: 10, color: lightText)),
            const SizedBox(height: 2),
            Text('$disco  $mtype  \u20a6${amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: darkText)),
            Text('Meter: $meter  \u00b7  $phone', style: const TextStyle(fontSize: 11, color: lightText)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: canAfford ? primaryPurple : Colors.grey.shade400, borderRadius: BorderRadius.circular(20)),
            child: Text(canAfford ? 'Tap to fill' : 'Low balance', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  // ── Recent meter chips ────────────────────────────────────────────────────
  Widget _buildRecentMeters() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Recent meters', style: TextStyle(fontSize: 10, color: lightText, letterSpacing: 0.3)),
      const SizedBox(height: 5),
      Wrap(spacing: 7, runSpacing: 6, children: _recentMeters.map((meter) {
        final isActive = meterNumberController.text == meter;
        return GestureDetector(
          onTap: () => setState(() { meterNumberController.text = meter; isValidationSuccess = false; _validatedMeterType = null; }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isActive ? primaryPurple : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isActive ? primaryPurple : Colors.grey[300]!),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.history_rounded, size: 11, color: isActive ? Colors.white70 : lightText),
              const SizedBox(width: 4),
              Text(meter, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? Colors.white : darkText)),
            ]),
          ),
        );
      }).toList()),
    ]);
  }

  // ── Quick amount chips ────────────────────────────────────────────────────
  Widget _buildQuickAmounts(double balance) {
    const amounts = [500, 1000, 2000, 3000, 5000, 10000, 20000];
    return Wrap(spacing: 7, runSpacing: 7, children: amounts.map((amt) {
      final amtD      = amt.toDouble();
      final isSelected= amountController.text == amt.toString();
      final canAfford = balance >= amtD;
      return Opacity(
        opacity: canAfford ? 1.0 : 0.45,
        child: GestureDetector(
          onTap: canAfford ? () => setState(() => amountController.text = amt.toString()) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? primaryPurple : (canAfford ? Colors.white : Colors.grey[100]!),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? primaryPurple : Colors.grey[200]!),
              boxShadow: [BoxShadow(color: isSelected ? primaryPurple.withOpacity(0.25) : Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('\u20a6$amt', style: TextStyle(color: isSelected ? Colors.white : darkText, fontWeight: FontWeight.w600, fontSize: 12)),
              if (!canAfford) const Text('Low bal.', style: TextStyle(fontSize: 8, color: Colors.red, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      );
    }).toList());
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────

  Widget _buildSkeletonLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: [
        Container(height: 20, width: 160, color: Colors.white),
        const SizedBox(height: 10),
        GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.9), itemCount: 9, itemBuilder: (_, __) => Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 20),
        Container(height: 52, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
        const SizedBox(height: 20),
        ...List.generate(3, (_) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Container(height: 52, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))))),
      ]),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildDiscoGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.9),
      itemCount: discos.length,
      itemBuilder: (_, i) {
        final disco     = discos[i];
        final isSelected= selectedDiscoId == disco['id'];
        final color     = (disco['color'] as Color?) ?? primaryPurple;
        final imagePath = disco['image']?.toString() ?? '';
        return GestureDetector(
          onTap: () => setState(() { selectedDiscoId = disco['id']; isValidationSuccess = false; _validatedMeterType = null; }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? color : Colors.grey[200]!, width: isSelected ? 2 : 1),
              boxShadow: [BoxShadow(color: isSelected ? color.withOpacity(0.15) : Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Expanded(
                  child: Center(
                    child: imagePath.isNotEmpty
                        ? Image.asset(imagePath, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(Icons.bolt_rounded, size: 28, color: color))
                        : Icon(Icons.bolt_rounded, size: 28, color: color),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  disco['name'].toString().split(' ').first,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? color : darkText),
                ),
                if (isSelected) ...[const SizedBox(height: 2), const Icon(Icons.check_circle_rounded, size: 12, color: Colors.green)],
              ]),
            ),
          ),
        );
      },
    );
  }

  /// Clean pill-style meter type selector — no icons, just text
  Widget _buildMeterTypeSelector() {
    return Row(
      children: meterTypes.map((type) {
        final isSelected = selectedMeterType == type['id'];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              selectedMeterType = type['id'] as String;
              isValidationSuccess = false;
              _validatedMeterType = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.only(right: type['id'] == 'prepaid' ? 6 : 0, left: type['id'] == 'postpaid' ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: isSelected ? primaryPurple : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? primaryPurple : Colors.grey[200]!, width: isSelected ? 2 : 1),
                boxShadow: [BoxShadow(color: isSelected ? primaryPurple.withOpacity(0.2) : Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Column(children: [
                Text(
                  type['name'] as String,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isSelected ? Colors.white : darkText),
                ),
                if (_validatedMeterType == type['variation_code']) ...[
                  const SizedBox(height: 3),
                  const Icon(Icons.verified_rounded, size: 13, color: Colors.green),
                ],
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCustomerInfoCard() {
    final discoName = discos.firstWhere((d) => d['id'] == selectedDiscoId, orElse: () => {'name': 'N/A'})['name'].toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.green.shade50, Colors.green.shade100.withOpacity(0.4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.verified_rounded, color: Colors.green, size: 17), SizedBox(width: 6), Text('Meter Validated', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green))]),
        const SizedBox(height: 10),
        _infoRow('Name',     customerName ?? 'Customer',                                                                   Icons.person),
        _infoRow('Meter No.', meterNumberController.text.trim(),                                                            Icons.numbers),
        _infoRow('Phone',    phoneController.text.trim(),                                                                   Icons.phone),
        _infoRow('DISCO',    discoName,                                                                                     Icons.electrical_services),
        _infoRow('Type',     _validatedMeterType ?? (selectedMeterType == 'prepaid' ? 'Prepaid' : 'Postpaid'),             Icons.electric_meter),
        if (customerAddress != null && customerAddress!.isNotEmpty) _infoRow('Address', customerAddress!, Icons.location_on),
      ]),
    );
  }

  Widget _infoRow(String label, String value, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: lightText),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: lightText, letterSpacing: 0.3)),
        const SizedBox(height: 1),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: darkText), maxLines: 2, overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );

  Widget _buildInputField({required TextEditingController controller, required String hint, required IconData icon, TextInputType keyboard = TextInputType.text, bool readOnly = false, Widget? prefix, String? suffix, void Function(String)? onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: readOnly ? Colors.grey[100] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Icon(icon, color: primaryPurple, size: 18),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(
          controller: controller,
          keyboardType: keyboard,
          readOnly: readOnly,
          style: TextStyle(color: readOnly ? Colors.grey[500] : darkText, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: lightText, fontSize: 13),
            border: InputBorder.none,
            prefix: prefix,
            suffixText: suffix,
            suffixStyle: const TextStyle(color: lightText, fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
          ),
          onChanged: onChanged,
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt Dialog (unchanged logic, sizes tightened)
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
      final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Render boundary not found');
      final image    = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode image');
      final pngBytes = byteData.buffer.asUint8List();
      final tempDir  = await getTemporaryDirectory();
      final file     = File('${tempDir.path}/elec_receipt_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);
      final hasAccess = await Gal.hasAccess(toAlbum: false);
      if (!hasAccess) await Gal.requestAccess(toAlbum: false);
      await Gal.putImage(file.path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Receipt saved to gallery'), backgroundColor: Colors.green));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save image'), backgroundColor: Colors.red));
    } finally { if (mounted) setState(() => _isSaving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final r           = widget.receipt;
    final rawStatus   = r['Status']?.toString() ?? 'pending';
    final statusLower = rawStatus.toLowerCase();
    final isSuccess   = statusLower == 'successful' || statusLower == 'success';
    final isPending   = statusLower == 'pending'    || statusLower == 'processing';
    final statusColor = isSuccess ? Colors.green : isPending ? Colors.orange : Colors.red;
    final statusIcon  = isSuccess ? Icons.check_circle_rounded : isPending ? Icons.hourglass_top_rounded : Icons.cancel_rounded;
    final token       = r['token']?.toString() ?? '';
    final amountStr   = r['amount']?.toString() ?? '0';
    final paidStr     = r['paid_amount']?.toString() ?? amountStr;
    final transId     = r['ident']?.toString() ?? 'N/A';
    final isPrepaid   = r['MeterType']?.toString() == 'Prepaid';
    final hasToken    = token.isNotEmpty && isPrepaid;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [primaryPurple, Color(0xFF9B7DFF)]), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.receipt_long, color: Colors.white, size: 19)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Payment Receipt', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        // ── Receipt body — no scroll ─────────────────────────────────────────
        RepaintBoundary(
          key: _captureKey,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Brand
              RichText(text: TextSpan(children: [
                const TextSpan(text: 'AMS', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: primaryPurple, letterSpacing: 1)),
                const TextSpan(text: 'UB',  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF3B82F6), letterSpacing: 1)),
                const TextSpan(text: 'NIG', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF10B981), letterSpacing: 1)),
              ])),
              const Text('Grandfather of Data Vendors', style: TextStyle(fontSize: 9, color: lightText, fontStyle: FontStyle.italic)),
              const SizedBox(height: 10),
              // Status icon
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: statusColor.withAlpha(20), shape: BoxShape.circle), child: Icon(statusIcon, color: statusColor, size: 24)),
              const SizedBox(height: 4),
              Text(rawStatus.toUpperCase(), style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
              // Token — keep prominent for prepaid
              if (hasToken) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.withOpacity(0.5))),
                  child: Column(children: [
                    const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.vpn_key_rounded, color: Colors.amber, size: 14), SizedBox(width: 5), Text('PREPAID TOKEN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 0.8))]),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
                      child: Row(children: [
                        Expanded(child: SelectableText(token, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 2, color: darkText), textAlign: TextAlign.center)),
                        GestureDetector(onTap: () => Clipboard.setData(ClipboardData(text: token)), child: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.copy_rounded, color: primaryPurple, size: 17))),
                      ]),
                    ),
                    const SizedBox(height: 5),
                    const Text('Enter this token on your meter to recharge', style: TextStyle(fontSize: 10, color: lightText), textAlign: TextAlign.center),
                  ]),
                ),
              ],
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              // 3 compact info pairs
              _infoGrid(label1: 'Customer',   value1: r['customer_name'] ?? 'N/A', label2: 'Meter No.', value2: r['meter_number'] ?? 'N/A'),
              const SizedBox(height: 8),
              _infoGrid(label1: 'DISCO',      value1: r['package'] ?? 'N/A',       label2: 'Meter Type', value2: r['MeterType'] ?? 'N/A'),
              const SizedBox(height: 8),
              _infoGrid(
                label1: 'Amount',   value1: paidStr != amountStr ? '₦$amountStr → ₦$paidStr' : '₦$amountStr',
                label2: 'Date',     value2: DateTime.now().toString().substring(0, 16),
              ),
              const SizedBox(height: 8),
              _infoGrid(label1: 'Reference',  value1: transId,                     label2: 'Phone', value2: r['Customer_Phone'] ?? 'N/A'),
            ]),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(top: BorderSide(color: Colors.grey.shade200))),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _saveToGallery,
              icon: _isSaving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded, size: 16),
              label: Text(_isSaving ? 'Saving…' : 'Save', style: const TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check_circle_rounded, size: 16),
              label: const Text('Done', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 11)),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _infoGrid({required String label1, required String value1, required String label2, required String value2}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _infoCell(label1, value1)),
        const SizedBox(width: 8),
        Expanded(child: _infoCell(label2, value2)),
      ]);

  Widget _infoCell(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(9)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, color: lightText, letterSpacing: 0.4)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: darkText), maxLines: 2, overflow: TextOverflow.ellipsis),
    ]),
  );
}