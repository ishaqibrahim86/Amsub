import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';
import '../services/auth_service.dart';
import '../services/pin_auth_service.dart';
import '../providers/user_balance_provider.dart';

class DataCouponScreen extends StatefulWidget {
  const DataCouponScreen({super.key});

  @override
  State<DataCouponScreen> createState() => _DataCouponScreenState();
}

class _DataCouponScreenState extends State<DataCouponScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color primaryBlue   = Color(0xFF3B82F6);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  String?  _selectedNetwork;
  int?     _selectedPlanId;
  int      _quantity       = 1;
  double   _estimatedCost  = 0.0;
  bool     _isLoading      = true;
  bool     _isGenerating   = false;
  bool     _isRefreshing   = false;
  String?  _error;
  String?  _successMessage;
  List<Map<String, dynamic>> _generatedPins = [];
  List<Map<String, dynamic>> _history       = [];
  List<Map<String, dynamic>> _couponPlans   = [];

  final _nameController = TextEditingController();

  static const String _cacheBalanceKey   = 'coupon_balance_cache';
  static const String _cachePlansKey     = 'coupon_plans_cache';
  static const String _cacheHistoryKey   = 'coupon_history_cache';
  static const String _cacheTimestampKey = 'coupon_cache_timestamp';
  static const Duration _cacheDuration   = Duration(minutes: 5);

  late AnimationController _animationController;
  late Animation<double>   _fadeAnimation;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);
    WidgetsBinding.instance.addObserver(this);
    _loadCachedData();
    _fetchData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _animationController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _fetchData(isBackground: true);
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  Future<void> _loadCachedData() async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - timestamp >= _cacheDuration.inMilliseconds) return;

      final balData  = prefs.getString(_cacheBalanceKey);
      final plnData  = prefs.getString(_cachePlansKey);
      final hisData  = prefs.getString(_cacheHistoryKey);

      if (!mounted) return;
      setState(() {
        if (balData != null) {
          final bp = Provider.of<UserBalanceProvider>(context, listen: false);
          bp.updateBalance((jsonDecode(balData)['balance'] as num?)?.toDouble() ?? 0.0, bp.bonusBalance);
        }
        if (plnData != null) _couponPlans = List<Map<String, dynamic>>.from(jsonDecode(plnData));
        if (hisData != null) _history     = List<Map<String, dynamic>>.from(jsonDecode(hisData));
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) { debugPrint('Cache load error: $e'); }
  }

  Future<void> _cacheData(double balance) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheBalanceKey, jsonEncode({'balance': balance}));
      await prefs.setString(_cachePlansKey,   jsonEncode(_couponPlans));
      await prefs.setString(_cacheHistoryKey, jsonEncode(_history));
      await prefs.setInt(_cacheTimestampKey,  DateTime.now().millisecondsSinceEpoch);
    } catch (e) { debugPrint('Cache save error: $e'); }
  }

  // ── API ───────────────────────────────────────────────────────────────────

  Future<http.Response> _safeCall(Future<http.Response> Function() fn) async {
    for (int i = 0; i < 3; i++) {
      try { return await fn().timeout(const Duration(seconds: 15)); }
      catch (e) { if (i == 2) rethrow; await Future.delayed(Duration(seconds: i + 1)); }
    }
    throw Exception('Max retries exceeded');
  }

  Future<void> _fetchData({bool isBackground = false}) async {
    if (isBackground) { setState(() => _isRefreshing = true); }
    else              { setState(() => _isLoading    = true); }

    try {
      final token = await AuthService.getToken();
      if (token == null) return;
      final headers = {'Authorization': 'Token $token'};

      final results = await Future.wait([
        _safeCall(() => http.get(Uri.parse('https://amsubnig.com/api/user/'),               headers: headers)),
        _safeCall(() => http.get(Uri.parse('https://amsubnig.com/api/datarechargepin/'),    headers: headers)),
      ]);

      double newBalance = 0.0;

      if (results[0].statusCode == 200) {
        final data   = jsonDecode(results[0].body);
        final user   = data['user'] ?? {};
        newBalance   = double.tryParse(user['Account_Balance']?.toString() ?? '0') ?? 0.0;
        final bonus  = double.tryParse(user['bonus_balance']?.toString()   ?? '0') ?? 0.0;

        final raw    = data['datacoupon_plan'] as List<dynamic>? ?? [];
        final plans  = raw.map((p) => {
          'id':           p['id'],
          'dataplan_id':  p['dataplan_id'],
          'network':      (p['network'] as String?)?.toUpperCase() ?? 'Unknown',
          'name':         p['plan'] ?? 'Unknown Plan',
          'amount':       double.tryParse(p['plan_amount']?.toString() ?? '0') ?? 0.0,
          'month_validate': p['month_validate'],
          'plan_type':    p['plan_type'],
        }).toList();

        if (!mounted) return;
        final bp = Provider.of<UserBalanceProvider>(context, listen: false);
        bp.updateBalance(newBalance, bonus);
        setState(() { _couponPlans = plans; });
        _updateCost();
      }

      if (results[1].statusCode == 200) {
        final data   = jsonDecode(results[1].body);
        final list   = data is List ? data : (data['results'] ?? []) as List;
        setState(() {
          _history = list.map((item) {
            final m = item as Map<String, dynamic>;
            return {
              'network':  m['net_name']     ?? m['network'] ?? 'Unknown',
              'plan':     m['plan_network'] ?? 'Unknown Plan',
              'quantity': m['quantity']     ?? 0,
              'amount':   m['amount']?.toString() ?? '0',
              'pins':     m['data_pins']    ?? '',
              'status':   m['Status']       ?? 'Unknown',
              'date':     m['create_date']  ?? '',
            };
          }).toList();
        });
      }

      await _cacheData(newBalance);
    } catch (e) {
      if (!isBackground) setState(() => _error = 'Network error: $e');
    } finally {
      setState(() { _isLoading = false; _isRefreshing = false; });
      _animationController.forward();
    }
  }

  void _updateCost() {
    if (_selectedPlanId == null || _selectedNetwork == null) return;
    final plan = _couponPlans.firstWhere((p) => p['id'] == _selectedPlanId && p['network'] == _selectedNetwork, orElse: () => {'amount': 0.0});
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _estimatedCost = (plan['amount'] as double) * _quantity);
    });
  }

  // ── Generate: confirm → PIN → API ────────────────────────────────────────

  Future<void> _generateCoupons() async {
    if (_selectedNetwork == null || _selectedPlanId == null) { setState(() => _error = 'Select network and plan'); return; }
    final name = _nameController.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter name on card'); return; }

    final bp             = Provider.of<UserBalanceProvider>(context, listen: false);
    final currentBalance = bp.balance;
    if (_estimatedCost > currentBalance) { setState(() => _error = 'Insufficient balance (₦${currentBalance.toStringAsFixed(2)})'); return; }

    // ── Step 1: Confirmation dialog ───────────────────────────────────────
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: lightPurple, shape: BoxShape.circle), child: const Icon(Icons.sim_card, color: primaryPurple, size: 26)),
            const SizedBox(height: 12),
            const Text('Confirm Coupon Purchase', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _confirmRow('Network',  _selectedNetwork!),
                _confirmRow('Quantity', '$_quantity ${_quantity == 1 ? 'coupon' : 'coupons'}'),
                _confirmRow('Name',     name),
                _confirmRow('Cost',     '₦${_estimatedCost.toStringAsFixed(2)}'),
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

    setState(() { _isGenerating = true; _error = null; _successMessage = null; _generatedPins = []; });

    try {
      final token = await AuthService.getToken();
      if (token == null) { setState(() { _error = 'Session expired'; _isGenerating = false; }); return; }

      final response = await _safeCall(() => http.post(
        Uri.parse('https://amsubnig.com/api/datarechargepin/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'network': _selectedNetwork, 'data_plan': _selectedPlanId, 'quantity': _quantity, 'name_on_card': name}),
      ));

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> pinsList = [];
        final pinsData = data['data_pins'];
        if (pinsData is List) {
          for (final pinItem in pinsData) {
            if (pinItem is Map && pinItem.containsKey('fields')) {
              final f = pinItem['fields'] as Map;
              String exp = f['expire_date']?.toString() ?? 'N/A';
              if (exp.contains('T')) exp = exp.split('T')[0];
              pinsList.add({
                'network':        f['network'] ?? _selectedNetwork ?? 'Unknown',
                'pin':            f['pin']?.toString() ?? 'N/A',
                'serial':         f['serial']?.toString() ?? 'N/A',
                'load_code':      f['load_code']?.toString() ?? 'N/A',
                'expire_date':    exp,
                'name_on_card':   data['name_on_card'] ?? name,
                'date_generated': DateTime.now().toString().split('.')[0],
              });
            }
          }
        }
        setState(() { _successMessage = '${pinsList.length} coupon${pinsList.length > 1 ? 's' : ''} generated!'; _generatedPins = pinsList; _isGenerating = false; });
        _nameController.clear();
        _fetchData(isBackground: true);
        if (mounted) Provider.of<UserBalanceProvider>(context, listen: false).refresh();
        _showGeneratedPinsDialog();
      } else {
        final resp = jsonDecode(response.body);
        setState(() { _error = resp['error'] ?? 'Failed (${response.statusCode})'; _isGenerating = false; });
      }
    } catch (e) { setState(() { _error = 'Network error: $e'; _isGenerating = false; }); }
  }

  Widget _confirmRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 11, color: lightText))),
      const SizedBox(width: 6),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText), overflow: TextOverflow.ellipsis)),
    ]),
  );

  // ── PDF / Print ───────────────────────────────────────────────────────────

  Future<void> _generatePDF() async {
    try {
      final pdf = pw.Document();
      final now = DateTime.now();
      final dt  = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')} ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(15),
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        build: (_) {
          final widgets = <pw.Widget>[
            pw.Text('Data Coupons — $dt', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.purple)),
            pw.SizedBox(height: 10),
          ];
          for (var i = 0; i < _generatedPins.length; i += 3) {
            final row = <pw.Widget>[];
            for (var j = 0; j < 3; j++) {
              row.add(i + j < _generatedPins.length ? _pdfCard(_generatedPins[i + j]) : pw.Expanded(child: pw.Container()));
            }
            widgets.add(pw.Row(children: row));
          }
          return widgets;
        },
      ));

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/data_coupons_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdf.save());
      if (mounted) { await OpenFile.open(file.path); _snack('PDF generated!'); }
    } catch (e) { if (mounted) _snack('Error generating PDF', isError: true); }
  }

  Future<void> _printPDF() async {
    try {
      final pdf = pw.Document();
      final now = DateTime.now();
      final dt  = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(15),
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        build: (_) {
          final widgets = <pw.Widget>[
            pw.Text('Data Coupons — $dt', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.purple)),
            pw.SizedBox(height: 10),
          ];
          for (var i = 0; i < _generatedPins.length; i += 3) {
            final row = <pw.Widget>[];
            for (var j = 0; j < 3; j++) {
              row.add(i + j < _generatedPins.length ? _pdfCard(_generatedPins[i + j]) : pw.Expanded(child: pw.Container()));
            }
            widgets.add(pw.Row(children: row));
          }
          return widgets;
        },
      ));
      await Printing.layoutPdf(onLayout: (_) async => pdf.save());
    } catch (e) { if (mounted) _snack('Error printing', isError: true); }
  }

  pw.Widget _pdfCard(Map<String, dynamic> pin) {
    final nm = pin['name_on_card']?.toString() ?? '';
    return pw.Expanded(child: pw.Container(
      height: 100,
      margin: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.purple, width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('DATA CARD', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.purple)),
          pw.Text(nm.length > 8 ? nm.substring(0, 8) : nm, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ]),
        pw.Text(pin['pin'], style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: pw.Font.courierBold()), textAlign: pw.TextAlign.center),
        pw.Row(children: [
          pw.Expanded(child: pw.Text('S/N: ${pin['serial'].toString().length > 10 ? pin['serial'].toString().substring(0,10) : pin['serial']}', style: pw.TextStyle(fontSize: 6))),
          pw.Expanded(child: pw.Text('Load: ${pin['load_code']}', style: pw.TextStyle(fontSize: 6, color: PdfColors.green), textAlign: pw.TextAlign.right)),
        ]),
        pw.Text('Exp: ${pin['expire_date']}', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey)),
        pw.Center(child: pw.Text('AMSUBNIG', style: pw.TextStyle(fontSize: 5, color: PdfColors.purple))),
      ]),
    ));
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : primaryPurple,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Generated pins dialog ─────────────────────────────────────────────────

  void _showGeneratedPinsDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              decoration: const BoxDecoration(gradient: LinearGradient(colors: [primaryPurple, primaryBlue], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              child: Row(children: [
                const Icon(Icons.receipt_long, color: Colors.white, size: 19),
                const SizedBox(width: 10),
                const Expanded(child: Text('Generated Data Coupons', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
                IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            // List
            Expanded(
              child: _generatedPins.isEmpty
                  ? Center(child: Text('No pins generated', style: TextStyle(color: lightText, fontSize: 13)))
                  : ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: _generatedPins.length,
                itemBuilder: (_, i) => _buildPinCard(_generatedPins[i], i),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(top: BorderSide(color: Colors.grey.shade200)), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20))),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: TextStyle(color: lightText, fontSize: 12))),
                if (_generatedPins.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  TextButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 16, color: primaryPurple),
                    label: const Text('PDF', style: TextStyle(color: primaryPurple, fontSize: 12)),
                    onPressed: () { Navigator.pop(context); _generatePDF(); },
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.print, color: Colors.white, size: 16),
                    label: const Text('Print', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                    onPressed: () { Navigator.pop(context); _printPDF(); },
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildPinCard(Map<String, dynamic> pin, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: primaryPurple.withOpacity(0.2)), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Card header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryPurple.withOpacity(0.08), primaryBlue.withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Container(width: 22, height: 22, decoration: const BoxDecoration(color: primaryPurple, shape: BoxShape.circle), child: Center(child: Text('${index+1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)))),
              const SizedBox(width: 8),
              const Text('DATA CARD', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryPurple)),
            ]),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(10)), child: Text(pin['name_on_card'] ?? 'N/A', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryPurple))),
          ]),
        ),
        // PIN row
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(10), border: Border.all(color: primaryPurple.withOpacity(0.25))),
            child: Row(children: [
              const Text('PIN:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: darkText)),
              const SizedBox(width: 8),
              Expanded(child: SelectableText(pin['pin'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryPurple, letterSpacing: 1.5), textAlign: TextAlign.right)),
              GestureDetector(onTap: () { Clipboard.setData(ClipboardData(text: pin['pin'])); _snack('PIN copied!'); }, child: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.copy, color: primaryPurple, size: 17))),
            ]),
          ),
        ),
        // Details grid
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: GridView.count(
            crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3.2, crossAxisSpacing: 6, mainAxisSpacing: 6,
            children: [
              _detailBox('Serial',    pin['serial']),
              _detailBox('Load Code', pin['load_code'], highlight: true),
              _detailBox('Expires',   pin['expire_date']),
              _detailBox('Generated', pin['date_generated']),
            ],
          ),
        ),
        // Dial hint
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(7)), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.info_outline, size: 12, color: Colors.grey), SizedBox(width: 5), Text('Dial *556# to load  |  Bal: *461*4#', style: TextStyle(fontSize: 9, color: Colors.grey))])),
        ),
        // Footer
        Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: lightPurple, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14))), child: const Center(child: Text('Powered by IISADIG', style: TextStyle(fontSize: 9, color: primaryPurple, fontWeight: FontWeight.w600)))),
      ]),
    );
  }

  Widget _detailBox(String label, String value, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(7)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: lightText, fontSize: 10)),
        const SizedBox(width: 4),
        Expanded(child: Text(value, style: TextStyle(fontWeight: highlight ? FontWeight.bold : FontWeight.normal, color: highlight ? primaryPurple : darkText, fontSize: 10), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bp = Provider.of<UserBalanceProvider>(context);
    final walletBalance = bp.balance;

    if (_isLoading) {
      return Scaffold(backgroundColor: const Color(0xFFF8F7FF), appBar: _buildAppBar(), body: _buildSkeleton());
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        color: primaryPurple,
        onRefresh: () => _fetchData(isBackground: true),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              // ── Wallet card ───────────────────────────────────────────────
              Container(
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
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(18)), child: const Row(children: [Icon(Icons.account_balance_wallet, color: Colors.white, size: 14), SizedBox(width: 5), Text('Available', style: TextStyle(color: Colors.white, fontSize: 11))])),
                ]),
              ),

              const SizedBox(height: 14),

              // ── Form card ─────────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))], border: Border.all(color: Colors.grey[200]!)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Header
                    Row(children: [
                      Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.sim_card, color: primaryPurple, size: 17)),
                      const SizedBox(width: 10),
                      const Text('Generate Data Coupon', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: darkText)),
                    ]),
                    const SizedBox(height: 16),

                    // Network
                    _fieldLabel('Network'),
                    const SizedBox(height: 6),
                    _buildDropdown<String>(
                      value: _selectedNetwork, hint: 'Select Network', icon: Icons.signal_cellular_alt,
                      items: ['MTN','AIRTEL','GLO','9MOBILE/T2'].map((n) => DropdownMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) { setState(() { _selectedNetwork = v; _selectedPlanId = null; _updateCost(); }); },
                    ),
                    const SizedBox(height: 12),

                    // Plan
                    _fieldLabel('Data Plan'),
                    const SizedBox(height: 6),
                    _buildDropdown<int>(
                      value: _selectedPlanId, hint: 'Select Plan', icon: Icons.data_usage,
                      items: _couponPlans.where((p) => p['network'] == _selectedNetwork).map((p) => DropdownMenuItem<int>(value: p['id'] as int, child: Text('${p['name']} — ₦${(p['amount'] as double).toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: (v) { setState(() { _selectedPlanId = v; _updateCost(); }); },
                    ),
                    const SizedBox(height: 12),

                    // Quantity
                    _fieldLabel('Quantity'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
                      child: Row(children: [
                        const Icon(Icons.format_list_numbered, color: lightText, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: DropdownButton<int>(
                          value: _quantity, isExpanded: true, underline: const SizedBox(),
                          style: const TextStyle(color: darkText, fontSize: 13),
                          items: List.generate(39, (i) => i + 1).map((q) => DropdownMenuItem(value: q, child: Text('$q ${q == 1 ? 'coupon' : 'coupons'}'))).toList(),
                          onChanged: (v) { setState(() { _quantity = v!; _updateCost(); }); },
                        )),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // Name on card
                    _fieldLabel('Name on Card'),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
                      child: TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(color: darkText, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Enter name on card',
                          hintStyle: TextStyle(color: lightText, fontSize: 12),
                          border: InputBorder.none,
                          prefixIcon: const Icon(Icons.person_outline, color: primaryPurple, size: 18),
                          contentPadding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onChanged: (_) => _updateCost(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Cost banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [primaryPurple.withOpacity(0.08), primaryBlue.withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: primaryPurple.withOpacity(0.25)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Estimated Cost:', style: TextStyle(fontSize: 13, color: darkText)),
                        Text('₦${_estimatedCost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryPurple)),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // Generate button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isGenerating ? null : _generateCoupons,
                        style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, disabledBackgroundColor: Colors.grey[400], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 3, shadowColor: primaryPurple.withOpacity(0.4)),
                        child: _isGenerating
                            ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)), SizedBox(width: 10), Text('Generating...', style: TextStyle(fontSize: 14))])
                            : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.sim_card, size: 18), SizedBox(width: 8), Text('Generate Coupons', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]),
                      ),
                    ),

                    // Error/success banners
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      _statusBanner(icon: Icons.error_outline, text: _error!, iconColor: Colors.red.shade700, bgColor: Colors.red.shade50, borderColor: Colors.red.shade200, textColor: Colors.red.shade700, onClose: () => setState(() => _error = null)),
                    ],
                    if (_successMessage != null) ...[
                      const SizedBox(height: 10),
                      _statusBanner(icon: Icons.check_circle_outline, text: _successMessage!, iconColor: Colors.green.shade700, bgColor: Colors.green.shade50, borderColor: Colors.green.shade200, textColor: Colors.green.shade700, onClose: () => setState(() => _successMessage = null)),
                    ],
                  ]),
                ),
              ),

              const SizedBox(height: 18),

              // ── History ───────────────────────────────────────────────────
              Row(children: [
                Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.history, color: primaryPurple, size: 14)),
                const SizedBox(width: 8),
                const Text('Recent Orders', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: darkText)),
              ]),

              const SizedBox(height: 10),

              _history.isEmpty
                  ? Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)), child: Column(children: [const Icon(Icons.history_toggle_off, size: 32, color: lightText), const SizedBox(height: 8), Text('No recent coupon orders', style: TextStyle(color: lightText, fontSize: 12))]))
                  : Column(children: _history.take(5).map(_buildHistoryTile).toList()),
            ],
          ),
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Data Coupon', style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16)),
      centerTitle: true,
      backgroundColor: Colors.white,
      foregroundColor: primaryPurple,
      elevation: 0,
      toolbarHeight: 48,
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: primaryPurple, size: 18), onPressed: () => Navigator.pop(context)),
      actions: [
        if (_isRefreshing)
          const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primaryPurple)))
        else
          IconButton(icon: const Icon(Icons.refresh, color: primaryPurple, size: 20), onPressed: () => _fetchData(isBackground: true)),
      ],
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), children: [
        Container(height: 78, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18))),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(children: List.generate(5, (_) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Container(height: 46, color: Colors.white)))),
        ),
      ]),
    );
  }

  // ── Reusable helpers ──────────────────────────────────────────────────────

  Widget _fieldLabel(String label) => Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: darkText));

  Widget _buildDropdown<T>({required T? value, required String hint, required IconData icon, required List<DropdownMenuItem<T>> items, required void Function(T?) onChanged}) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
      child: DropdownButtonFormField<T>(
        value: value,
        hint: Text(hint, style: TextStyle(color: lightText, fontSize: 12)),
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        icon: const Icon(Icons.arrow_drop_down, color: primaryPurple),
        decoration: InputDecoration(border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), prefixIcon: Icon(icon, color: primaryPurple, size: 18)),
      ),
    );
  }

  Widget _statusBanner({required IconData icon, required String text, required Color iconColor, required Color bgColor, required Color borderColor, required Color textColor, VoidCallback? onClose}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 15),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 12))),
        if (onClose != null) GestureDetector(onTap: onClose, child: Icon(Icons.close, color: iconColor, size: 14)),
      ]),
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> order) {
    final status    = order['status'].toString().toLowerCase();
    final isSuccess = status.contains('success') || status.contains('completed');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.sim_card, color: primaryPurple, size: 16)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${order['network']} · ${order['plan']} (${order['quantity']})', style: const TextStyle(fontWeight: FontWeight.w600, color: darkText, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text('₦${order['amount']}  ·  ${order['date']}', style: TextStyle(fontSize: 10, color: lightText)),
          const SizedBox(height: 5),
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: isSuccess ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(10)), child: Text(order['status'], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isSuccess ? Colors.green.shade700 : Colors.orange.shade700))),
        ])),
        if (order['pins'].isNotEmpty)
          GestureDetector(onTap: () { Clipboard.setData(ClipboardData(text: order['pins'])); _snack('Pins copied!'); }, child: const Padding(padding: EdgeInsets.only(left: 8, top: 2), child: Icon(Icons.copy, color: primaryPurple, size: 16))),
      ]),
    );
  }
}