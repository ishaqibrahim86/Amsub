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
import '../services/auth_service.dart';
import '../services/pin_auth_service.dart';
import '../providers/user_balance_provider.dart';

class RechargeCardScreen extends StatefulWidget {
  const RechargeCardScreen({super.key});

  @override
  State<RechargeCardScreen> createState() => _RechargeCardScreenState();
}

class _RechargeCardScreenState extends State<RechargeCardScreen> {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color primaryBlue   = Color(0xFF3B82F6);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  // Network definitions (id matches backend Network model)
  static const List<Map<String, dynamic>> _networks = [
    {'id': 1, 'name': 'MTN',     'image': 'assets/images/mtn.png',     'color': Color(0xFFFFCC00)},
    {'id': 2, 'name': 'GLO',     'image': 'assets/images/glo.png',     'color': Color(0xFF00B140)},
    {'id': 3, 'name': 'AIRTEL',  'image': 'assets/images/airtel.png',  'color': Color(0xFFE40046)},
    {'id': 4, 'name': '9MOBILE', 'image': 'assets/images/9mobile.png', 'color': Color(0xFF00A859)},
  ];

  Map<String, int>              _available  = {'MTN': 0, 'GLO': 0, 'AIRTEL': 0, '9MOBILE': 0};
  Map<String, List<Map<String,dynamic>>> _plans = {};

  int?    _selectedNetworkId;
  int?    _selectedPlanId;
  int     _quantity      = 1;
  double  _estimatedCost = 0.0;
  String? _infoAlert;

  bool    _isLoading    = true;
  bool    _isGenerating = false;
  bool    _isRefreshing = false;
  String? _error;
  String? _successMessage;

  List<Map<String, dynamic>> _generatedPins = [];
  List<Map<String, dynamic>> _history       = [];

  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCached();
    _fetchAll();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _selectedNetworkName =>
      _networks.firstWhere((n) => n['id'] == _selectedNetworkId, orElse: () => {'name': ''})['name'] as String;

  List<Map<String, dynamic>> get _filteredPlans =>
      _selectedNetworkName.isEmpty ? [] : (_plans[_selectedNetworkName] ?? []);

  int get _selectedAvailable => _available[_selectedNetworkName] ?? 0;

