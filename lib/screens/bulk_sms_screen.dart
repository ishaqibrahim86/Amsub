import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/pin_auth_service.dart';
import '../providers/user_balance_provider.dart';

class BulkSmsScreen extends StatefulWidget {
  const BulkSmsScreen({super.key});

  @override
  State<BulkSmsScreen> createState() => _BulkSmsScreenState();
}

class _BulkSmsScreenState extends State<BulkSmsScreen> {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color primaryBlue   = Color(0xFF3B82F6);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  final _formKey             = GlobalKey<FormState>();
  final _senderController    = TextEditingController(text: 'YourBrand');
  final _messageController   = TextEditingController();
  final _recipientsController= TextEditingController();

  bool    _dnd       = false;
  bool    _isSending = false;
  String? _error;
  String? _successMessage;

  List<Map<String, dynamic>> _history        = [];
  bool                       _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _senderController.dispose();
    _messageController.dispose();
    _recipientsController.dispose();
    super.dispose();
  }

  // ── History ───────────────────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final token = await AuthService.getToken();
      if (token == null) return;
      final response = await http.get(
        Uri.parse('https://amsubnig.com/api/sendsms/'),
        headers: {'Authorization': 'Token $token'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _history = data.map((item) => {
            'ident':   item['ident']        ?? 'N/A',
            'sender':  item['sendername']   ?? 'N/A',
            'message': item['message']      ?? '',
            'to':      item['to']           ?? '',
            'amount':  item['amount']?.toString() ?? '0',
            'total':   item['total']        ?? 0,
            'date':    item['create_date']  ?? '',
          }).toList();
        });
      }
    } catch (e) { debugPrint('Bulk SMS history error: $e'); }
    finally { setState(() => _isLoadingHistory = false); }
  }

  // ── Send: confirm → PIN → API ─────────────────────────────────────────────

  Future<void> _sendBulkSms() async {
    if (!_formKey.currentState!.validate()) return;

    final sender     = _senderController.text.trim();
    final message    = _messageController.text.trim();
    final recipients = _recipientsController.text.trim();

    if (recipients.isEmpty) {
      setState(() => _error = 'Enter at least one recipient number');
      return;
    }

    // ── Step 1: Confirmation dialog ───────────────────────────────────────
    final recipientCount = recipients.split(',').where((s) => s.trim().isNotEmpty).length;
    final rate           = _dnd ? 3.5 : 2.5;
    final estimatedCost  = recipientCount * rate;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: lightPurple, shape: BoxShape.circle), child: const Icon(Icons.sms, color: primaryPurple, size: 26)),
            const SizedBox(height: 12),
            const Text('Confirm Bulk SMS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _confirmRow('Sender',      sender),
                _confirmRow('Recipients',  '$recipientCount number${recipientCount == 1 ? '' : 's'}'),
                _confirmRow('Route',       _dnd ? 'DND (₦3.5/SMS)' : 'Standard (₦2.5/SMS)'),
                _confirmRow('Est. Cost',   '₦${estimatedCost.toStringAsFixed(2)}'),
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

    setState(() { _isSending = true; _error = null; _successMessage = null; });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() { _error = 'Session expired'; _isSending = false; });
        return;
      }

      final response = await http.post(
        Uri.parse('https://amsubnig.com/api/sendsms/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'sender': sender, 'message': message, 'recetipient': recipients, 'DND': _dnd}),
      );

      if (response.statusCode == 200) {
        setState(() {
          _successMessage = jsonDecode(response.body)['error'] ?? 'Bulk SMS sent successfully!';
          _isSending = false;
        });
        _messageController.clear();
        _recipientsController.clear();
        _loadHistory();

        // Refresh balance
        if (mounted) Provider.of<UserBalanceProvider>(context, listen: false).refresh();
      } else {
        final body = jsonDecode(response.body);
        setState(() { _error = body['error'] ?? 'Failed: ${response.statusCode}'; _isSending = false; });
      }
    } catch (e) {
      setState(() { _error = 'Network error: $e'; _isSending = false; });
    }
  }

  Widget _confirmRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 11, color: lightText))),
      const SizedBox(width: 6),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText), overflow: TextOverflow.ellipsis)),
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
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 48,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: primaryPurple, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [primaryPurple, primaryBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.sms, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 8),
          const Text('Bulk SMS', style: TextStyle(color: primaryPurple, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(28)),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, color: primaryPurple, size: 19),
              onPressed: _loadHistory,
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await _loadHistory(); await bp.refresh(); },
        color: primaryPurple,
        child: Form(
          key: _formKey,
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

              // ── Rates info banner ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: lightPurple,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryPurple.withOpacity(0.2)),
                ),
                child: Row(children: [
                  Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: primaryPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.info_outline, color: primaryPurple, size: 16)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Bulk SMS Rates', style: TextStyle(fontWeight: FontWeight.bold, color: primaryPurple, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text('Standard: ₦2.5/SMS  ·  DND: ₦3.5/SMS', style: TextStyle(color: lightText, fontSize: 11)),
                  ])),
                ]),
              ),

              const SizedBox(height: 16),

              // ── Sender field ──────────────────────────────────────────────
              _buildField(
                controller: _senderController,
                label: 'Sender Name',
                icon: Icons.badge,
                maxLength: 11,
                helper: 'Max 11 characters',
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),

              const SizedBox(height: 12),

              // ── Message field ─────────────────────────────────────────────
              _buildField(
                controller: _messageController,
                label: 'Message',
                icon: Icons.message,
                maxLines: 4,
                validator: (v) => v!.isEmpty ? 'Enter message' : null,
              ),

              const SizedBox(height: 12),

              // ── Recipients field ──────────────────────────────────────────
              _buildField(
                controller: _recipientsController,
                label: 'Recipients',
                icon: Icons.contacts,
                keyboard: TextInputType.phone,
                helper: 'Separate numbers with commas, no spaces. Up to 10,000 numbers.\ne.g. 08100000000,09111111111,08077777777',
                helperMaxLines: 3,
                validator: (v) => v!.isEmpty ? 'Enter at least one number' : null,
              ),

              const SizedBox(height: 12),

              // ── DND toggle ────────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _dnd ? primaryPurple.withOpacity(0.3) : Colors.grey[200]!),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: Text('Enable DND', style: TextStyle(fontWeight: FontWeight.w600, color: darkText, fontSize: 13)),
                  subtitle: Text('Higher charge but reaches DND numbers', style: TextStyle(color: lightText, fontSize: 11)),
                  value: _dnd,
                  activeColor: primaryPurple,
                  activeTrackColor: primaryPurple.withOpacity(0.3),
                  onChanged: (v) => setState(() => _dnd = v),
                ),
              ),

              const SizedBox(height: 18),

              // ── Send button ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [primaryPurple, primaryBlue], begin: Alignment.centerLeft, end: Alignment.centerRight),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: primaryPurple.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _sendBulkSms,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: _isSending
                        ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('Sending...', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    ])
                        : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.send, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Send Bulk SMS', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),

              // ── Error / Success banners ───────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 12),
                _statusBanner(icon: Icons.error_outline, text: _error!, iconColor: Colors.red.shade700, bgColor: Colors.red.shade50, borderColor: Colors.red.shade200, textColor: Colors.red.shade700),
              ],
              if (_successMessage != null) ...[
                const SizedBox(height: 12),
                _statusBanner(icon: Icons.check_circle_outline, text: _successMessage!, iconColor: Colors.green.shade700, bgColor: Colors.green.shade50, borderColor: Colors.green.shade200, textColor: Colors.green.shade700),
              ],

              const SizedBox(height: 24),

              // ── History section ───────────────────────────────────────────
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Recent Bulk SMS', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryPurple)),
                TextButton(
                  onPressed: _loadHistory,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                  child: const Text('Refresh', style: TextStyle(color: primaryBlue, fontSize: 12)),
                ),
              ]),

              const SizedBox(height: 10),

              _isLoadingHistory
                  ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: primaryPurple)))
                  : _history.isEmpty
                  ? Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  const Icon(Icons.sms, size: 36, color: lightText),
                  const SizedBox(height: 10),
                  const Text('No bulk SMS history yet', style: TextStyle(color: lightText, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Your sent messages will appear here', style: TextStyle(color: lightText, fontSize: 11)),
                ]),
              )
                  : Column(
                children: _history.map((tx) => _buildHistoryTile(tx)).toList(),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int? maxLength,
    int maxLines = 1,
    String? helper,
    int? helperMaxLines,
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: TextFormField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        keyboardType: keyboard,
        style: const TextStyle(color: darkText, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: primaryPurple, fontSize: 13),
          prefixIcon: Icon(icon, color: primaryPurple, size: 18),
          alignLabelWithHint: maxLines > 1,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryPurple.withOpacity(0.2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primaryPurple, width: 1.5)),
          helperText: helper,
          helperMaxLines: helperMaxLines ?? 1,
          helperStyle: TextStyle(color: lightText, fontSize: 10, height: 1.3),
          counterStyle: TextStyle(color: lightText, fontSize: 10),
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: maxLines > 1 ? 12 : 0),
        ),
        validator: validator,
      ),
    );
  }

  Widget _statusBanner({required IconData icon, required String text, required Color iconColor, required Color bgColor, required Color borderColor, required Color textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 12))),
      ]),
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> tx) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryPurple.withOpacity(0.15)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [primaryPurple, primaryBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.sms, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(tx['sender'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, color: darkText, fontSize: 13)),
              Text(tx['date'] ?? '', style: const TextStyle(fontSize: 10, color: lightText)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.phone, size: 11, color: lightText),
              const SizedBox(width: 4),
              Expanded(child: Text('To: ${tx['to'] ?? 'N/A'}', style: const TextStyle(fontSize: 11, color: lightText), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(7)),
              child: Text(tx['message'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: darkText)),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: primaryPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Text('₦${tx['amount'] ?? '0'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryPurple)),
              ),
            ),
          ])),
        ]),
      ),
    );
  }
}