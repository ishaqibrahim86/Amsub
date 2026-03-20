import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../services/auth_service.dart';
import '../services/virtual_account_service.dart';
import 'contact_us_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

class FundWalletScreen extends StatefulWidget {
  const FundWalletScreen({super.key});

  @override
  State<FundWalletScreen> createState() => _FundWalletScreenState();
}

class _FundWalletScreenState extends State<FundWalletScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color primaryBlue   = Color(0xFF3B82F6);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  List<Map<String, dynamic>> bankAccounts = [];
  bool isLoading         = true;
  bool isRefreshing      = false;
  bool _isCreatingAccount= false;
  String? errorMessage;
  String? fullName;

  static const String _cacheBankAccountsKey = 'bank_accounts_cache';
  static const String _cacheFullNameKey      = 'full_name_cache';
  static const String _cacheTimestampKey     = 'bank_cache_timestamp';
  static const Duration _cacheDuration       = Duration(minutes: 10);

  late AnimationController _animationController;
  late Animation<double>   _fadeAnimation;
  Timer? _retryTimer;

  final TextEditingController _bvnController = TextEditingController();
  final TextEditingController _ninController = TextEditingController();
  String _idType = 'bvn';

  // Which account number was most recently copied (for feedback)
  String? _copiedAccountNumber;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);
    WidgetsBinding.instance.addObserver(this);
    _loadCachedData();
    fetchBankAccounts();
  }

  @override
  void dispose() {
    _bvnController.dispose();
    _ninController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) fetchBankAccounts(isBackground: true);
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  Future<void> _loadCachedData() async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - timestamp >= _cacheDuration.inMilliseconds) return;
      final accountsData = prefs.getString(_cacheBankAccountsKey);
      final nameData     = prefs.getString(_cacheFullNameKey);
      if (accountsData != null) setState(() => bankAccounts = List<Map<String, dynamic>>.from(jsonDecode(accountsData)));
      if (nameData != null)     setState(() => fullName = nameData);
      setState(() => isLoading = false);
      _animationController.forward();
    } catch (e) { debugPrint('Cache load error: $e'); }
  }

  Future<void> _cacheData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheBankAccountsKey, jsonEncode(bankAccounts));
      if (fullName != null) await prefs.setString(_cacheFullNameKey, fullName!);
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) { debugPrint('Cache save error: $e'); }
  }

  // ── API ───────────────────────────────────────────────────────────────────

  Future<http.Response> _safeApiCall(Future<http.Response> Function() fn) async {
    for (int i = 0; i < 3; i++) {
      try { return await fn().timeout(const Duration(seconds: 15)); }
      catch (e) { if (i == 2) rethrow; await Future.delayed(Duration(seconds: i + 1)); }
    }
    throw Exception('Max retries exceeded');
  }

  Future<void> fetchBankAccounts({bool isBackground = false}) async {
    if (isBackground) { setState(() => isRefreshing = true); }
    else              { setState(() { isLoading = true; errorMessage = null; }); }

    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        setState(() { isLoading = false; isRefreshing = false; errorMessage = 'Session expired. Please login again.'; });
        return;
      }

      final response = await _safeApiCall(() => http.get(
        Uri.parse('https://amsubnig.com/api/user/'),
        headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
      ));

      if (response.statusCode == 200) {
        final data     = jsonDecode(response.body) as Map<String, dynamic>;
        final userData = data['user'] as Map<String, dynamic>?;
        if (userData != null) {
          final banks       = userData['bank_accounts']?['accounts'] as List?;
          final newFullName = userData['FullName'] as String?;
          setState(() {
            bankAccounts = banks != null ? banks.map((e) => Map<String, dynamic>.from(e)).toList() : [];
            fullName     = newFullName;
            isLoading    = false;
            isRefreshing = false;
            errorMessage = null;
          });
          await _cacheData();
          _animationController.forward();
        } else {
          setState(() { isLoading = false; isRefreshing = false; errorMessage = 'User data not found'; });
        }
      } else {
        setState(() { isLoading = false; isRefreshing = false; errorMessage = 'Failed to load (${response.statusCode})'; });
        if (!isBackground) _scheduleRetry();
      }
    } catch (e) {
      setState(() { isLoading = false; isRefreshing = false; errorMessage = 'Network error. Please check your connection.'; });
      if (!isBackground) _scheduleRetry();
      debugPrint('Fetch error: $e');
    }
  }

  Future<void> _createVirtualAccount() async {
    final bvn = _idType == 'bvn' ? _bvnController.text.trim() : null;
    final nin = _idType == 'nin' ? _ninController.text.trim() : null;
    setState(() => _isCreatingAccount = true);
    try {
      final accounts = await VirtualAccountService.createVirtualAccount(bvn: bvn, nin: nin);
      setState(() { bankAccounts = accounts; errorMessage = null; });
      await _cacheData();
      _animationController.forward();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Virtual account created successfully! 🎉'),
          backgroundColor: primaryPurple, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red[700], behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isCreatingAccount = false);
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && errorMessage != null) fetchBankAccounts(isBackground: true);
    });
  }

  Future<void> _copyToClipboard(String text, String accountNumber) async {
    await Clipboard.setData(ClipboardData(text: text));
    setState(() => _copiedAccountNumber = accountNumber);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedAccountNumber = null);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [Icon(Icons.check_circle, color: Colors.white, size: 16), SizedBox(width: 8), Text('Account number copied!')]),
        backgroundColor: primaryPurple, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 48,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: primaryPurple, size: 18), onPressed: () => Navigator.pop(context)),
        title: const Text('Fund Wallet', style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        actions: [
          if (isRefreshing)
            const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primaryPurple)))
          else
            IconButton(icon: const Icon(Icons.refresh, color: primaryPurple, size: 20), onPressed: () => fetchBankAccounts(isBackground: true)),
        ],
      ),
      body: isLoading
          ? _buildSkeleton()
          : errorMessage != null
          ? _buildErrorWidget()
          : bankAccounts.isEmpty
          ? _buildEmptyState()
          : FadeTransition(
        opacity: _fadeAnimation,
        child: RefreshIndicator(
          color: primaryPurple,
          onRefresh: () => fetchBankAccounts(isBackground: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildHeaderCard(),
              const SizedBox(height: 14),
              _buildNoticeCard(),
              const SizedBox(height: 18),
              _buildAccountsHeader(),
              const SizedBox(height: 12),
              ...bankAccounts.map(_buildBankAccountCard),
              const SizedBox(height: 18),
              _buildInstructionsCard(),
              const SizedBox(height: 18),
              _buildSupportSection(),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [primaryPurple, primaryBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: primaryPurple.withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(children: [
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.account_balance, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Text('Bank Transfer', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Transfer to any account below to fund your wallet instantly',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
        ),
      ]),
    );
  }

  Widget _buildNoticeCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryPurple.withOpacity(0.2))),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: primaryPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.info_outline, color: primaryPurple, size: 16)),
        const SizedBox(width: 10),
        const Expanded(child: Text('Transfer the exact amount you want to credit. Your wallet will be funded automatically.', style: TextStyle(fontSize: 12, color: darkText, height: 1.4))),
      ]),
    );
  }

  Widget _buildAccountsHeader() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Your Account Numbers', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: darkText)),
      const SizedBox(height: 3),
      Text('Tap the account number to copy it', style: TextStyle(fontSize: 11, color: lightText)),
    ]);
  }

  Widget _buildBankAccountCard(Map<String, dynamic> account) {
    final accountNumber = account['accountNumber']?.toString() ?? 'N/A';
    final bankName      = account['bankName']?.toString() ?? 'Unknown Bank';
    final accountName   = 'A and M Enterprises — ${account['accountName']?.toString() ?? fullName ?? ''}';
    final isCopied      = _copiedAccountNumber == accountNumber;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))],
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(children: [
        // Bank header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [primaryPurple.withOpacity(0.08), Colors.transparent], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: primaryPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.account_balance, color: primaryPurple, size: 17)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bankName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 1),
              Text(accountName, style: TextStyle(fontSize: 11, color: lightText), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            // ₦50 charge badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.amber.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.receipt, color: Colors.amber[800], size: 12),
                const SizedBox(width: 3),
                Text('₦50 fee', style: TextStyle(color: Colors.amber[800], fontWeight: FontWeight.w600, fontSize: 10)),
              ]),
            ),
          ]),
        ),

        // Account number — full tappable row
        GestureDetector(
          onTap: () => _copyToClipboard(accountNumber, accountNumber),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: isCopied ? primaryPurple.withOpacity(0.05) : Colors.transparent,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Account Number', style: TextStyle(fontSize: 10, color: lightText, letterSpacing: 0.3)),
                const SizedBox(height: 4),
                Text(
                  accountNumber,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isCopied ? primaryPurple : darkText, letterSpacing: 3),
                ),
              ])),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isCopied ? primaryPurple : primaryPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(isCopied ? Icons.check_rounded : Icons.copy_rounded, color: isCopied ? Colors.white : primaryPurple, size: 15),
                  const SizedBox(width: 5),
                  Text(isCopied ? 'Copied!' : 'Copy', style: TextStyle(color: isCopied ? Colors.white : primaryPurple, fontWeight: FontWeight.w600, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildInstructionsCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey[200]!)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('📌 How it works', style: TextStyle(fontWeight: FontWeight.bold, color: darkText, fontSize: 14)),
        const SizedBox(height: 12),
        _instructionItem(1, 'Tap the account number to copy it'),
        _instructionItem(2, 'Open your bank app and make a transfer'),
        _instructionItem(3, 'Your wallet is credited instantly'),
        _instructionItem(4, 'Minimum deposit: ₦100  ·  Fee: ₦50 per transfer'),
      ]),
    );
  }

  Widget _instructionItem(int n, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(color: primaryPurple.withOpacity(0.1), shape: BoxShape.circle),
        child: Center(child: Text('$n', style: const TextStyle(color: primaryPurple, fontWeight: FontWeight.bold, fontSize: 11))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: darkText))),
    ]),
  );

  Widget _buildSupportSection() {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactUsScreen())),
        child: Column(children: [
          Text('Need help funding your wallet?', style: TextStyle(color: lightText, fontSize: 12)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(30)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.headset_mic, color: primaryPurple, size: 16),
              SizedBox(width: 7),
              Text('Contact Support', style: TextStyle(color: primaryPurple, fontWeight: FontWeight.w600, fontSize: 13)),
              SizedBox(width: 4),
              Icon(Icons.arrow_forward, color: primaryPurple, size: 14),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Empty state — generate virtual account ────────────────────────────────

  Widget _buildEmptyState() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: lightPurple, shape: BoxShape.circle),
            child: const Icon(Icons.account_balance_outlined, size: 52, color: primaryPurple),
          ),
          const SizedBox(height: 20),
          const Text('Generate Virtual Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
          const SizedBox(height: 6),
          Text('Enter your BVN or NIN to create your personal bank account numbers.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: lightText, height: 1.5)),
          const SizedBox(height: 24),

          // BVN / NIN pill toggle
          Container(
            decoration: BoxDecoration(color: lightPurple, borderRadius: BorderRadius.circular(30)),
            child: Row(children: ['bvn', 'nin'].map((type) {
              final selected = _idType == type;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _idType = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(color: selected ? primaryPurple : Colors.transparent, borderRadius: BorderRadius.circular(30)),
                    child: Text(type.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(color: selected ? Colors.white : primaryPurple, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              );
            }).toList()),
          ),

          const SizedBox(height: 14),

          // Input field
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))]),
            child: TextField(
              controller: _idType == 'bvn' ? _bvnController : _ninController,
              keyboardType: TextInputType.number,
              maxLength: 11,
              style: const TextStyle(fontSize: 14, color: darkText, letterSpacing: 1.5),
              decoration: InputDecoration(
                labelText: _idType == 'bvn' ? 'Enter your BVN' : 'Enter your NIN',
                labelStyle: const TextStyle(color: primaryPurple, fontSize: 13),
                hintText: '11-digit number',
                counterText: '',
                border: InputBorder.none,
                prefixIcon: Icon(_idType == 'bvn' ? Icons.credit_card : Icons.badge_outlined, color: primaryPurple, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Privacy note inline
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.lock_outline, size: 12, color: lightText),
            const SizedBox(width: 5),
            Text('Your details are encrypted and secure', style: TextStyle(fontSize: 11, color: lightText)),
          ]),

          const SizedBox(height: 20),

          // Generate button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isCreatingAccount ? null : _createVirtualAccount,
              icon: _isCreatingAccount
                  ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add_circle_outline, size: 18),
              label: Text(_isCreatingAccount ? 'Creating Account…' : 'Generate Virtual Account', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPurple, foregroundColor: Colors.white,
                disabledBackgroundColor: primaryPurple.withOpacity(0.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 4, shadowColor: primaryPurple.withOpacity(0.4),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // What happens next explainer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('What happens next?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: darkText)),
              const SizedBox(height: 8),
              _explainerItem(Icons.person_outline, 'We verify your identity securely'),
              _explainerItem(Icons.account_balance, 'You receive personal bank account numbers'),
              _explainerItem(Icons.bolt_rounded, 'Transfer money to fund your wallet instantly'),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _explainerItem(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(children: [
      Icon(icon, size: 15, color: primaryPurple),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: lightText))),
    ]),
  );

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.cloud_off_rounded, size: 56, color: lightText),
          const SizedBox(height: 16),
          Text(errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: lightText, fontSize: 13)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: fetchBankAccounts,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Try Again', style: TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(backgroundColor: primaryPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11)),
          ),
        ]),
      ),
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 20), children: [
        Container(height: 88,  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18))),
        const SizedBox(height: 14),
        Container(height: 48,  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
        const SizedBox(height: 18),
        Container(height: 16,  width: 180, color: Colors.white),
        const SizedBox(height: 6),
        Container(height: 12,  width: 140, color: Colors.white),
        const SizedBox(height: 14),
        ...List.generate(2, (_) => Container(margin: const EdgeInsets.only(bottom: 12), height: 110, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)))),
        const SizedBox(height: 6),
        Container(height: 100, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
      ]),
    );
  }
}