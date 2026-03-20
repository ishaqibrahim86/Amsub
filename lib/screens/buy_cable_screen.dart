import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/pin_auth_service.dart'; // ← PIN auth
import '../providers/user_balance_provider.dart';

class CablePaymentScreen extends StatefulWidget {
  const CablePaymentScreen({super.key});

  @override
  State<CablePaymentScreen> createState() => _CablePaymentScreenState();
}

class _CablePaymentScreenState extends State<CablePaymentScreen> {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  final smartCardController  = TextEditingController();
  final phoneController      = TextEditingController();
  final ScrollController _scrollController  = ScrollController();
  final GlobalKey _packageSectionKey = GlobalKey();

  final List<Map<String, dynamic>> providers = [
    {'id': 2, 'name': 'DSTV',      'code': 'DSTV',    'db_id': 2, 'image': 'assets/images/dstv.png'},
    {'id': 1, 'name': 'GOTV',      'code': 'GOTV',    'db_id': 1, 'image': 'assets/images/gotv.png'},
    {'id': 3, 'name': 'Startimes', 'code': 'STARTIME','db_id': 3, 'image': 'assets/images/startimes.png'},
  ];

  List<Map<String, dynamic>> allPackages      = [];
  List<Map<String, dynamic>> filteredPackages = [];

  int?    selectedProviderId;
  String? selectedPackageId;
  String? customerName;

  bool isLoading           = true;
  bool isValidating        = false;
  bool isSubmitting        = false;
  bool isValidationSuccess = false;

