import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/pin_auth_service.dart';
import '../providers/user_balance_provider.dart';

class BuyAirtimeScreen extends StatefulWidget {
  const BuyAirtimeScreen({super.key});

  @override
  State<BuyAirtimeScreen> createState() => _BuyAirtimeScreenState();
}

class _BuyAirtimeScreenState extends State<BuyAirtimeScreen> {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color primaryBlue   = Color(0xFF3B82F6);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  final phoneController  = TextEditingController();
  final amountController = TextEditingController();

  bool bypassValidation = true;
  String? selectedNetwork;
  String? selectedAirtimeType;
  int?    selectedPrefilledAmount;

  List<Map<String, dynamic>> networks = [];
  bool isLoading    = true;
  bool isSubmitting = false;

  String? userType;
  Map<String, dynamic>? vtuPercentages;
  Map<String, dynamic>? shareAndSellPercentages;

  // ── New UX state ──────────────────────────────────────────────────────────
  List<String>          _recentNumbers = [];
  Map<String, dynamic>? _lastPurchase;

  final List<int> prefilledAmounts = [50, 100, 200, 500, 1000, 2000, 5000];

  final List<Map<String, String>> airtimeTypes = [
    {'value': 'VTU',            'label': 'VTU',          'description': 'Direct recharge'},
    {'value': 'Share and Sell', 'label': 'Share & Sell', 'description': 'Transfer to others'},
  ];