  void _updateCost() {
    if (_selectedPlanId == null || _filteredPlans.isEmpty) { setState(() => _estimatedCost = 0); return; }
    final plan = _filteredPlans.firstWhere((p) => p['id'] == _selectedPlanId, orElse: () => {'amount_to_pay': 0.0});
    setState(() => _estimatedCost = ((plan['amount_to_pay'] as double?) ?? 0.0) * _quantity);
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  Future<void> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('recharge_card_cache');
      if (raw == null) return;
      final json  = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;

      final bp = Provider.of<UserBalanceProvider>(context, listen: false);
      bp.updateBalance((json['balance'] as num?)?.toDouble() ?? bp.balance, bp.bonusBalance);

      setState(() {
        final avail = json['available'] as Map? ?? {};
        _available = avail.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
        if (json['plans'] != null) {
          final rawPlans = json['plans'] as Map;
          _plans = rawPlans.map((k, v) => MapEntry(k.toString(), (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()));
        }
        if (json['history'] != null) {
          _history = (json['history'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        _isLoading = false;
      });
    } catch (e) { debugPrint('Cache load error: $e'); }
  }

  Future<void> _saveCache(double balance) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('recharge_card_cache', jsonEncode({
        'balance': balance, 'available': _available, 'plans': _plans, 'history': _history,
      }));
    } catch (_) {}
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<http.Response> _safeGet(Uri url, Map<String, String> headers) async {
    try { return await http.get(url, headers: headers).timeout(const Duration(seconds: 15)); }
    catch (_) { await Future.delayed(const Duration(seconds: 2)); return await http.get(url, headers: headers); }
  }

  Future<void> _fetchAll({bool bg = false}) async {
    if (bg) { setState(() => _isRefreshing = true); }
    else    { setState(() => _isLoading    = true); }

    try {
      final token = await AuthService.getToken();
      if (token == null) return;
      final headers = {'Authorization': 'Token $token'};

      final results = await Future.wait([
        _safeGet(Uri.parse('https://amsubnig.com/api/user/'),          headers),
        _safeGet(Uri.parse('https://amsubnig.com/api/rechargepin/'),   headers),
      ]);

      double newBalance = Provider.of<UserBalanceProvider>(context, listen: false).balance;

      // User data + recharge plans
      if (results[0].statusCode == 200) {
        final data = jsonDecode(results[0].body);
        newBalance  = double.tryParse(data['user']?['Account_Balance']?.toString() ?? '0') ?? 0.0;
        final bonus = double.tryParse(data['user']?['bonus_balance']?.toString()   ?? '0') ?? 0.0;

        final recharge = data['recharge'] as Map<String, dynamic>? ?? {};
        final newAvail = <String, int>{
          'MTN':     (recharge['mtn']     as num?)?.toInt() ?? 0,
          'GLO':     (recharge['glo']     as num?)?.toInt() ?? 0,
          'AIRTEL':  (recharge['airtel']  as num?)?.toInt() ?? 0,
          '9MOBILE': (recharge['9mobile'] as num?)?.toInt() ?? 0,
        };

        List<Map<String,dynamic>> parsePlans(dynamic raw) {
          if (raw == null) return [];
          return (raw as List).map((p) => {
            'id':             p['id'],
            'network_name':   p['network_name'] ?? '',
            'amount':         double.tryParse(p['amount']?.toString() ?? '0') ?? 0.0,
            'amount_to_pay':  double.tryParse(p['amount_to_pay']?.toString() ?? '0') ?? 0.0,
          }).toList();
        }

        if (!mounted) return;
        final bp = Provider.of<UserBalanceProvider>(context, listen: false);
        bp.updateBalance(newBalance, bonus);
        setState(() {
          _available = newAvail;
          _plans = {
            'MTN':     parsePlans(recharge['mtn_pin']),
            'GLO':     parsePlans(recharge['glo_pin']),
            'AIRTEL':  parsePlans(recharge['airtel_pin']),
            '9MOBILE': parsePlans(recharge['9mobile_pin']),
          };
        });
        _updateCost();
      }

      // History
      if (results[1].statusCode == 200) {
        final data   = jsonDecode(results[1].body);
        final list   = (data['results'] ?? (data is List ? data : [])) as List;
        setState(() {
          _history = list.map((item) {
            final m = item as Map<String, dynamic>;
            return {
              'id':        m['id'] ?? '',
              'network':   m['network_name'] ?? 'Unknown',
              'amount':    m['amount']?.toString() ?? '0',
              'quantity':  m['quantity'] ?? 0,
              'name':      m['name_on_card'] ?? '',
              'status':    m['Status'] ?? 'Unknown',
              'date':      m['create_date'] ?? '',
              'data_pin':  _normPin(m['data_pin']),
            };
          }).toList();
        });
      }

      await _saveCache(newBalance);
    } catch (e) {
      if (!bg) setState(() => _error = 'Network error: $e');
    } finally {
      setState(() { _isLoading = false; _isRefreshing = false; });
    }
  }

  // ── Generate: confirm → PIN → API ────────────────────────────────────────

  Future<void> _generate() async {
    if (_selectedNetworkId == null || _selectedPlanId == null) { setState(() => _error = 'Select network and denomination'); return; }
    final name = _nameController.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter name on card'); return; }

    final bp             = Provider.of<UserBalanceProvider>(context, listen: false);
    final currentBalance = bp.balance;
    if (_estimatedCost > currentBalance) { setState(() => _error = 'Insufficient balance (₦${currentBalance.toStringAsFixed(2)})'); return; }
    if (_selectedAvailable < _quantity)  { setState(() => _error = 'Only $_selectedAvailable pin${_selectedAvailable == 1 ? '' : 's'} available for $_selectedNetworkName'); return; }

    final selectedPlan = _filteredPlans.firstWhere((p) => p['id'] == _selectedPlanId, orElse: () => {});

    // ── Step 1: Confirmation dialog ───────────────────────────────────────
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: lightPurple, shape: BoxShape.circle), child: const Icon(Icons.credit_card, color: primaryPurple, size: 26)),
            const SizedBox(height: 12),
            const Text('Confirm Recharge Card', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _confirmRow('Network',    _selectedNetworkName),
                _confirmRow('Value',      '₦${(selectedPlan['amount'] as double? ?? 0).toStringAsFixed(0)} card'),
                _confirmRow('Quantity',   '$_quantity card${_quantity == 1 ? '' : 's'}'),
                _confirmRow('Name',       name),
                _confirmRow('Total Cost', '₦${_estimatedCost.toStringAsFixed(2)}'),
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

      final response = await http.post(
        Uri.parse('https://amsubnig.com/api/rechargepin/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'network': _selectedNetworkId, 'network_amount': _selectedPlanId, 'quantity': _quantity, 'name_on_card': name}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        // Parse pins from data_pin (JSON string of serialized objects)
        List<Map<String, dynamic>> pinsList = [];
        final rawPins = data['data_pin'];
        if (rawPins != null) {
          List<dynamic> parsed = rawPins is String ? jsonDecode(rawPins) : (rawPins as List);
          for (final item in parsed) {
            final f = item is Map && item.containsKey('fields') ? item['fields'] as Map : item as Map;
            String exp = f['expire_date']?.toString() ?? 'N/A';
            if (exp.contains('T')) exp = exp.split('T')[0];
            pinsList.add({
              'network':        _selectedNetworkName,
              'pin':            f['pin']?.toString() ?? 'N/A',
              'serial':         f['serial']?.toString() ?? 'N/A',
              'amount':         f['amount']?.toString() ?? selectedPlan['amount']?.toString() ?? 'N/A',
              'expire_date':    exp,
              'name_on_card':   data['name_on_card'] ?? name,
              'date_generated': DateTime.now().toString().split('.')[0],
            });
          }
        }

        bp.updateBalance(currentBalance - _estimatedCost, bp.bonusBalance);

        setState(() {
          _successMessage = '${pinsList.length} card${pinsList.length > 1 ? 's' : ''} generated!';
          _generatedPins  = pinsList;
          _isGenerating   = false;
        });
        _nameController.clear();
        _fetchAll(bg: true);
        if (mounted) _showPinsDialog();
      } else {
        final resp = jsonDecode(response.body);
        setState(() { _error = resp['error'] ?? 'Failed (${response.statusCode})'; _isGenerating = false; });
      }
    } catch (e) { setState(() { _error = 'Network error: $e'; _isGenerating = false; }); }
  }

  /// Normalises data_pin which the API may return as a JSON String or a List.
  String _normPin(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is List)   return raw.map((e) => e is Map ? (e['fields']?['pin'] ?? e['pin'] ?? '') : e.toString()).join(', ');
    return raw.toString();
  }

