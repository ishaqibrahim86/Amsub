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
import '../providers/user_balance_provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/pin_auth_service.dart';

class BuyDataScreen extends StatefulWidget {
  const BuyDataScreen({super.key});

  @override
  State<BuyDataScreen> createState() => _BuyDataScreenState();
}

class _BuyDataScreenState extends State<BuyDataScreen> {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color primaryBlue   = Color(0xFF3B82F6);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  final phoneController = TextEditingController();
  bool bypassValidation   = true;
  String? _selectedPlanType = 'All';

  List<Map<String, dynamic>> networks = [];
  Map<String, List<dynamic>> plansByNetwork = {};
  final List<String> planTypes = ['All', 'SME', 'GIFTING', 'SME2', 'AWOOF GIFTING', 'CORPORATE GIFTING'];

  String? selectedNetworkKey;
  String? selectedPlanId;
  bool isLoading    = true;
  bool isSubmitting = false;

  // ── New UX state ──────────────────────────────────────────────────────────
  List<String>             _recentNumbers  = [];      // last 5 used numbers
  Map<String, dynamic>?    _lastPurchase;             // for quick-repeat banner
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Computed ──────────────────────────────────────────────────────────────
  bool get isPhoneValid       => normalizePhoneNumber(phoneController.text.trim()) != null;
  bool get isPlanTypeSelected => _selectedPlanType != null;
  bool get isPlanSelected     => selectedPlanId != null && selectedNetworkKey != null;
  bool get canBuy             => isPhoneValid && isPlanTypeSelected && isPlanSelected && !isSubmitting;
  int  get _planCount         => plansByNetwork[selectedNetworkKey]?.length ?? 0;

  // ── Phone normalisation ───────────────────────────────────────────────────
  String? normalizePhoneNumber(String phone) {
    if (phone.isEmpty) return null;
    String d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11 && d.startsWith('0'))        return d;
    if (d.length == 10 && !d.startsWith('0'))       return '0$d';
    if (d.length == 13 && d.startsWith('234'))      return '0${d.substring(3)}';
    if (d.length == 14 && d.startsWith('2340'))     return '0${d.substring(4)}';
    if (d.length == 14 && d.startsWith('234'))      return '0${d.substring(3)}';
    if (d.length == 12 && d.startsWith('234'))      return '0${d.substring(3)}';
    if (d.startsWith('+234')) {
      final w = d.replaceFirst('+', '');
      if (w.length == 13) return '0${w.substring(3)}';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    fetchUserBalanceAndPlans();
  }