  // ── Computed ──────────────────────────────────────────────────────────────
  bool get isPhoneValid  => normalizePhoneNumber(phoneController.text.trim()) != null;
  bool get isAmountValid {
    final a = double.tryParse(amountController.text.trim()) ?? 0;
    return a >= (selectedAirtimeType == 'VTU' ? 50 : 100);
  }
  bool get canBuy => selectedNetwork != null && selectedAirtimeType != null && isPhoneValid && isAmountValid && !isSubmitting;

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    fetchAllData();
  }

  @override
  void dispose() {
    phoneController.dispose();
    amountController.dispose();
    super.dispose();
  }

  // ── API helpers ───────────────────────────────────────────────────────────
  Future<http.Response> safeApiCall(Uri url, Map<String, String> headers) async {
    try { return await http.get(url, headers: headers).timeout(const Duration(seconds: 15)); }
    catch (_) { await Future.delayed(const Duration(seconds: 2)); return await http.get(url, headers: headers); }
  }

  Future<void> _loadCachedData() async {
    final prefs  = await SharedPreferences.getInstance();
    final cached = prefs.getString('buy_airtime_cache');
    if (cached == null) return;
    try {
      final json   = jsonDecode(cached) as Map<String, dynamic>;
      final bal    = json['balance'] as double?;
      final netList= (json['networks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final vtu    = json['vtu']    as Map<String, dynamic>?;
      final share  = json['share']  as Map<String, dynamic>?;
      final uType  = json['userType'] as String?;
      for (var net in netList) { net['color'] = _getNetworkColor(net['key'] as String); }
      if (!mounted) return;
      final bp = Provider.of<UserBalanceProvider>(context, listen: false);
      bp.updateBalance(bal ?? 0.0, bp.bonusBalance);
      final recentRaw    = prefs.getString('recent_airtime_numbers');
      final lastPurchRaw = prefs.getString('last_airtime_purchase');
      setState(() {
        networks = netList; vtuPercentages = vtu;
        shareAndSellPercentages = share; userType = uType; isLoading = false;
        if (recentRaw != null) _recentNumbers = List<String>.from(jsonDecode(recentRaw) as List);
        if (lastPurchRaw != null) _lastPurchase = Map<String, dynamic>.from(jsonDecode(lastPurchRaw) as Map);
      });
    } catch (_) {}
  }

  Future<void> fetchAllData() async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) { if (mounted) Navigator.pushReplacementNamed(context, '/login'); return; }
      final headers = {'Authorization': 'Token $token'};
      final results = await Future.wait([
        safeApiCall(Uri.parse('https://amsubnig.com/api/user/'), headers),
        safeApiCall(Uri.parse('https://amsubnig.com/api/network-plans/'), headers),
        safeApiCall(Uri.parse('https://amsubnig.com/api/user-discounts/'), headers),
      ]);

      double? newBalance;
      List<Map<String, dynamic>> newNetworks = [];
      Map<String, dynamic>? newVtu, newShare;
      String? newUserType;

      if (results[0].statusCode == 200) {
        final data = jsonDecode(results[0].body);
        newBalance = double.tryParse(data['user']?['Account_Balance']?.toString() ?? '0') ?? 0.0;
      }
      if (results[1].statusCode == 200) {
        final data = jsonDecode(results[1].body) as Map<String, dynamic>;
        for (final key in ['MTN', 'GLO', 'AIRTEL', '9MOBILE']) {
          if (!data.containsKey(key)) continue;
          final netInfo = data[key]['network_info'] as Map? ?? {};
          newNetworks.add({'key': key, 'name': key == '9MOBILE' ? '9mobile' : key, 'image': 'assets/images/${key.toLowerCase()}.png', 'id': netInfo['id']?.toString() ?? _getNetworkIdFromKey(key).toString()});
        }
      }
      if (results[2].statusCode == 200) {
        final data = jsonDecode(results[2].body);
        newUserType = data['user_type']?.toString();
        newVtu   = Map<String, dynamic>.from(data['vtu_percentages'] ?? {});
        newShare = Map<String, dynamic>.from(data['share_and_sell_percentages'] ?? {});
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('buy_airtime_cache', jsonEncode({'balance': newBalance ?? 0.0, 'networks': newNetworks, 'vtu': newVtu, 'share': newShare, 'userType': newUserType}));
      for (var net in newNetworks) { net['color'] = _getNetworkColor(net['key'] as String); }

      if (!mounted) return;
      final bp = Provider.of<UserBalanceProvider>(context, listen: false);
      if (newBalance != null) bp.updateBalance(newBalance, bp.bonusBalance);
      setState(() {
        if (newNetworks.isNotEmpty) networks = newNetworks;
        vtuPercentages = newVtu; shareAndSellPercentages = newShare; userType = newUserType; isLoading = false;
      });
    } catch (e) {
      debugPrint('Airtime fetch error: $e');
      if (mounted && networks.isEmpty) { showError('Failed to load. Showing cache if available.'); setState(() => isLoading = false); }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String? normalizePhoneNumber(String phone) {
    if (phone.isEmpty) return null;
    String d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11 && d.startsWith('0'))    return d;
    if (d.length == 10 && !d.startsWith('0'))   return '0$d';
    if (d.length == 13 && d.startsWith('234'))  return '0${d.substring(3)}';
    if (d.startsWith('+234')) { final w = d.replaceFirst('+', ''); if (w.length == 13) return '0${w.substring(3)}'; }
    return null;
  }

  Future<void> pickFromContacts() async {
    try {
      if (await Permission.contacts.request().isGranted) {
        final contact = await FlutterContacts.openExternalPick();
        if (contact != null && contact.phones.isNotEmpty) {
          final raw  = contact.phones.first.number ?? '';
          final norm = normalizePhoneNumber(raw.replaceAll(RegExp(r'[\s\-\(\)]'), ''));
          setState(() => phoneController.text = norm ?? raw);
          norm != null ? showSuccess('Contact selected') : showError('Could not format — please edit manually.');
        }
      } else { showError('Contacts permission denied'); }
    } catch (_) { showError('Could not pick contact'); }
  }

  Color _getNetworkColor(String network) {
    switch (network.toUpperCase()) {
      case 'MTN':     return const Color(0xFFFFCC00);
      case 'GLO':     return const Color(0xFF00B140);
      case 'AIRTEL':  return const Color(0xFFE40046);
      case '9MOBILE': return const Color(0xFF00A859);
      default:        return primaryPurple;
    }
  }

  int _getNetworkIdFromKey(String key) => {'MTN': 1, 'GLO': 2, 'AIRTEL': 3, '9MOBILE': 4}[key] ?? 1;

  double calculateDiscountedAmount(double amount) {
    if (selectedNetwork == null || selectedAirtimeType == null || amount <= 0) return amount;
    final pctStr = selectedAirtimeType == 'VTU'
        ? (vtuPercentages?[selectedNetwork]?.toString())
        : (shareAndSellPercentages?[selectedNetwork]?.toString());
    final pct = double.tryParse(pctStr ?? '100') ?? 100.0;
    return amount * (pct / 100);
  }

  Future<void> _saveRecentNumber(String phone) async {
    final updated = [phone, ..._recentNumbers.where((n) => n != phone)].take(5).toList();
    setState(() => _recentNumbers = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recent_airtime_numbers', jsonEncode(updated));
  }

  Future<void> _saveLastPurchase(double amount, double discounted, String phone, String network, String type) async {
    final data = {'amount': amount, 'discounted': discounted, 'phone': phone, 'network': network, 'type': type};
    setState(() => _lastPurchase = data);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_airtime_purchase', jsonEncode(data));
  }

  // ── Submit: confirm → PIN → API ───────────────────────────────────────────
  Future<void> submitPurchase() async {
    final bp             = Provider.of<UserBalanceProvider>(context, listen: false);
    final currentBalance = bp.balance;
    final phone          = normalizePhoneNumber(phoneController.text.trim()) ?? phoneController.text.trim();
    final amount         = double.tryParse(amountController.text.trim()) ?? 0;

    if (selectedNetwork == null)     return showError('Select a network');
    if (selectedAirtimeType == null) return showError('Select airtime type');
    if (amount < (selectedAirtimeType == 'VTU' ? 50 : 100)) return showError('Amount too low');
    if (!isPhoneValid) return showError('Invalid phone number');

    final discountedAmount = calculateDiscountedAmount(amount);
    if (currentBalance < discountedAmount) return showError('Insufficient balance. Please fund your wallet.');

    // ── Step 1: Confirm dialog ────────────────────────────────────────────
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: lightPurple, shape: BoxShape.circle), child: const Icon(Icons.phone_android, color: primaryPurple, size: 26)),
            const SizedBox(height: 12),
            const Text('Confirm Airtime Purchase', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _confirmRow('Network', selectedNetwork ?? ''),
                _confirmRow('Type',    selectedAirtimeType ?? ''),
                _confirmRow('Phone',   phone),
                _confirmRow('Amount',  '₦${amount.toStringAsFixed(0)}'),
                if (discountedAmount < amount)
                  _confirmRow('You Pay', '₦${discountedAmount.toStringAsFixed(0)}  ✓ discount', highlight: true),
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
      if (token == null) { showError('Session expired'); if (mounted) Navigator.pushReplacementNamed(context, '/login'); return; }

      final networkData = networks.firstWhere((n) => n['key'] == selectedNetwork);
      final networkId   = int.tryParse(networkData['id']?.toString() ?? '1') ?? 1;

      final response = await http.post(
        Uri.parse('https://amsubnig.com/api/topup/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'network': networkId, 'amount': amount.toInt(), 'mobile_number': phone, 'Ported_number': bypassValidation, 'airtime_type': selectedAirtimeType}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result          = jsonDecode(response.body) as Map<String, dynamic>;
        final capturedNetwork = selectedNetwork ?? '';
        final capturedType    = selectedAirtimeType ?? '';

        bp.updateBalance(currentBalance - discountedAmount, bp.bonusBalance);
        await _saveRecentNumber(phone);
        await _saveLastPurchase(amount, discountedAmount, phone, capturedNetwork, capturedType);

        setState(() { selectedAirtimeType = null; selectedNetwork = null; selectedPrefilledAmount = null; });
        phoneController.clear();
        amountController.clear();

        showSuccess('✅ Airtime purchased successfully!');
        if (mounted) _showReceiptDialog(result, amount, phone, capturedNetwork, capturedType);
      } else {
        final err = jsonDecode(response.body);
        showError('❌ ${err['error'] ?? 'Purchase failed (${response.statusCode})'}');
      }
    } catch (_) { showError('❌ Network error. Please try again.'); }
    finally { if (mounted) setState(() => isSubmitting = false); }
  }

  Widget _confirmRow(String label, String value, {bool highlight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 72, child: Text(label, style: const TextStyle(fontSize: 11, color: lightText))),
      const SizedBox(width: 6),
      Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: highlight ? Colors.green : darkText), overflow: TextOverflow.ellipsis)),
    ]),
  );

  void _showReceiptDialog(Map<String, dynamic> receipt, double amount, String phone, String networkKey, String airtimeType) {
    showDialog(context: context, builder: (_) => _AirtimeReceiptDialog(
      receipt: receipt, amount: amount,
      discountedAmount: calculateDiscountedAmount(amount),
      phone: phone, networkKey: networkKey, airtimeType: airtimeType,
      onBuyAgain: () => setState(() { selectedNetwork = null; selectedAirtimeType = null; selectedPrefilledAmount = null; }),
    ));
  }

  void showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error, color: Colors.white, size: 18), const SizedBox(width: 10), Expanded(child: Text(msg, style: const TextStyle(fontSize: 13)))]),
      backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), duration: const Duration(seconds: 4),
    ));
  }

  void showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 18), const SizedBox(width: 10), Expanded(child: Text(msg, style: const TextStyle(fontSize: 13)))]),
      backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), duration: const Duration(seconds: 3),
    ));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bp           = Provider.of<UserBalanceProvider>(context);
    final walletBalance= bp.balance;
    final amount       = double.tryParse(amountController.text.trim()) ?? 0;
    final discounted   = calculateDiscountedAmount(amount);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        title: const Text('Buy Airtime', style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true, elevation: 0, backgroundColor: Colors.white, foregroundColor: darkText, toolbarHeight: 48,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: primaryPurple, size: 20), onPressed: fetchAllData)],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await fetchAllData(); await bp.refresh(); },
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
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // ── Quick repeat ──────────────────────────────────
                  if (_lastPurchase != null) ...[
                    _buildLastPurchaseBanner(walletBalance),
                    const SizedBox(height: 16),
                  ],

                  // ── 1. Network ────────────────────────────────────
                  _sectionLabel('1. Select Network', Icons.sim_card),
                  const SizedBox(height: 10),
                  _buildNetworkGrid(),
                  const SizedBox(height: 20),

                  // ── 2. Airtime type ───────────────────────────────
                  _sectionLabel('2. Airtime Type', Icons.category),
                  const SizedBox(height: 10),
                  _buildAirtimeTypeSelector(),
                  const SizedBox(height: 20),

                  // ── 3. Phone ──────────────────────────────────────
                  _sectionLabel('3. Phone Number', Icons.phone),
                  const SizedBox(height: 8),
                  _buildPhoneInput(),
                  if (_recentNumbers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildRecentNumbers(),
                  ],
                  const SizedBox(height: 20),

                  // ── 4. Amount ─────────────────────────────────────
                  _sectionLabel('4. Amount', Icons.payments),
                  const SizedBox(height: 8),
                  _buildAmountInput(),

                  if (selectedAirtimeType != null) ...[
                    const SizedBox(height: 12),
                    const Text('Quick Amounts', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: lightText)),
                    const SizedBox(height: 8),
                    _buildPrefilledAmounts(walletBalance),
                  ],

                  // ── Discount summary ──────────────────────────────
                  if (amount > 0 && discounted < amount) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.3))),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('You pay after discount:', style: TextStyle(color: Colors.green, fontSize: 13)),
                        Text('₦${discounted.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 100),
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: canBuy
          ? Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isSubmitting ? null : (discounted <= walletBalance ? submitPurchase : () => showError('Insufficient balance')),
            style: ElevatedButton.styleFrom(
              backgroundColor: discounted <= walletBalance ? primaryPurple : lightText,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              elevation: 8, shadowColor: primaryPurple.withOpacity(0.45),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: isSubmitting
                  ? const Row(key: ValueKey('l'), mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)), SizedBox(width: 12), Text('Processing…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))])
                  : Row(key: const ValueKey('i'), mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.shopping_cart_rounded, size: 20), const SizedBox(width: 8), Text('BUY AIRTIME  •  ₦${discounted.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]),
            ),
          ),
        ),
      )
          : null,
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _sectionLabel(String title, IconData icon) => Row(children: [
    Icon(icon, color: primaryPurple, size: 17),
    const SizedBox(width: 7),
    Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: darkText)),
  ]);

  Widget _buildLastPurchaseBanner(double balance) {
    final lp         = _lastPurchase!;
    final amount     = (lp['amount'] as num?)?.toDouble() ?? 0;
    final discounted = (lp['discounted'] as num?)?.toDouble() ?? amount;
    final phone      = lp['phone']   as String? ?? '';
    final network    = lp['network'] as String? ?? '';
    final type       = lp['type']    as String? ?? '';
    final canAfford  = balance >= discounted;

    return GestureDetector(
      onTap: canAfford ? () => setState(() {
        selectedNetwork     = network;
        selectedAirtimeType = type;
        selectedPrefilledAmount = amount.toInt();
        phoneController.text    = phone;
        amountController.text   = amount.toStringAsFixed(0);
      }) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [primaryPurple.withOpacity(0.08), primaryBlue.withOpacity(0.06)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primaryPurple.withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primaryPurple.withOpacity(0.12), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.replay_rounded, color: primaryPurple, size: 17)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Quick Repeat', style: TextStyle(fontSize: 10, color: lightText)),
            const SizedBox(height: 2),
            Text('$network  $type  ₦${amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: darkText)),
            Text(phone, style: const TextStyle(fontSize: 11, color: lightText)),
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

  Widget _buildRecentNumbers() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Recent', style: TextStyle(fontSize: 10, color: lightText, letterSpacing: 0.3)),
      const SizedBox(height: 5),
      Wrap(spacing: 7, runSpacing: 6, children: _recentNumbers.map((num) {
        final isActive = phoneController.text == num;
        return GestureDetector(
          onTap: () => setState(() => phoneController.text = num),
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
              Text(num, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? Colors.white : darkText)),
            ]),
          ),
        );
      }).toList()),
    ]);
  }

  /// 4-column grid — matches buy data screen exactly
  Widget _buildNetworkGrid() {
    if (networks.isEmpty) return const Center(child: Text('No networks available', style: TextStyle(color: lightText, fontSize: 12)));
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.95),
      itemCount: networks.length,
      itemBuilder: (_, i) {
        final network    = networks[i];
        final key        = network['key']?.toString() ?? '';
        final isSelected = selectedNetwork == key;
        final color      = (network['color'] as Color?) ?? primaryPurple;
        final imagePath  = network['image']?.toString() ?? '';
        return GestureDetector(
          onTap: () => setState(() { selectedNetwork = key; selectedPrefilledAmount = null; }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? color : Colors.grey[200]!, width: isSelected ? 2 : 1),
              boxShadow: [BoxShadow(color: isSelected ? color.withOpacity(0.15) : Colors.black.withOpacity(0.04), blurRadius: 5, offset: const Offset(0, 2))],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 30, child: imagePath.isNotEmpty ? Image.asset(imagePath, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.sim_card, size: 22, color: color)) : Icon(Icons.sim_card, size: 22, color: color)),
              const SizedBox(height: 3),
              Text(network['name']?.toString() ?? key, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isSelected ? color : darkText), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            ]),
          ),
        );
      },
    );
  }

  /// Compact horizontal 2-pill selector — replaces the tall card list
  Widget _buildAirtimeTypeSelector() {
    return Row(children: airtimeTypes.asMap().entries.map((entry) {
      final i          = entry.key;
      final type       = entry.value;
      final isSelected = selectedAirtimeType == type['value'];
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() { selectedAirtimeType = type['value']; selectedPrefilledAmount = null; }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            decoration: BoxDecoration(
              color: isSelected ? primaryPurple : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? primaryPurple : Colors.grey[200]!, width: isSelected ? 2 : 1),
              boxShadow: [BoxShadow(color: isSelected ? primaryPurple.withOpacity(0.2) : Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(type['value'] == 'VTU' ? Icons.phone_android : Icons.people, color: isSelected ? Colors.white : lightText, size: 16),
              const SizedBox(width: 7),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(type['label']!, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : darkText, fontSize: 13)),
                Text(type['description']!, style: TextStyle(fontSize: 10, color: isSelected ? Colors.white70 : lightText)),
              ])),
              if (isSelected) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            ]),
          ),
        ),
      );
    }).toList());
  }

  Widget _buildPhoneInput() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Row(children: [
        const Padding(padding: EdgeInsets.only(left: 14), child: Icon(Icons.phone, color: primaryPurple, size: 18)),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontSize: 14, color: darkText),
          decoration: const InputDecoration(hintText: '08012345678', border: InputBorder.none, hintStyle: TextStyle(color: lightText, fontSize: 13), contentPadding: EdgeInsets.symmetric(vertical: 13)),
          onChanged: (_) => setState(() {}),
        )),
        if (phoneController.text.isNotEmpty)
          GestureDetector(onTap: () => setState(() => phoneController.clear()), child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.clear, size: 16, color: lightText))),
        Container(height: 46, width: 1, color: Colors.grey[200]),
        InkWell(onTap: pickFromContacts, borderRadius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)), child: const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(Icons.contacts_rounded, color: primaryPurple, size: 20))),
      ]),
    );
  }

  Widget _buildAmountInput() {
    final orig       = double.tryParse(amountController.text.trim()) ?? 0;
    final discounted = calculateDiscountedAmount(orig);
    final saving     = orig - discounted;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Row(children: [
          const Padding(padding: EdgeInsets.only(left: 14), child: Text('₦', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryPurple))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(
            controller: amountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14, color: darkText),
            decoration: InputDecoration(
              hintText: selectedAirtimeType == 'VTU' ? 'Min ₦50' : 'Min ₦100',
              border: InputBorder.none, hintStyle: const TextStyle(color: lightText, fontSize: 13),
              suffixText: 'NGN', suffixStyle: const TextStyle(color: lightText, fontSize: 12),
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onChanged: (v) => setState(() { if (v.isNotEmpty) selectedPrefilledAmount = null; }),
          )),
        ]),
      ),
      if (saving > 0 && orig > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Row(children: [
            const Icon(Icons.savings_rounded, size: 13, color: Colors.green),
            const SizedBox(width: 5),
            Text('You save ₦${saving.toStringAsFixed(0)} — pay ₦${discounted.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w500)),
          ]),
        ),
    ]);
  }

  /// Affordability dim — same logic as buy data screen
  Widget _buildPrefilledAmounts(double balance) {
    return Wrap(
      spacing: 7, runSpacing: 7,
      children: prefilledAmounts.map((amt) {
        final isSelected  = selectedPrefilledAmount == amt;
        final discounted  = calculateDiscountedAmount(amt.toDouble());
        final hasDiscount = discounted < amt && selectedNetwork != null && selectedAirtimeType != null;
        final canAfford   = balance >= discounted;
        return Opacity(
          opacity: canAfford ? 1.0 : 0.45,
          child: GestureDetector(
            onTap: canAfford ? () => setState(() { selectedPrefilledAmount = amt; amountController.text = amt.toString(); }) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isSelected ? primaryPurple : (canAfford ? Colors.white : Colors.grey[100]!),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? primaryPurple : Colors.grey[200]!),
                boxShadow: [BoxShadow(color: isSelected ? primaryPurple.withOpacity(0.25) : Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('₦$amt', style: TextStyle(color: isSelected ? Colors.white : darkText, fontWeight: FontWeight.w600, fontSize: 12)),
                if (hasDiscount && canAfford) Text('₦${discounted.toStringAsFixed(0)}', style: TextStyle(fontSize: 9, color: isSelected ? Colors.white70 : Colors.green)),
                if (!canAfford) const Text('Low bal.', style: TextStyle(fontSize: 8, color: Colors.red, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSkeletonLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: [
        GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.95), itemCount: 4, itemBuilder: (_, __) => Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 20),
        Row(children: [Expanded(child: Container(height: 58, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)))), const SizedBox(width: 8), Expanded(child: Container(height: 58, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))))]),
        const SizedBox(height: 20),
        Container(height: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
        const SizedBox(height: 20),
        Container(height: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
        const SizedBox(height: 14),
        Wrap(spacing: 7, runSpacing: 7, children: List.generate(7, (_) => Container(width: 68, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt Dialog — compact no-scroll + AMSUBNIG branding
// ─────────────────────────────────────────────────────────────────────────────
class _AirtimeReceiptDialog extends StatefulWidget {
  final Map<String, dynamic> receipt;
  final double amount, discountedAmount;
  final String phone, networkKey, airtimeType;
  final VoidCallback onBuyAgain;

  const _AirtimeReceiptDialog({required this.receipt, required this.amount, required this.discountedAmount, required this.phone, required this.networkKey, required this.airtimeType, required this.onBuyAgain});

  @override
  State<_AirtimeReceiptDialog> createState() => _AirtimeReceiptDialogState();
}

class _AirtimeReceiptDialogState extends State<_AirtimeReceiptDialog> {
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
      final file     = File('${tempDir.path}/airtime_receipt_${DateTime.now().millisecondsSinceEpoch}.png');
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
    final receipt   = widget.receipt;
    final hasSaving = widget.amount - widget.discountedAmount > 0.5;
    final rawStatus = receipt['Status']?.toString() ?? 'pending';
    final statusLow = rawStatus.toLowerCase();
    final isSuccess = statusLow == 'successful' || statusLow == 'success';
    final isPending = statusLow == 'pending'    || statusLow == 'processing';
    final sc        = isSuccess ? Colors.green : isPending ? Colors.orange : Colors.red;
    final si        = isSuccess ? Icons.check_circle_rounded : isPending ? Icons.hourglass_top_rounded : Icons.cancel_rounded;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Dialog header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [primaryPurple, Color(0xFF9B7DFF)]), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.receipt_long, color: Colors.white, size: 19)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Airtime Receipt', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        // Body — no scroll, fits screen
        RepaintBoundary(
          key: _captureKey,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // AMSUBNIG brand
              RichText(text: TextSpan(children: [
                const TextSpan(text: 'AMS', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: primaryPurple, letterSpacing: 1)),
                const TextSpan(text: 'UB',  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF3B82F6), letterSpacing: 1)),
                const TextSpan(text: 'NIG', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF10B981), letterSpacing: 1)),
              ])),
              const Text('Grandfather of Data Vendors', style: TextStyle(fontSize: 9, color: lightText, fontStyle: FontStyle.italic)),
              const SizedBox(height: 10),
              // Status + network logo side by side
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: sc.withAlpha(20), shape: BoxShape.circle), child: Icon(si, color: sc, size: 24)),
                const SizedBox(width: 14),
                SizedBox(height: 32, child: Image.asset('assets/images/${widget.networkKey.toLowerCase()}.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
              ]),
              const SizedBox(height: 4),
              Text(rawStatus.toUpperCase(), style: TextStyle(color: sc, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              // 3 info pairs
              _infoGrid(
                label1: 'Network',  value1: widget.networkKey,
                label2: 'Type',     value2: widget.airtimeType,
              ),
              const SizedBox(height: 8),
              _infoGrid(
                label1: 'Amount',  value1: hasSaving ? '₦${widget.amount.toStringAsFixed(0)}  →  ₦${widget.discountedAmount.toStringAsFixed(0)}' : '₦${widget.amount.toStringAsFixed(0)}',
                label2: 'Phone',   value2: widget.phone,
              ),
              const SizedBox(height: 8),
              _infoGrid(
                label1: 'Reference', value1: receipt['ident']?.toString() ?? 'N/A',
                label2: 'Date',      value2: DateTime.now().toString().substring(0, 16),
              ),
              // Saving badge
              if (hasSaving) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.withOpacity(0.25))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.savings_rounded, size: 13, color: Colors.green),
                    const SizedBox(width: 6),
                    Text('You saved ₦${(widget.amount - widget.discountedAmount).toStringAsFixed(0)} with your discount!', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ]),
          ),
        ),
        // Footer buttons
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
              onPressed: () { Navigator.pop(context); widget.onBuyAgain(); },
              icon: const Icon(Icons.shopping_cart_rounded, size: 16),
              label: const Text('Buy Again', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 11)),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _infoGrid({required String label1, required String value1, required String label2, required String value2}) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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