  // ── New UX state ──────────────────────────────────────────────────────────
  List<String>          _recentCards  = [];   // last 5 smart card numbers
  Map<String, dynamic>? _lastPurchase;        // quick-repeat banner

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    _loadAll();
  }

  @override
  void dispose() {
    smartCardController.dispose();
    phoneController.dispose();
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
    final prefs  = await SharedPreferences.getInstance();
    final cached = prefs.getString('cable_cache');
    if (cached == null) return;
    try {
      final json = jsonDecode(cached) as Map<String, dynamic>;
      final bal  = json['balance'] as double?;
      final pkgs = (json['packages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (!mounted) return;
      final bp = Provider.of<UserBalanceProvider>(context, listen: false);
      bp.updateBalance(bal ?? 0.0, bp.bonusBalance);
      final recentRaw    = prefs.getString('recent_cable_cards');
      final lastPurchRaw = prefs.getString('last_cable_purchase');
      setState(() {
        allPackages = pkgs; isLoading = false;
        if (recentRaw != null) _recentCards = List<String>.from(jsonDecode(recentRaw) as List);
        if (lastPurchRaw != null) _lastPurchase = Map<String, dynamic>.from(jsonDecode(lastPurchRaw) as Map);
      });
    } catch (_) {}
  }

  Future<void> _saveRecentCard(String iuc) async {
    final updated = [iuc, ..._recentCards.where((c) => c != iuc)].take(5).toList();
    setState(() => _recentCards = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recent_cable_cards', jsonEncode(updated));
  }

  Future<void> _saveLastPurchase({required String providerName, required int providerDbId, required String packageName, required String packageId, required double amount, required String iuc, required String phone}) async {
    final data = {'provider_name': providerName, 'provider_db_id': providerDbId, 'package_name': packageName, 'package_id': packageId, 'amount': amount, 'iuc': iuc, 'phone': phone};
    setState(() => _lastPurchase = data);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_cable_purchase', jsonEncode(data));
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
        safeApiCall(Uri.parse('https://amsubnig.com/api/get-cable-plans/'), headers),
      ]);

      double? newBalance;
      List<Map<String, dynamic>> newPackages = [];

      if (results[0].statusCode == 200) {
        final data  = jsonDecode(results[0].body);
        final phone = data['user']?['Phone']?.toString() ?? '';
        if (phone.isNotEmpty) phoneController.text = phone;
        newBalance = double.tryParse(data['user']?['Account_Balance']?.toString() ?? '0') ?? 0.0;
      }

      if (results[1].statusCode == 200) {
        final data = jsonDecode(results[1].body) as Map<String, dynamic>;
        void addPlans(String apiKey, int providerId, String providerName) {
          if (!data.containsKey(apiKey)) return;
          final providerData = data[apiKey] as Map<String, dynamic>;
          final plansList    = providerData['plans'] as List? ?? [];
          final cableId      = providerData['cable_id'];
          for (final plan in plansList) {
            newPackages.add({
              'provider_id':    providerId,
              'provider_db_id': cableId,
              'id':             plan['id']?.toString() ?? '',
              'name':           plan['package'] ?? 'Unknown Package',
              'amount':         double.tryParse(plan['plan_amount']?.toString() ?? '0') ?? 0.0,
              'provider_name':  providerName,
              'product_code':   plan['product_code'] ?? '',
            });
          }
        }
        addPlans('GOTV',     2, 'GOTV');
        addPlans('DSTV',     1, 'DSTV');
        addPlans('STARTIME', 3, 'Startimes');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cable_cache', jsonEncode({'balance': newBalance ?? 0.0, 'packages': newPackages}));

      if (!mounted) return;
      final bp = Provider.of<UserBalanceProvider>(context, listen: false);
      if (newBalance != null) bp.updateBalance(newBalance, bp.bonusBalance);
      setState(() { if (newPackages.isNotEmpty) allPackages = newPackages; isLoading = false; });
      if (selectedProviderId != null) _filterPackages();
    } catch (e) {
      debugPrint('Cable fetch error: $e');
      if (mounted && allPackages.isEmpty) {
        showError('Failed to load plans.');
        setState(() => isLoading = false);
      }
    }
  }

  void _filterPackages() {
    if (selectedProviderId == null) return;
    final provider = providers.firstWhere((p) => p['id'] == selectedProviderId);
    setState(() {
      filteredPackages  = allPackages.where((p) => p['provider_name'] == provider['name']).toList();
      selectedPackageId = null;
    });
  }

  void _scrollToPackages() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _packageSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut, alignment: 0.05);
      }
    });
  }

  // ── Validate smart card ───────────────────────────────────────────────────

  Future<void> validateSmartCard() async {
    final iuc   = smartCardController.text.trim();
    final phone = phoneController.text.trim();

    if (selectedProviderId == null) return showError('Select a provider first');
    if (iuc.isEmpty || iuc.length < 10) return showError('Enter a valid Smart Card / IUC number');
    if (!RegExp(r'^0[7-9][0-1]\d{8}$').hasMatch(phone)) return showError('Enter valid phone number (e.g. 08012345678)');

    setState(() { isValidating = true; isValidationSuccess = false; customerName = null; });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        showError('Session expired.');
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      final provider   = providers.firstWhere((p) => p['id'] == selectedProviderId);
      final cablename  = provider['code'] as String;

      final uri = Uri.parse('https://amsubnig.com/api/validate-iuc/').replace(
        queryParameters: {'smart_card_number': iuc, 'cablename': cablename},
      );

      final response = await http.get(uri, headers: {'Authorization': 'Token $token'}).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['invalid'] == true) {
          showError('Invalid IUC: ${data['name']}');
        } else {
          setState(() { customerName = data['name']?.toString() ?? 'Customer'; isValidationSuccess = true; });
          await _showValidationDialog(
            customerName: customerName!,
            providerName: provider['name'] as String,
            smartCard: iuc,
            phone: phone,
          );
          _scrollToPackages();
        }
      } else {
        showError('Validation failed (${response.statusCode})');
      }
    } catch (_) { showError('Validation failed. Please try again.'); }
    finally { if (mounted) setState(() => isValidating = false); }
  }

  Future<void> _showValidationDialog({required String customerName, required String providerName, required String smartCard, required String phone}) async {
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
              const Expanded(child: Text('Smart Card Validated!', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
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
                  _dialogRow(Icons.person,      'Customer',   customerName),
                  const Divider(height: 10, thickness: 0.5),
                  _dialogRow(Icons.tv_rounded,  'Provider',   providerName),
                  const Divider(height: 10, thickness: 0.5),
                  _dialogRow(Icons.credit_card, 'Smart Card', smartCard),
                  const Divider(height: 10, thickness: 0.5),
                  _dialogRow(Icons.phone,       'Phone',      phone),
                ]),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.withOpacity(0.4))),
                child: const Row(children: [Icon(Icons.info_rounded, color: Colors.amber, size: 16), SizedBox(width: 8), Expanded(child: Text('Select a cable plan below to continue', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w500, fontSize: 12)))]),
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Continue', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              )),
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
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText), maxLines: 2, overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );

  // ── Submit: confirm dialog → PIN → API ───────────────────────────────────

  Future<void> submitPayment() async {
    final bp             = Provider.of<UserBalanceProvider>(context, listen: false);
    final currentBalance = bp.balance;

    if (!isValidationSuccess) return showError('Validate IUC first');
    if (selectedPackageId == null) return showError('Select a package');

    final iuc              = smartCardController.text.trim();
    final phone            = phoneController.text.trim();
    final capturedProvider = providers.firstWhere((p) => p['id'] == selectedProviderId);
    final capturedPackage  = filteredPackages.firstWhere((p) => p['id'] == selectedPackageId);
    final capturedCustomer = customerName ?? 'Customer';
    final packageAmount    = capturedPackage['amount'] as double;

    if (currentBalance < packageAmount) return showError('Insufficient balance. Please fund your wallet.');

    // ── Step 1: Confirmation dialog ───────────────────────────────────────
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: lightPurple, shape: BoxShape.circle), child: const Icon(Icons.tv_rounded, color: primaryPurple, size: 26)),
            const SizedBox(height: 12),
            const Text('Confirm Subscription', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _confirmRow('Smart Card', iuc),
                _confirmRow('Provider',   capturedProvider['name'].toString()),
                _confirmRow('Package',    capturedPackage['name'].toString()),
                _confirmRow('Amount',     '₦${packageAmount.toStringAsFixed(0)}'),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11)),
                child: const Text('Cancel', style: TextStyle(fontSize: 13)),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 11)),
                child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              )),
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
        Uri.parse('https://amsubnig.com/api/cable-subscription/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'cablename':         capturedProvider['db_id'] as int,
          'smart_card_number': iuc,
          'phone':             phone,
          'cableplan':         int.tryParse(capturedPackage['id'].toString()) ?? 0,
          'customer_name':     capturedCustomer,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        bp.updateBalance(currentBalance - packageAmount, bp.bonusBalance);
        showSuccess('✅ Subscription successful!');
        await _saveRecentCard(iuc);
        await _saveLastPurchase(
          providerName:  capturedProvider['name'] as String,
          providerDbId:  capturedProvider['db_id'] as int,
          packageName:   capturedPackage['name'] as String,
          packageId:     capturedPackage['id'].toString(),
          amount:        packageAmount,
          iuc:           iuc,
          phone:         phone,
        );
        resetForm();
        if (mounted) {
          showDialog(context: context, builder: (_) => _CableReceiptDialog(
            receipt: data,
            providerName: capturedProvider['name'] as String,
            packageName: capturedPackage['name'] as String,
            amount: packageAmount,
          ));
        }
      } else if (response.statusCode == 400) {
        showError('Payment failed: ${_extractError(jsonDecode(response.body))}');
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
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText), maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]),
  );

  String _extractError(Map<String, dynamic> r) {
    for (final k in ['error', 'detail', 'non_field_errors']) {
      if (r.containsKey(k)) { final v = r[k]; return v is List ? v.first.toString() : v.toString(); }
    }
    return 'Unknown error occurred';
  }

  void resetForm() {
    smartCardController.clear();
    setState(() {
      selectedProviderId  = null; selectedPackageId = null;
      isValidationSuccess = false; customerName = null;
      filteredPackages    = [];
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
    final bp             = Provider.of<UserBalanceProvider>(context);
    final walletBalance  = bp.balance;
    final selectedPkg    = selectedPackageId != null
        ? filteredPackages.firstWhere((p) => p['id'] == selectedPackageId, orElse: () => <String, dynamic>{})
        : null;
    final packageAmount  = (selectedPkg?['amount'] as double?) ?? 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        title: const Text('Cable TV Subscription', style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16)),
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

                  // ── 1. Provider ───────────────────────────────────
                  _sectionHeader('1. Select TV Provider', Icons.tv_rounded),
                  const SizedBox(height: 10),
                  _buildProviderRow(),
                  const SizedBox(height: 20),

                  // ── 2. Smart card ─────────────────────────────────
                  _sectionHeader('2. Smart Card / IUC Number', Icons.credit_card),
                  const SizedBox(height: 8),
                  _buildInputField(
                    controller: smartCardController,
                    hint: 'Enter Smart Card / IUC number',
                    icon: Icons.credit_card,
                    keyboard: TextInputType.number,
                    readOnly: isValidationSuccess,
                    onChanged: (_) => setState(() => isValidationSuccess = false),
                  ),
                  if (_recentCards.isNotEmpty && !isValidationSuccess) ...[
                    const SizedBox(height: 8),
                    _buildRecentCards(),
                  ],
                  const SizedBox(height: 14),

                  // ── 3. Phone ──────────────────────────────────────
                  _sectionHeader('3. Phone Number', Icons.phone),
                  const SizedBox(height: 8),
                  _buildInputField(
                    controller: phoneController,
                    hint: '08012345678',
                    icon: Icons.phone_rounded,
                    keyboard: TextInputType.phone,
                    readOnly: isValidationSuccess,
                    onChanged: (_) => setState(() => isValidationSuccess = false),
                  ),
                  const SizedBox(height: 16),

                  // ── Validate button ───────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isValidating ? null : validateSmartCard,
                      style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 3),
                      child: isValidating
                          ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)), SizedBox(width: 10), Text('Validating…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))])
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.verified_rounded, size: 18), SizedBox(width: 8), Text('VALIDATE SMART CARD', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]),
                    ),
                  ),

                  if (isValidationSuccess) ...[
                    const SizedBox(height: 16),
                    SizedBox(key: _packageSectionKey, height: 0),

                    // ── 4. Package ────────────────────────────────
                    _sectionHeader('4. Select Package', Icons.layers),
                    const SizedBox(height: 10),
                    _buildPackageSelector(),

                    const SizedBox(height: 14),
                    _buildCustomerInfoCard(),

                    if (selectedPackageId != null) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: isSubmitting ? null : submitPayment,
                          style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 6),
                          child: isSubmitting
                              ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)), SizedBox(width: 10), Text('Processing…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))])
                              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.shopping_cart_rounded, size: 20), const SizedBox(width: 8), Text('PAY NOW  •  ₦${packageAmount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]),
                        ),
                      ),
                    ],
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

  // ── Skeleton ──────────────────────────────────────────────────────────────

  // ── Quick repeat banner ─────────────────────────────────────────────────────
  Widget _buildLastPurchaseBanner(double balance) {
    final lp          = _lastPurchase!;
    final amount      = (lp['amount'] as num?)?.toDouble() ?? 0;
    final iuc         = lp['iuc']           as String? ?? '';
    final phone       = lp['phone']         as String? ?? '';
    final provName    = lp['provider_name'] as String? ?? '';
    final pkgName     = lp['package_name']  as String? ?? '';
    final provDbId    = (lp['provider_db_id'] as num?)?.toInt();
    final pkgId       = lp['package_id']    as String? ?? '';
    final canAfford   = balance >= amount;

    return GestureDetector(
      onTap: canAfford ? () {
        final prov = providers.firstWhere((p) => p['db_id'] == provDbId, orElse: () => providers.first);
        setState(() {
          selectedProviderId  = prov['id'] as int;
          selectedPackageId   = null;
          isValidationSuccess = false;
          customerName        = null;
          filteredPackages    = allPackages.where((p) => p['provider_name'] == prov['name']).toList();
          smartCardController.text = iuc;
          phoneController.text     = phone;
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
            Text('$provName  ·  $pkgName  ·  ₦${amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: darkText)),
            Text('Card: $iuc  ·  $phone', style: const TextStyle(fontSize: 11, color: lightText)),
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

  // ── Recent smart card chips ───────────────────────────────────────────────
  Widget _buildRecentCards() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Recent', style: TextStyle(fontSize: 10, color: lightText, letterSpacing: 0.3)),
      const SizedBox(height: 5),
      Wrap(spacing: 7, runSpacing: 6, children: _recentCards.map((card) {
        final isActive = smartCardController.text == card;
        return GestureDetector(
          onTap: () => setState(() { smartCardController.text = card; isValidationSuccess = false; customerName = null; }),
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
              Text(card, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? Colors.white : darkText)),
            ]),
          ),
        );
      }).toList()),
    ]);
  }

  Widget _buildSkeletonLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: [
        Container(height: 18, width: 160, color: Colors.white),
        const SizedBox(height: 10),
        Row(children: List.generate(3, (_) => Expanded(child: Container(height: 80, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)))))),
        const SizedBox(height: 20),
        ...List.generate(3, (_) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Container(height: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))))),
      ]),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  /// Horizontal row of provider cards (only 3, looks better as a row than a grid)
  Widget _buildProviderRow() {
    return Row(
      children: providers.map((provider) {
        final isSelected  = selectedProviderId == provider['id'];
        final imagePath   = provider['image'] as String;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() { selectedProviderId = provider['id'] as int; isValidationSuccess = false; selectedPackageId = null; });
              _filterPackages();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.only(
                left:  providers.indexOf(provider) == 0 ? 0 : 5,
                right: providers.indexOf(provider) == providers.length - 1 ? 0 : 5,
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected ? primaryPurple.withOpacity(0.08) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isSelected ? primaryPurple : Colors.grey[200]!, width: isSelected ? 2 : 1),
                boxShadow: [BoxShadow(color: isSelected ? primaryPurple.withOpacity(0.15) : Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(
                  height: 44,
                  child: Image.asset(imagePath, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(Icons.tv_rounded, size: 32, color: isSelected ? primaryPurple : lightText)),
                ),
                const SizedBox(height: 6),
                Text(
                  provider['name'] as String,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? primaryPurple : darkText),
                ),
                if (isSelected) ...[const SizedBox(height: 3), const Icon(Icons.check_circle_rounded, size: 13, color: Colors.green)],
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInputField({required TextEditingController controller, required String hint, required IconData icon, TextInputType keyboard = TextInputType.text, bool readOnly = false, void Function(String)? onChanged}) {
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
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
          ),
          onChanged: onChanged,
        )),
      ]),
    );
  }

  Widget _buildPackageSelector() {
    if (filteredPackages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
        child: const Center(child: Text('No packages available for this provider', style: TextStyle(color: lightText, fontSize: 13))),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredPackages.length,
      itemBuilder: (_, i) {
        final pkg        = filteredPackages[i];
        final isSelected = selectedPackageId == pkg['id'];
        return GestureDetector(
          onTap: () => setState(() => selectedPackageId = pkg['id'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isSelected ? lightPurple : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSelected ? primaryPurple : Colors.grey[200]!, width: isSelected ? 2 : 1),
              boxShadow: [BoxShadow(color: isSelected ? primaryPurple.withOpacity(0.08) : Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isSelected ? primaryPurple : lightText, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(pkg['name'] as String, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isSelected ? primaryPurple : darkText))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: isSelected ? primaryPurple : Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(18)),
                child: Text('₦${(pkg['amount'] as double).toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? Colors.white : Colors.green[700])),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildCustomerInfoCard() {
    final selProvider = providers.firstWhere((p) => p['id'] == selectedProviderId, orElse: () => {'name': 'N/A'});
    final selPkg      = filteredPackages.firstWhere((p) => p['id'] == selectedPackageId, orElse: () => {'name': 'N/A', 'amount': 0.0});
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.green.shade50, Colors.green.shade100.withOpacity(0.4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.verified_rounded, color: Colors.green, size: 17), SizedBox(width: 6), Text('Smart Card Validated', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green))]),
        const SizedBox(height: 10),
        _infoRow('Customer',   customerName ?? 'Customer',                       Icons.person),
        _infoRow('Smart Card', smartCardController.text.trim(),                  Icons.credit_card),
        _infoRow('Phone',      phoneController.text.trim(),                      Icons.phone),
        _infoRow('Provider',   selProvider['name'].toString(),                   Icons.tv_rounded),
        if (selectedPackageId != null) ...[
          _infoRow('Package',  selPkg['name'].toString(),                        Icons.layers),
          _infoRow('Amount',   '₦${(selPkg['amount'] as double).toStringAsFixed(0)}', Icons.payments),
        ],
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt Dialog (unchanged logic, sizes tightened)
// ─────────────────────────────────────────────────────────────────────────────
class _CableReceiptDialog extends StatefulWidget {
  final Map<String, dynamic> receipt;
  final String providerName;
  final String packageName;
  final double amount;

  const _CableReceiptDialog({required this.receipt, required this.providerName, required this.packageName, required this.amount});

  @override
  State<_CableReceiptDialog> createState() => _CableReceiptDialogState();
}

class _CableReceiptDialogState extends State<_CableReceiptDialog> {
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
      if (byteData == null) throw Exception('Failed to encode');
      final pngBytes = byteData.buffer.asUint8List();
      final tempDir  = await getTemporaryDirectory();
      final file     = File('${tempDir.path}/cable_receipt_${DateTime.now().millisecondsSinceEpoch}.png');
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
    final transId     = r['ident']?.toString() ?? 'N/A';
    final amountStr   = r['paid_amount']?.toString() ?? widget.amount.toStringAsFixed(0);

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
            const Expanded(child: Text('Subscription Receipt', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
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
              // Status + provider logo side by side
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: statusColor.withAlpha(20), shape: BoxShape.circle), child: Icon(statusIcon, color: statusColor, size: 24)),
                const SizedBox(width: 14),
                SizedBox(height: 32, child: Image.asset(
                  'assets/images/${widget.providerName.toLowerCase().replaceAll(' ', '')}.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                )),
              ]),
              const SizedBox(height: 4),
              Text(rawStatus.toUpperCase(), style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              _infoGrid(label1: 'Customer',   value1: r['customer_name']?.toString() ?? 'N/A',     label2: 'Smart Card', value2: r['smart_card_number']?.toString() ?? 'N/A'),
              const SizedBox(height: 8),
              _infoGrid(label1: 'Provider',   value1: widget.providerName,                          label2: 'Package',    value2: widget.packageName),
              const SizedBox(height: 8),
              _infoGrid(label1: 'Amount',     value1: '₦$amountStr',                               label2: 'Phone',      value2: r['phone']?.toString() ?? 'N/A'),
              const SizedBox(height: 8),
              _infoGrid(label1: 'Reference',  value1: transId,                                      label2: 'Date',       value2: DateTime.now().toString().substring(0, 16)),
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