  @override
  void dispose() {
    phoneController.dispose();
    _searchController.dispose();
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
    final cached = prefs.getString('buy_data_cache');
    if (cached == null) return;
    try {
      final json    = jsonDecode(cached) as Map<String, dynamic>;
      final bal     = json['balance'] as double?;
      final netList = (json['networks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final plansMap= <String, List<dynamic>>{};
      for (var e in (json['plans'] as Map? ?? {}).entries) {
        plansMap[e.key as String] = List<dynamic>.from(e.value as List);
      }
      for (var net in netList) { net['color'] = _getNetworkColor(net['key'] as String); }
      if (!mounted) return;
      final bp = Provider.of<UserBalanceProvider>(context, listen: false);
      bp.updateBalance(bal ?? 0.0, bp.bonusBalance);

      // Load recent numbers and last purchase
      final recentRaw   = prefs.getString('recent_data_numbers');
      final lastPurchRaw= prefs.getString('last_data_purchase');
      setState(() {
        networks       = netList;
        plansByNetwork = plansMap;
        isLoading      = false;
        if (recentRaw != null) {
          _recentNumbers = List<String>.from(jsonDecode(recentRaw) as List);
        }
        if (lastPurchRaw != null) {
          _lastPurchase = Map<String, dynamic>.from(jsonDecode(lastPurchRaw) as Map);
        }
      });
    } catch (_) {}
  }

  /// Save a number to recent list (max 5, deduped, most recent first)
  Future<void> _saveRecentNumber(String phone) async {
    final updated = [phone, ..._recentNumbers.where((n) => n != phone)].take(5).toList();
    setState(() => _recentNumbers = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recent_data_numbers', jsonEncode(updated));
  }

  /// Save last purchase for quick-repeat banner
  Future<void> _saveLastPurchase(Map<String, dynamic> plan, String phone, String networkKey) async {
    final data = {'plan_size': plan['plan_size'], 'plan_Volume': plan['plan_Volume'], 'plan_amount': plan['plan_amount'], 'plan_type': plan['plan_type'], 'plan_id': plan['id'].toString(), 'phone': phone, 'network': networkKey};
    setState(() => _lastPurchase = data);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_data_purchase', jsonEncode(data));
  }

  Future<void> fetchUserBalanceAndPlans() async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        if (mounted) { showError('Session expired. Please login again.'); Navigator.pushReplacementNamed(context, '/login'); }
        return;
      }
      final headers = {'Authorization': 'Token $token', 'Content-Type': 'application/json'};
      final results = await Future.wait([
        safeApiCall(Uri.parse('https://amsubnig.com/api/user/'), headers),
        safeApiCall(Uri.parse('https://amsubnig.com/api/network-plans/'), headers),
      ]);

      double? newBalance;
      List<Map<String, dynamic>> newNetworks = [];
      Map<String, List<dynamic>> newPlans = {};

      if (results[0].statusCode == 200) {
        final data = jsonDecode(results[0].body);
        newBalance = double.tryParse(data['user']?['Account_Balance']?.toString() ?? '0') ?? 0.0;
      }

      if (results[1].statusCode == 200) {
        final data = jsonDecode(results[1].body) as Map<String, dynamic>;
        const keys = ['MTN', 'GLO', 'AIRTEL', '9MOBILE', 'SMILE'];
        for (final key in keys) {
          if (!data.containsKey(key)) continue;
          final netInfo = data[key]['network_info'] as Map? ?? {};
          newNetworks.add({'key': key, 'name': key == '9MOBILE' ? '9mobile' : key, 'image': 'assets/images/${key.toLowerCase()}.png', 'id': netInfo['id']?.toString() ?? _getNetworkIdFromKey(key)});
          final planList = data[key]['data_plans'] as List?;
          if (planList != null) newPlans[key] = planList;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('buy_data_cache', jsonEncode({'balance': newBalance ?? 0.0, 'networks': newNetworks, 'plans': newPlans}));
      for (var net in newNetworks) { net['color'] = _getNetworkColor(net['key'] as String); }

      if (!mounted) return;
      final bp = Provider.of<UserBalanceProvider>(context, listen: false);
      if (newBalance != null) bp.updateBalance(newBalance, bp.bonusBalance);
      setState(() {
        if (newNetworks.isNotEmpty) networks = newNetworks;
        if (newPlans.isNotEmpty) plansByNetwork = newPlans;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('BuyData fetch error: $e');
      if (mounted && networks.isEmpty) { showError('Failed to load plans.'); setState(() => isLoading = false); }
    }
  }

  // ── Contacts ──────────────────────────────────────────────────────────────
  Future<void> pickFromContacts() async {
    try {
      if (await Permission.contacts.request().isGranted) {
        final contact = await FlutterContacts.openExternalPick();
        if (contact != null && contact.phones.isNotEmpty) {
          final raw     = contact.phones.first.number ?? '';
          final cleaned = raw.replaceAll(RegExp(r'[\s\-\(\)]'), '');
          final norm    = normalizePhoneNumber(cleaned);
          setState(() => phoneController.text = norm ?? cleaned);
          norm != null ? showSuccess('Contact selected') : showError('Could not format number. Edit manually.');
        }
      } else {
        showDialog(context: context, builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Contacts Permission', style: TextStyle(fontSize: 15)),
          content: const Text('Please enable contacts permission in settings.', style: TextStyle(fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () { Navigator.pop(context); openAppSettings(); }, child: const Text('Open Settings')),
          ],
        ));
      }
    } catch (_) { showError('Could not pick contact'); }
  }

  // ── Network helpers ───────────────────────────────────────────────────────
  Color _getNetworkColor(String network) {
    switch (network.toUpperCase()) {
      case 'MTN':     return const Color(0xFFFFCC00);
      case 'GLO':     return const Color(0xFF00B140);
      case 'AIRTEL':  return const Color(0xFFE40046);
      case '9MOBILE': return const Color(0xFF00A859);
      case 'SMILE':   return const Color(0xFF00AEEF);
      default:        return primaryBlue;
    }
  }

  int _getNetworkIdFromKey(String key) => {'MTN': 1, 'GLO': 2, 'AIRTEL': 3, '9MOBILE': 4, 'SMILE': 5}[key] ?? 1;

  Map<String, dynamic>? findSelectedPlan(String? planId) {
    if (planId == null || selectedNetworkKey == null) return null;
    for (final plan in plansByNetwork[selectedNetworkKey] ?? []) {
      if (plan is Map && plan['id'].toString() == planId) return Map<String, dynamic>.from(plan);
    }
    return null;
  }

  List<dynamic> getFilteredPlans() {
    if (selectedNetworkKey == null) return [];
    final all = plansByNetwork[selectedNetworkKey] ?? [];
    var filtered = (_selectedPlanType == 'All' || _selectedPlanType == null)
        ? all
        : all.where((plan) {
      final type = (plan as Map)['plan_type']?.toString().toUpperCase() ?? '';
      return type == _selectedPlanType!.toUpperCase();
    }).toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((plan) {
        final m = plan as Map;
        final size   = '${m['plan_size']}${m['plan_Volume'] ?? 'gb'}'.toLowerCase();
        final amount = m['plan_amount']?.toString() ?? '';
        final type   = m['plan_type']?.toString().toLowerCase() ?? '';
        return size.contains(q) || amount.contains(q) || type.contains(q);
      }).toList();
    }
    return filtered;
  }

  // ── Submit: confirm dialog → PIN → API ────────────────────────────────────
  Future<void> submitPurchase() async {
    final bp             = Provider.of<UserBalanceProvider>(context, listen: false);
    final currentBalance = bp.balance;
    final selectedPlan   = findSelectedPlan(selectedPlanId);
    if (selectedPlan == null) { showError('Please select a data plan'); return; }
    final normalizedPhone = normalizePhoneNumber(phoneController.text.trim());
    if (normalizedPhone == null) { showError('Please enter a valid Nigerian number'); return; }
    final planAmount = double.tryParse(selectedPlan['plan_amount']?.toString() ?? '0') ?? 0;
    if (currentBalance < planAmount) { showError('Insufficient balance. Please fund your wallet.'); return; }

    // ── Step 1: Confirmation dialog ───────────────────────────────────────
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: lightPurple, shape: BoxShape.circle), child: const Icon(Icons.wifi, color: primaryPurple, size: 26)),
            const SizedBox(height: 12),
            const Text('Confirm Data Purchase', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _confirmRow('Network', selectedNetworkKey ?? ''),
                _confirmRow('Plan',    '${selectedPlan['plan_size']}${selectedPlan['plan_Volume'] ?? 'GB'}'),
                _confirmRow('Type',    selectedPlan['plan_type'] ?? 'Standard'),
                _confirmRow('Phone',   normalizedPhone),
                _confirmRow('Amount',  '₦$planAmount'),
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
      if (token == null) { showError('Session expired.'); if (mounted) Navigator.pushReplacementNamed(context, '/login'); return; }

      final networkId = selectedPlan['network_id'] ?? selectedPlan['network'] ?? _getNetworkIdFromKey(selectedNetworkKey!);
      final response  = await http.post(
        Uri.parse('https://amsubnig.com/api/data/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'plan': selectedPlan['id'], 'network': networkId, 'mobile_number': normalizedPhone, 'Ported_number': bypassValidation}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        bp.updateBalance(currentBalance - planAmount, bp.bonusBalance);
        showSuccess('✅ Purchase Successful!');
        await _saveRecentNumber(normalizedPhone);
        await _saveLastPurchase(selectedPlan, normalizedPhone, selectedNetworkKey!);
        if (mounted) _showReceiptDialog(result, selectedPlan, normalizedPhone);
        phoneController.clear();
        setState(() => selectedPlanId = null);
      } else if (response.statusCode == 400) {
        showError('❌ ${_extractErrorMessage(jsonDecode(response.body))}');
      } else if (response.statusCode == 403) {
        showError('❌ Insufficient balance or unauthorized');
      } else {
        showError('❌ Purchase failed (${response.statusCode})');
      }
    } catch (_) { showError('❌ Network error. Please try again.'); }
    finally { if (mounted) setState(() => isSubmitting = false); }
  }

  Widget _confirmRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 11, color: lightText))),
      const SizedBox(width: 6),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText), overflow: TextOverflow.ellipsis)),
    ]),
  );

  void _showReceiptDialog(Map<String, dynamic> receipt, Map<String, dynamic> plan, String phone) {
    showDialog(context: context, builder: (_) => _ReceiptDialog(
      receipt: receipt, plan: plan, phone: phone,
      networkKey: selectedNetworkKey ?? '',
      onBuyAgain: () => setState(() { selectedPlanId = null; phoneController.clear(); }),
    ));
  }

  String _extractErrorMessage(Map<String, dynamic> r) {
    if (r.containsKey('error'))         return r['error'].toString();
    if (r.containsKey('mobile_number')) return 'Invalid phone number';
    if (r.containsKey('plan'))          return 'Invalid plan selected';
    if (r.containsKey('network'))       return 'Invalid network';
    if (r.containsKey('detail'))        return r['detail'].toString();
    if (r.containsKey('message'))       return r['message'].toString();
    return 'Unknown error occurred';
  }

  void showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error, color: Colors.white, size: 18), const SizedBox(width: 10), Expanded(child: Text(msg, style: const TextStyle(fontSize: 13)))]),
      backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  void showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 18), const SizedBox(width: 10), Expanded(child: Text(msg, style: const TextStyle(fontSize: 13)))]),
      backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bp              = Provider.of<UserBalanceProvider>(context);
    final walletBalance   = bp.balance;
    final filteredPlans   = getFilteredPlans();
    final selectedPlan    = findSelectedPlan(selectedPlanId);
    final normalizedPhone = normalizePhoneNumber(phoneController.text.trim());
    final currentBalance  = bp.balance; // used for affordability dim

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        title: const Text('Buy Data', style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        toolbarHeight: 48,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: primaryPurple, size: 20), onPressed: fetchUserBalanceAndPlans)],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await fetchUserBalanceAndPlans(); await bp.refresh(); },
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
                  // ── Quick-repeat last purchase ────────────────
                  if (_lastPurchase != null) ...[
                    _buildLastPurchaseBanner(),
                    const SizedBox(height: 16),
                  ],

                  // ── 1. Network ────────────────────────────────────
                  _sectionLabel('1. Select Network', Icons.sim_card),
                  const SizedBox(height: 10),
                  _buildNetworkRow(),
                  const SizedBox(height: 20),

                  // ── 2. Phone ──────────────────────────────────────
                  _sectionLabel('2. Phone Number', Icons.phone),
                  const SizedBox(height: 8),
                  _buildPhoneInput(),
                  if (phoneController.text.isNotEmpty && normalizedPhone != null && normalizedPhone != phoneController.text.trim())
                    Padding(
                      padding: const EdgeInsets.only(top: 5, left: 10),
                      child: Row(children: [const Icon(Icons.info_outline, size: 12, color: primaryBlue), const SizedBox(width: 5), Expanded(child: Text('Sending to: $normalizedPhone', style: const TextStyle(fontSize: 11, color: primaryBlue, fontStyle: FontStyle.italic)))]),
                    ),
                  // Recent numbers
                  if (_recentNumbers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildRecentNumbers(),
                  ],

                  // ── 3. Plan type ──────────────────────────────────
                  if (selectedNetworkKey != null) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('3. Plan Type', Icons.filter_list),
                    const SizedBox(height: 8),
                    _buildPlanTypeFilter(),
                  ],

                  // ── 4. Plans ──────────────────────────────────────
                  if (selectedNetworkKey != null && isPlanTypeSelected) ...[
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      _sectionLabel('4. Select Plan', Icons.data_usage),
                      if (_planCount > 0)
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(10)), child: Text('${filteredPlans.length} plans', style: const TextStyle(fontSize: 10, color: primaryPurple, fontWeight: FontWeight.w600))),
                    ]),
                    const SizedBox(height: 8),
                    // Search bar
                    _buildPlanSearch(),
                    const SizedBox(height: 8),
                    if (selectedPlan != null) ...[_buildSelectedPlanCard(selectedPlan), const SizedBox(height: 8)],
                    filteredPlans.isEmpty ? _buildEmptyState() : _buildPlanList(filteredPlans, currentBalance),
                  ],

                  const SizedBox(height: 120),
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
      // ── Floating BUY button ───────────────────────────────────────────────
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: canBuy && selectedPlan != null
          ? Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isSubmitting ? null : submitPurchase,
            style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, disabledBackgroundColor: lightText, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 8, shadowColor: primaryPurple.withOpacity(0.45)),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: isSubmitting
                  ? const Row(key: ValueKey('l'), mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)), SizedBox(width: 12), Text('Processing…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))])
                  : Row(key: const ValueKey('i'), mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.shopping_cart_rounded, size: 20), const SizedBox(width: 8), Text('BUY NOW  •  ₦${selectedPlan['plan_amount']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]),
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

  /// Horizontal scrollable network row — same style as Recharge Card screen.
  /// Each card shows logo image, name, and live plan-count badge.
  /// Wrapped grid of network cards — visible all at once, no swiping needed.
  Widget _buildNetworkRow() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.95,
      ),
      itemCount: networks.length,
      itemBuilder: (_, i) {
        final network    = networks[i];
        final key        = network['key']?.toString() ?? '';
        final isSelected = selectedNetworkKey == key;
        final color      = (network['color'] as Color?) ?? primaryBlue;
        final imagePath  = network['image']?.toString() ?? '';
        final count      = plansByNetwork[key]?.length ?? 0;

        return GestureDetector(
          onTap: () => setState(() {
            selectedNetworkKey = key;
            selectedPlanId     = null;
            _selectedPlanType  = 'All';
          }),
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
              SizedBox(
                height: 30,
                child: imagePath.isNotEmpty
                    ? Image.asset(imagePath, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.sim_card, size: 22, color: color))
                    : Icon(Icons.sim_card, size: 22, color: color),
              ),
              const SizedBox(height: 3),
              Text(network['name']?.toString() ?? key, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isSelected ? color : darkText), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.15) : lightPurple, borderRadius: BorderRadius.circular(6)),
                child: Text('$count plans', style: TextStyle(fontSize: 8, color: isSelected ? color : primaryPurple, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildPhoneInput() {
    final isValid = phoneController.text.isEmpty || isPhoneValid;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: !isValid ? Colors.red.shade300 : Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Expanded(
          child: TextFormField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: 14, color: darkText),
            decoration: InputDecoration(
              hintText: 'Enter 11-digit Nigerian number',
              hintStyle: const TextStyle(color: lightText, fontSize: 13),
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.phone, color: primaryPurple, size: 18),
              suffixIcon: phoneController.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 16, color: lightText), onPressed: () => setState(() => phoneController.clear()))
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              errorText: phoneController.text.isNotEmpty && !isValid ? 'Enter valid number' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Container(height: 46, width: 1, color: Colors.grey[200]),
        InkWell(
          onTap: pickFromContacts,
          borderRadius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(Icons.contacts_rounded, color: primaryPurple, size: 20)),
        ),
      ]),
    );
  }

  Widget _buildPlanTypeFilter() {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: planTypes.map((type) {
        final isSelected = _selectedPlanType == type;
        return FilterChip(
          label: Text(type, style: TextStyle(fontSize: 11, color: isSelected ? primaryPurple : darkText, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          selected: isSelected,
          onSelected: (_) => setState(() { _selectedPlanType = type; selectedPlanId = null; }),
          backgroundColor: Colors.white,
          selectedColor: lightPurple,
          checkmarkColor: primaryPurple,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          shape: StadiumBorder(side: BorderSide(color: isSelected ? primaryPurple : Colors.grey[300]!, width: isSelected ? 1.5 : 1)),
        );
      }).toList(),
    );
  }

  Widget _buildPlanList(List<dynamic> plans, double balance) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: plans.length,
      itemBuilder: (_, index) {
        final plan       = plans[index] as Map<String, dynamic>;
        final isSelected = selectedPlanId == plan['id'].toString();
        final planAmt    = double.tryParse(plan['plan_amount']?.toString() ?? '0') ?? 0;
        final canAfford  = balance >= planAmt;
        return Opacity(
          opacity: canAfford ? 1.0 : 0.45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 7),
            decoration: BoxDecoration(
              color: isSelected ? lightPurple : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? primaryPurple : Colors.grey[200]!, width: isSelected ? 2 : 1),
              boxShadow: [BoxShadow(color: isSelected ? primaryPurple.withOpacity(0.08) : Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))],
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: canAfford
                  ? Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isSelected ? primaryPurple : lightText, size: 18)
                  : const Icon(Icons.lock_rounded, size: 16, color: lightText),
              title: Text('${plan['plan_size']}${plan['plan_Volume'] ?? 'GB'}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isSelected ? primaryPurple : darkText)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${plan['plan_type'] ?? 'Standard'}  ·  ${plan['month_validate'] ?? '30'} days', style: const TextStyle(color: lightText, fontSize: 11)),
                if (!canAfford) ...[
                  const SizedBox(height: 2),
                  const Text('Insufficient balance', style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.w500)),
                ],
              ]),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: isSelected ? primaryPurple : (canAfford ? lightPurple : Colors.grey[200]!), borderRadius: BorderRadius.circular(18)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('₦${plan['plan_amount']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : (canAfford ? primaryPurple : lightText))),
                  if (isSelected) const Text('✓', style: TextStyle(fontSize: 10, color: Colors.white70)),
                ]),
              ),
              onTap: canAfford ? () => setState(() => selectedPlanId = plan['id'].toString()) : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(14), border: Border.all(color: primaryPurple.withOpacity(0.15))),
      child: Column(children: [
        Icon(Icons.data_exploration, size: 46, color: primaryPurple.withOpacity(0.4)),
        const SizedBox(height: 12),
        const Text('No plans available', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: darkText)),
        const SizedBox(height: 6),
        const Text('Try selecting a different plan type', style: TextStyle(fontSize: 12, color: lightText)),
      ]),
    );
  }

  Widget _buildSelectedPlanCard(Map<String, dynamic> plan) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lightPurple, Color(0xFFEEF6FF)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryPurple.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: primaryPurple.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: primaryPurple, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.check_rounded, color: Colors.white, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Selected Plan', style: TextStyle(fontSize: 10, color: lightText)),
          const SizedBox(height: 2),
          Text('${plan['plan_size']}${plan['plan_Volume'] ?? 'GB'}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: darkText)),
          Text('₦${plan['plan_amount']}  ·  ${plan['plan_type'] ?? 'Standard'}', style: const TextStyle(fontSize: 11, color: lightText)),
        ])),
        IconButton(icon: const Icon(Icons.close_rounded, color: lightText, size: 18), onPressed: () => setState(() => selectedPlanId = null), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      ]),
    );
  }

  // ── Last purchase quick-repeat banner ────────────────────────────────────

  Widget _buildLastPurchaseBanner() {
    final lp = _lastPurchase!;
    final size    = '${lp['plan_size']}${lp['plan_Volume'] ?? 'GB'}';
    final amount  = '₦${lp['plan_amount']}';
    final phone   = lp['phone'] as String? ?? '';
    final network = lp['network'] as String? ?? '';
    return GestureDetector(
      onTap: () {
        // Pre-fill everything for a one-tap repeat
        final netKey = lp['network'] as String?;
        final planId = lp['plan_id'] as String?;
        setState(() {
          selectedNetworkKey = netKey;
          selectedPlanId     = planId;
          _selectedPlanType  = 'All';
          _searchQuery       = '';
          _searchController.clear();
          phoneController.text = phone;
        });
      },
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
            Text('$network  $size  $amount', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: darkText)),
            Text(phone, style: const TextStyle(fontSize: 11, color: lightText)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: primaryPurple, borderRadius: BorderRadius.circular(20)),
            child: const Text('Tap to fill', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  // ── Recent numbers ────────────────────────────────────────────────────────

  Widget _buildRecentNumbers() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Recent', style: TextStyle(fontSize: 10, color: lightText, letterSpacing: 0.3)),
      const SizedBox(height: 5),
      Wrap(spacing: 7, runSpacing: 6, children: _recentNumbers.map((num) {
        return GestureDetector(
          onTap: () => setState(() => phoneController.text = num),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: phoneController.text == num ? primaryPurple : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: phoneController.text == num ? primaryPurple : Colors.grey[300]!),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.history_rounded, size: 11, color: phoneController.text == num ? Colors.white70 : lightText),
              const SizedBox(width: 4),
              Text(num, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: phoneController.text == num ? Colors.white : darkText)),
            ]),
          ),
        );
      }).toList()),
    ]);
  }

  // ── Plan search ───────────────────────────────────────────────────────────

  Widget _buildPlanSearch() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Row(children: [
        const Padding(padding: EdgeInsets.only(left: 12), child: Icon(Icons.search_rounded, color: primaryPurple, size: 18)),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(
          controller: _searchController,
          style: const TextStyle(color: darkText, fontSize: 13),
          decoration: const InputDecoration(hintText: 'Search by size, amount or type…', hintStyle: TextStyle(color: lightText, fontSize: 12), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 11)),
          onChanged: (v) => setState(() { _searchQuery = v.trim(); selectedPlanId = null; }),
        )),
        if (_searchQuery.isNotEmpty)
          GestureDetector(onTap: () => setState(() { _searchQuery = ''; _searchController.clear(); selectedPlanId = null; }), child: const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.clear_rounded, size: 16, color: lightText))),
      ]),
    );
  }

  Widget _buildSkeletonLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: [
        GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.95), itemCount: 4, itemBuilder: (_, __) => Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 20),
        Container(height: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
        const SizedBox(height: 20),
        Wrap(spacing: 7, runSpacing: 7, children: List.generate(5, (_) => Container(width: 80, height: 30, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30))))),
        const SizedBox(height: 20),
        ...List.generate(5, (_) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(height: 66, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _ReceiptDialog extends StatefulWidget {
  final Map<String, dynamic> receipt;
  final Map<String, dynamic> plan;
  final String phone;
  final String networkKey;
  final VoidCallback onBuyAgain;

  const _ReceiptDialog({required this.receipt, required this.plan, required this.phone, required this.networkKey, required this.onBuyAgain});

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
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
      if (boundary == null) throw Exception('Could not find render boundary');
      final image    = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode image');
      final pngBytes = byteData.buffer.asUint8List();
      final tempDir  = await getTemporaryDirectory();
      final file     = File('${tempDir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.png');
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
    final plan      = widget.plan;
    final receipt   = widget.receipt;
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
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [primaryPurple, Color(0xFF9B7DFF)]), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.receipt_long, color: Colors.white, size: 19)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Purchase Receipt', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        // ── Receipt body — no scroll, fits screen ────────────────────
        RepaintBoundary(
          key: _captureKey,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // ── Brand header ────────────────────────────────────────
              RichText(text: TextSpan(children: [
                const TextSpan(text: 'AMS', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: primaryPurple, letterSpacing: 1)),
                const TextSpan(text: 'UB',  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF3B82F6), letterSpacing: 1)),
                const TextSpan(text: 'NIG', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF10B981), letterSpacing: 1)),
              ])),
              const Text('Grandfather of Data Vendors', style: TextStyle(fontSize: 9, color: lightText, fontStyle: FontStyle.italic)),
              const SizedBox(height: 10),
              // ── Status + network logo side by side ──────────────────
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: sc.withAlpha(20), shape: BoxShape.circle), child: Icon(si, color: sc, size: 24)),
                const SizedBox(width: 14),
                SizedBox(height: 32, child: Image.asset('assets/images/${widget.networkKey.toLowerCase()}.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
              ]),
              const SizedBox(height: 4),
              Text(rawStatus.toUpperCase(), style: TextStyle(color: sc, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
              // ── API response ────────────────────────────────────────
              if (receipt.containsKey('api_response') && receipt['api_response']?.toString().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: sc.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: sc.withOpacity(0.2))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, size: 12, color: sc),
                    const SizedBox(width: 6),
                    Expanded(child: Text(receipt['api_response'].toString(), style: TextStyle(fontSize: 10, color: sc, fontWeight: FontWeight.w500))),
                  ]),
                ),
              ],
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              // ── 2-column info grid — 3 pairs ────────────────────────
              _infoGrid(
                label1: 'Data Plan',  value1: '${plan['plan_size']}${plan['plan_Volume'] ?? 'GB'} · ₦${plan['plan_amount']}',
                label2: 'Type',       value2: plan['plan_type']?.toString() ?? 'Standard',
              ),
              const SizedBox(height: 8),
              _infoGrid(
                label1: 'Network',  value1: widget.networkKey,
                label2: 'Phone',    value2: widget.phone,
              ),
              const SizedBox(height: 8),
              _infoGrid(
                label1: 'Reference', value1: receipt['ident']?.toString() ?? 'N/A',
                label2: 'Date',      value2: DateTime.now().toString().substring(0, 16),
              ),
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

  Widget _infoGrid({required String label1, required String value1, required String label2, required String value2}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: _infoCell(label1, value1)),
      const SizedBox(width: 8),
      Expanded(child: _infoCell(label2, value2)),
    ]);
  }

  Widget _infoCell(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(9)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 9, color: lightText, letterSpacing: 0.4)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: darkText), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}