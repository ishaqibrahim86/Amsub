import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/pin_auth_service.dart';
import '../providers/user_balance_provider.dart';

class ResultCheckerScreen extends StatefulWidget {
  const ResultCheckerScreen({super.key});

  @override
  State<ResultCheckerScreen> createState() => _ResultCheckerScreenState();
}

class _ResultCheckerScreenState extends State<ResultCheckerScreen> {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color primaryBlue   = Color(0xFF3B82F6);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  String?  _selectedExam;
  int      _quantity       = 1;
  double   _estimatedCost  = 0.0;
  bool     _isLoading      = false;
  bool     _isGenerating   = false;
  String?  _error;
  String?  _successMessage;
  List<String>              _generatedPins = [];
  List<Map<String, dynamic>> _history      = [];

  Map<String, double> _examPrices = {'WAEC': 0.0, 'NECO': 0.0};
  final List<String>  _exams      = ['WAEC', 'NECO'];

  @override
  void initState() {
    super.initState();
    _fetchUserDataAndPrices();
    _fetchHistory();
  }

  // ── Fetch prices ──────────────────────────────────────────────────────────

  Future<void> _fetchUserDataAndPrices() async {
    setState(() => _isLoading = true);
    try {
      final token = await AuthService.getToken();
      if (token == null) return;
      final response = await http.get(
        Uri.parse('https://amsubnig.com/api/user/'),
        headers: {'Authorization': 'Token $token'},
      );
      if (response.statusCode == 200) {
        final data     = jsonDecode(response.body);
        final examData = data['Exam'] as Map<String, dynamic>? ?? {};
        final balance  = double.tryParse(data['user']?['Account_Balance']?.toString() ?? '0') ?? 0.0;
        final bonus    = double.tryParse(data['user']?['bonus_balance']?.toString()   ?? '0') ?? 0.0;

        if (mounted) {
          final bp = Provider.of<UserBalanceProvider>(context, listen: false);
          bp.updateBalance(balance, bonus);
          setState(() {
            _examPrices['WAEC'] = (examData['WAEC']?['amount'] as num?)?.toDouble() ?? 0.0;
            _examPrices['NECO'] = (examData['NECO']?['amount'] as num?)?.toDouble() ?? 0.0;
            _isLoading = false;
          });
          _updateCost();
        }
      }
    } catch (e) {
      debugPrint('User data fetch error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _updateCost() {
    if (_selectedExam == null) return;
    setState(() => _estimatedCost = (_examPrices[_selectedExam!] ?? 0.0) * _quantity);
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    try {
      final token = await AuthService.getToken();
      if (token == null) return;
      final response = await http.get(Uri.parse('https://amsubnig.com/api/epin/'), headers: {'Authorization': 'Token $token'});
      if (response.statusCode == 200) {
        final data    = jsonDecode(response.body);
        final results = data is List ? data : (data['results'] ?? []) as List;
        setState(() {
          _history = results.map((item) {
            final m = item as Map<String, dynamic>;
            return {'exam': m['exam_name'] ?? 'Unknown', 'quantity': m['quantity'] ?? 0, 'amount': m['amount']?.toString() ?? '0', 'pins': m['pins'] ?? '', 'status': m['Status'] ?? 'Unknown', 'date': m['create_date'] ?? ''};
          }).toList();
        });
      }
    } catch (e) { debugPrint('History error: $e'); }
    finally { setState(() => _isLoading = false); }
  }

  // ── Generate: confirm → PIN → API ────────────────────────────────────────

  Future<void> _generatePins() async {
    if (_selectedExam == null) { setState(() => _error = 'Select exam type'); return; }

    // ── Step 1: Confirmation dialog ───────────────────────────────────────
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: lightPurple, shape: BoxShape.circle), child: const Icon(Icons.school, color: primaryPurple, size: 26)),
            const SizedBox(height: 12),
            const Text('Confirm PIN Purchase', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _confirmRow('Exam',     _selectedExam!),
                _confirmRow('Quantity', '$_quantity ${_quantity == 1 ? 'PIN' : 'PINs'}'),
                _confirmRow('Cost',     '₦${_estimatedCost.toStringAsFixed(2)}'),
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

    setState(() { _isGenerating = true; _error = null; _successMessage = null; _generatedPins = []; });

    try {
      final token = await AuthService.getToken();
      if (token == null) { setState(() { _error = 'Session expired'; _isGenerating = false; }); return; }

      final response = await http.post(
        Uri.parse('https://amsubnig.com/api/epin/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'exam_name': _selectedExam, 'quantity': _quantity}),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final pins = data['pins']?.toString() ?? '';
        setState(() {
          _successMessage = 'PINs generated successfully!';
          _generatedPins  = pins.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
          _isGenerating   = false;
        });
        _fetchHistory();
        if (mounted) Provider.of<UserBalanceProvider>(context, listen: false).refresh();
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
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText))),
    ]),
  );

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bp           = Provider.of<UserBalanceProvider>(context);
    final walletBalance= bp.balance;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        title: const Text('Result Checker PIN', style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: primaryPurple,
        elevation: 0,
        toolbarHeight: 48,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: primaryPurple, size: 18), onPressed: () => Navigator.pop(context)),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: primaryPurple, size: 20), onPressed: () { _fetchUserDataAndPrices(); _fetchHistory(); })],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await _fetchUserDataAndPrices(); await _fetchHistory(); await bp.refresh(); },
        color: primaryPurple,
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(18)),
                  child: const Row(children: [Icon(Icons.account_balance_wallet, color: Colors.white, size: 14), SizedBox(width: 5), Text('Available', style: TextStyle(color: Colors.white, fontSize: 11))]),
                ),
              ]),
            ),

            const SizedBox(height: 14),

            // ── Form card ─────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))],
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Header
                  Row(children: [
                    Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.school, color: primaryPurple, size: 17)),
                    const SizedBox(width: 10),
                    const Flexible(child: Text('Generate Result Checker PIN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: darkText))),
                  ]),

                  const SizedBox(height: 16),

                  // ── Exam type ─────────────────────────────────────────
                  _fieldLabel('Exam Type'),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
                    child: DropdownButtonFormField<String>(
                      value: _selectedExam,
                      hint: Text('Select Exam', style: TextStyle(color: lightText, fontSize: 13)),
                      items: _exams.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: darkText, fontSize: 13)))).toList(),
                      onChanged: (val) { setState(() { _selectedExam = val; _updateCost(); }); },
                      decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8), prefixIcon: Icon(Icons.assignment_outlined, size: 18)),
                      icon: const Icon(Icons.arrow_drop_down, color: primaryPurple),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Quantity ──────────────────────────────────────────
                  _fieldLabel('Quantity'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
                    child: Row(children: [
                      const Icon(Icons.format_list_numbered, color: lightText, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: DropdownButton<int>(
                        value: _quantity,
                        isExpanded: true,
                        underline: const SizedBox(),
                        style: const TextStyle(color: darkText, fontSize: 13),
                        items: List.generate(5, (i) => i + 1).map((q) => DropdownMenuItem(value: q, child: Text('$q ${q == 1 ? 'PIN' : 'PINs'}'))).toList(),
                        onChanged: (val) { setState(() { _quantity = val!; _updateCost(); }); },
                      )),
                    ]),
                  ),

                  const SizedBox(height: 12),

                  // ── Cost banner ───────────────────────────────────────
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

                  // ── Generate button ───────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isGenerating ? null : _generatePins,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryPurple,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[400],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 3,
                        shadowColor: primaryPurple.withOpacity(0.4),
                      ),
                      child: _isGenerating
                          ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)), SizedBox(width: 10), Text('Generating...', style: TextStyle(fontSize: 14))])
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.school, size: 18), SizedBox(width: 8), Text('Generate PINs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]),
                    ),
                  ),

                  // ── Error / Success ───────────────────────────────────
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _statusBanner(icon: Icons.error_outline,    text: _error!,          iconColor: Colors.red.shade700,   bgColor: Colors.red.shade50,   borderColor: Colors.red.shade200,   textColor: Colors.red.shade700),
                  ],
                  if (_successMessage != null) ...[
                    const SizedBox(height: 12),
                    _statusBanner(icon: Icons.check_circle_outline, text: _successMessage!, iconColor: Colors.green.shade700, bgColor: Colors.green.shade50, borderColor: Colors.green.shade200, textColor: Colors.green.shade700),
                  ],

                  // ── Generated PINs ────────────────────────────────────
                  if (_generatedPins.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Row(children: [Icon(Icons.vpn_key, color: primaryPurple, size: 17), SizedBox(width: 7), Text('Generated PINs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: darkText))]),
                    const SizedBox(height: 10),
                    ..._generatedPins.asMap().entries.map((entry) {
                      final i   = entry.key;
                      final pin = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(10), border: Border.all(color: primaryPurple.withOpacity(0.25))),
                        child: Row(children: [
                          Container(
                            width: 24, height: 24,
                            decoration: const BoxDecoration(color: primaryPurple, shape: BoxShape.circle),
                            child: Center(child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: SelectableText(pin, style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w600, color: primaryPurple, letterSpacing: 1.5))),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: pin));
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('PIN copied!'), backgroundColor: primaryPurple, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                            },
                            child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.copy, color: primaryPurple, size: 18)),
                          ),
                        ]),
                      );
                    }),
                  ],
                ]),
              ),
            ),

            const SizedBox(height: 18),

            // ── History section ───────────────────────────────────────────
            Row(children: [
              Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.history, color: primaryPurple, size: 14)),
              const SizedBox(width: 8),
              const Text('Recent Orders', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: darkText)),
            ]),

            const SizedBox(height: 10),

            _isLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: primaryPurple)))
                : _history.isEmpty
                ? Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                const Icon(Icons.history_toggle_off, size: 34, color: lightText),
                const SizedBox(height: 8),
                Text('No recent orders', style: TextStyle(color: lightText, fontSize: 13)),
              ]),
            )
                : Column(
              children: _history.map((order) {
                final status    = order['status'].toString().toLowerCase();
                final isSuccess = status.contains('success') || status.contains('completed');
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.school, color: primaryPurple, size: 16)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${order['exam']} · ${order['quantity']} ${order['quantity'] == 1 ? 'PIN' : 'PINs'}', style: const TextStyle(fontWeight: FontWeight.w600, color: darkText, fontSize: 13)),
                      const SizedBox(height: 3),
                      Text('₦${order['amount']}  ·  ${order['date']}', style: TextStyle(fontSize: 11, color: lightText)),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: isSuccess ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                        child: Text(order['status'], style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isSuccess ? Colors.green.shade700 : Colors.orange.shade700)),
                      ),
                    ])),
                    if (order['pins'].isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: order['pins']));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('PINs copied!'), backgroundColor: primaryPurple, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                        },
                        child: const Padding(padding: EdgeInsets.only(left: 8, top: 2), child: Icon(Icons.copy, color: primaryPurple, size: 17)),
                      ),
                  ]),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reusable helpers ──────────────────────────────────────────────────────

  Widget _fieldLabel(String label) => Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: darkText));

  Widget _statusBanner({required IconData icon, required String text, required Color iconColor, required Color bgColor, required Color borderColor, required Color textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
      child: Row(children: [Icon(icon, color: iconColor, size: 15), const SizedBox(width: 8), Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 12)))]),
    );
  }
}