  Widget _confirmRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 11, color: lightText))),
      const SizedBox(width: 6),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText), overflow: TextOverflow.ellipsis)),
    ]),
  );

  // ── PDF / Print ───────────────────────────────────────────────────────────

  Future<void> _generatePDF() async {
    try {
      final pdf = pw.Document();
      final dt  = DateTime.now();
      final dtStr = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(15),
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        build: (_) {
          final widgets = <pw.Widget>[
            pw.Text('$_selectedNetworkName Recharge Cards — $dtStr', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.purple)),
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
      final file = File('${dir.path}/recharge_cards_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdf.save());
      if (mounted) { await OpenFile.open(file.path); _snack('PDF generated!'); }
    } catch (e) { if (mounted) _snack('Error generating PDF', isError: true); }
  }

  Future<void> _printPDF() async {
    try {
      final pdf = pw.Document();
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(15),
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        build: (_) {
          final widgets = <pw.Widget>[
            pw.Text('$_selectedNetworkName Recharge Cards', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.purple)),
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
          pw.Text('${pin['network']} ₦${pin['amount']}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.purple)),
          pw.Text(nm.length > 8 ? nm.substring(0, 8) : nm, style: pw.TextStyle(fontSize: 7, color: PdfColors.grey)),
        ]),
        pw.Center(child: pw.Text(pin['pin'], style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, font: pw.Font.courierBold()))),
        pw.Text('S/N: ${pin['serial'].toString().length > 12 ? pin['serial'].toString().substring(0, 12) : pin['serial']}', style: pw.TextStyle(fontSize: 6)),
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

  // ── Pins dialog ───────────────────────────────────────────────────────────

  void _showPinsDialog() {
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
                const Expanded(child: Text('Generated Recharge Cards', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
                IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            // List
            Expanded(
              child: _generatedPins.isEmpty
                  ? Center(child: Text('No cards generated', style: TextStyle(color: lightText, fontSize: 13)))
                  : ListView.builder(padding: const EdgeInsets.all(14), itemCount: _generatedPins.length, itemBuilder: (_, i) => _buildPinCard(_generatedPins[i], i)),
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
              Text('${pin['network']} ₦${pin['amount']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryPurple)),
            ]),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(10)), child: Text(pin['name_on_card'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryPurple))),
          ]),
        ),
        // PIN
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(10), border: Border.all(color: primaryPurple.withOpacity(0.25))),
            child: Row(children: [
              const Text('PIN:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: darkText)),
              const SizedBox(width: 8),
              Expanded(child: SelectableText(pin['pin'], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryPurple, letterSpacing: 2), textAlign: TextAlign.right)),
              GestureDetector(onTap: () { Clipboard.setData(ClipboardData(text: pin['pin'])); _snack('PIN copied!'); }, child: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.copy, color: primaryPurple, size: 17))),
            ]),
          ),
        ),
        // Details
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 3.2, crossAxisSpacing: 6, mainAxisSpacing: 6, children: [
            _detailBox('Serial',    pin['serial']),
            _detailBox('Expires',   pin['expire_date']),
            _detailBox('Generated', pin['date_generated']),
            _detailBox('Network',   pin['network']),
          ]),
        ),
        // Footer
        Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: lightPurple, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14))), child: const Center(child: Text('Powered by AMSUBNIG', style: TextStyle(fontSize: 9, color: primaryPurple, fontWeight: FontWeight.w600)))),
      ]),
    );
  }

  Widget _detailBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(7)),
      child: Row(children: [
        Text(label, style: const TextStyle(color: lightText, fontSize: 10)),
        const SizedBox(width: 4),
        Expanded(child: Text(value, style: const TextStyle(color: darkText, fontSize: 10), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bp            = Provider.of<UserBalanceProvider>(context);
    final walletBalance = bp.balance;

    if (_isLoading) {
      return Scaffold(backgroundColor: const Color(0xFFF8F7FF), appBar: _appBar(), body: _skeleton());
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: _appBar(),
      body: RefreshIndicator(
        color: primaryPurple,
        onRefresh: () => _fetchAll(bg: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: [
            // ── Wallet card ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [primaryPurple, Color(0xFF9B7DFF)]), borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: primaryPurple.withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 5))]),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Wallet Balance', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('₦${walletBalance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ]),
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(18)), child: const Row(children: [Icon(Icons.account_balance_wallet, color: Colors.white, size: 14), SizedBox(width: 5), Text('Available', style: TextStyle(color: Colors.white, fontSize: 11))])),
              ]),
            ),

            // ── Info alert ────────────────────────────────────────────────
            if (_infoAlert != null && _infoAlert!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withOpacity(0.4))),
                child: Row(children: [const Icon(Icons.info_outline, color: Colors.amber, size: 16), const SizedBox(width: 10), Expanded(child: Text(_infoAlert!, style: const TextStyle(fontSize: 12, color: darkText)))]),
              ),
            ],

            const SizedBox(height: 14),

            // ── Form card ─────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))], border: Border.all(color: Colors.grey[200]!)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.credit_card, color: primaryPurple, size: 17)),
                    const SizedBox(width: 10),
                    const Text('Generate Recharge Cards', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: darkText)),
                  ]),
                  const SizedBox(height: 16),

                  // ── 1. Network ────────────────────────────────────────
                  _fieldLabel('1. Select Network'),
                  const SizedBox(height: 8),
                  _buildNetworkRow(),
                  const SizedBox(height: 14),

                  // ── 2. Denomination ───────────────────────────────────
                  _fieldLabel('2. Select Denomination'),
                  const SizedBox(height: 8),
                  _buildDropdown<int>(
                    value: _selectedPlanId,
                    hint: _selectedNetworkId == null ? 'Select network first' : 'Select denomination',
                    icon: Icons.payments,
                    items: _filteredPlans.map((p) => DropdownMenuItem<int>(value: p['id'] as int, child: Text('₦${(p['amount'] as double).toStringAsFixed(0)} card  —  cost ₦${(p['amount_to_pay'] as double).toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: _selectedNetworkId == null ? null : (v) { setState(() { _selectedPlanId = v; _updateCost(); }); },
                  ),
                  const SizedBox(height: 12),

                  // ── 3. Quantity ───────────────────────────────────────
                  _fieldLabel('3. Quantity (max 39)'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
                    child: Row(children: [
                      const Icon(Icons.format_list_numbered, color: lightText, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: DropdownButton<int>(
                        value: _quantity, isExpanded: true, underline: const SizedBox(),
                        style: const TextStyle(color: darkText, fontSize: 13),
                        items: List.generate(39, (i) => i + 1).map((q) => DropdownMenuItem(value: q, child: Text('$q card${q == 1 ? '' : 's'}'))).toList(),
                        onChanged: (v) { setState(() { _quantity = v!; _updateCost(); }); },
                      )),
                    ]),
                  ),
                  const SizedBox(height: 12),

                  // ── 4. Name ───────────────────────────────────────────
                  _fieldLabel('4. Name on Card'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
                    child: TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(color: darkText, fontSize: 13),
                      decoration: InputDecoration(hintText: 'e.g. My Shop', hintStyle: TextStyle(color: lightText, fontSize: 12), border: InputBorder.none, prefixIcon: const Icon(Icons.person_outline, color: primaryPurple, size: 18), contentPadding: const EdgeInsets.symmetric(vertical: 13)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Cost banner ───────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryPurple.withOpacity(0.08), primaryBlue.withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10), border: Border.all(color: primaryPurple.withOpacity(0.25))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Total Cost:', style: TextStyle(fontSize: 13, color: darkText)),
                      Text('₦${_estimatedCost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryPurple)),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // ── Generate button ───────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isGenerating ? null : _generate,
                      style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, disabledBackgroundColor: Colors.grey[400], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 3, shadowColor: primaryPurple.withOpacity(0.4)),
                      child: _isGenerating
                          ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)), SizedBox(width: 10), Text('Generating...', style: TextStyle(fontSize: 14))])
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.credit_card, size: 18), SizedBox(width: 8), Text('Generate Recharge Cards', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]),
                    ),
                  ),

                  if (_error != null) ...[const SizedBox(height: 10), _statusBanner(icon: Icons.error_outline, text: _error!, iconColor: Colors.red.shade700, bgColor: Colors.red.shade50, borderColor: Colors.red.shade200, textColor: Colors.red.shade700, onClose: () => setState(() => _error = null))],
                  if (_successMessage != null) ...[const SizedBox(height: 10), _statusBanner(icon: Icons.check_circle_outline, text: _successMessage!, iconColor: Colors.green.shade700, bgColor: Colors.green.shade50, borderColor: Colors.green.shade200, textColor: Colors.green.shade700, onClose: () => setState(() => _successMessage = null))],
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
                ? Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)), child: Column(children: [const Icon(Icons.history_toggle_off, size: 32, color: lightText), const SizedBox(height: 8), Text('No recent orders', style: TextStyle(color: lightText, fontSize: 12))]))
                : Column(children: _history.take(10).map(_buildHistoryTile).toList()),
          ],
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _appBar() {
    return AppBar(
      title: const Text('Recharge Card', style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16)),
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
          IconButton(icon: const Icon(Icons.refresh, color: primaryPurple, size: 20), onPressed: () => _fetchAll(bg: true)),
      ],
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────

  Widget _skeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), children: [
        Container(height: 78, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18))),
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: List.generate(5, (_) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Container(height: 46, color: Colors.white))))),
      ]),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildNetworkRow() {
    return Row(children: _networks.map((net) {
      final isSelected   = _selectedNetworkId == net['id'];
      final color        = net['color'] as Color;
      final avail        = _available[net['name'] as String] ?? 0;
      final outOfStock   = avail == 0;
      return Expanded(child: GestureDetector(
        onTap: outOfStock ? null : () { setState(() { _selectedNetworkId = net['id'] as int; _selectedPlanId = null; _updateCost(); }); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: EdgeInsets.only(right: net['id'] != _networks.last['id'] ? 6 : 0),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: outOfStock ? Colors.grey.shade100 : (isSelected ? color.withOpacity(0.1) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: outOfStock ? Colors.grey.shade200 : (isSelected ? color : Colors.grey[200]!), width: isSelected ? 2 : 1),
            boxShadow: [BoxShadow(color: isSelected ? color.withOpacity(0.15) : Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(height: 36, child: Image.asset(net['image'] as String, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.sim_card, size: 28, color: outOfStock ? Colors.grey : color))),
            const SizedBox(height: 4),
            Text(net['name'] as String, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: outOfStock ? Colors.grey : (isSelected ? color : darkText))),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: outOfStock ? Colors.grey.shade200 : (isSelected ? color.withOpacity(0.15) : lightPurple), borderRadius: BorderRadius.circular(8)),
              child: Text('$avail avail.', style: TextStyle(fontSize: 9, color: outOfStock ? Colors.grey : (isSelected ? color : primaryPurple), fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ));
    }).toList());
  }

  Widget _buildDropdown<T>({required T? value, required String hint, required IconData icon, required List<DropdownMenuItem<T>> items, required void Function(T?)? onChanged}) {
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

  Widget _fieldLabel(String label) => Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: darkText));

  Widget _statusBanner({required IconData icon, required String text, required Color iconColor, required Color bgColor, required Color borderColor, required Color textColor, VoidCallback? onClose}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
      child: Row(children: [Icon(icon, color: iconColor, size: 15), const SizedBox(width: 8), Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 12))), if (onClose != null) GestureDetector(onTap: onClose, child: Icon(Icons.close, color: iconColor, size: 14))]),
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
        Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.credit_card, color: primaryPurple, size: 16)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${order['network']} · ${order['quantity']} card${order['quantity'] == 1 ? '' : 's'}  ·  ₦${order['amount']}', style: const TextStyle(fontWeight: FontWeight.w600, color: darkText, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(order['date'], style: TextStyle(fontSize: 10, color: lightText)),
          const SizedBox(height: 5),
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: isSuccess ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(10)), child: Text(order['status'], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isSuccess ? Colors.green.shade700 : Colors.orange.shade700))),
        ])),
        if ((order['data_pin'] as String).isNotEmpty)
          GestureDetector(onTap: () { Clipboard.setData(ClipboardData(text: order['data_pin'] as String)); _snack('PINs copied!'); }, child: const Padding(padding: EdgeInsets.only(left: 8, top: 2), child: Icon(Icons.copy, color: primaryPurple, size: 16))),
      ]),
    );
  }
}