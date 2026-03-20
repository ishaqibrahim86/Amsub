import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'buy_data_screen.dart';
import 'buy_airtime_screen.dart';
import 'buy_electricity_screen.dart';
import 'buy_cable_screen.dart';
import 'transactions_screen.dart';
import 'history_screen.dart';
import 'bonus_screen.dart';
import 'bulk_sms_screen.dart';
import 'airtime_to_cash_screen.dart';
import 'result_checker_screen.dart';
import 'data_coupon_screen.dart';
import 'recharge_card_screen.dart';
import 'fund_wallet_screen.dart';
import 'notifications_screen.dart';
import 'dart:async';
import '../widgets/banner_carousel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/user_balance_provider.dart';

class DashboardScreen extends StatefulWidget {
  final String? userEmail;
  const DashboardScreen({super.key, this.userEmail});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue   = const Color(0xFF3B82F6);
  final Color lightPurple   = const Color(0xFFF0EEFF);
  final Color darkText      = const Color(0xFF1E293B);
  final Color lightText     = const Color(0xFF64748B);

  String? fullName;
  String? username;
  String? phone;
  String? email;

  bool isLoading              = true;
  bool _balancesHidden        = false;
  bool hasUnreadNotification  = false;
  String? notificationMessage;
  String? alertMessage;

  List<Map<String, dynamic>> banners = [];
  int _currentBannerIndex    = 0;
  Timer? _bannerTimer;
  Timer? _refreshTimer;
  PageController? _pageController;
  bool _isPageViewReady      = false;

  // ←←← REAL-TIME LISTENER FOR BELL ICON
  late final ValueNotifier<bool> _unreadNotifier;

  // ── Helpers ───────────────────────────────────────────────────────────────

  String getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String get _masked => '₦ ••••••';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _unreadNotifier = NotificationStore.hasUnreadNotifier;
    _unreadNotifier.addListener(_onUnreadChanged);

    loadCachedDashboard();
    fetchAccountDetails();
    _fetchAlert();
    _syncUnreadDot();
  }

  @override
  void dispose() {
    _unreadNotifier.removeListener(_onUnreadChanged);
    WidgetsBinding.instance.removeObserver(this);
    _bannerTimer?.cancel();
    _refreshTimer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  void _onUnreadChanged() {
    if (mounted) {
      setState(() => hasUnreadNotification = _unreadNotifier.value);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _bannerTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (hasValidBanners && _isPageViewReady) _startBannerAutoScroll();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Provider.of<UserBalanceProvider>(context, listen: false).refresh();
      });
      _syncUnreadDot();
    }
  }

  // Sync red dot with persisted unread state (updates notifier → listener)
  Future<void> _syncUnreadDot() async {
    final unread = await NotificationStore.hasUnread();
    if (mounted) {
      _unreadNotifier.value = unread;
    }
  }

  // ── Banner helpers ────────────────────────────────────────────────────────

  void _startBannerAutoScroll() {
    if (!hasValidBanners || validBanners.length <= 1) return;
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || _pageController == null || !_isPageViewReady) return;
      try {
        int next = _currentBannerIndex + 1;
        if (next >= validBanners.length) next = 0;
        _pageController?.animateToPage(next, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      } catch (_) { timer.cancel(); }
    });
  }

  String getFullImageUrl(String path) {
    if (path.isEmpty) return '';
    String p = path;
    while (p.endsWith(',') || p.endsWith('"') || p.endsWith("'") || p.endsWith('}') || p.endsWith(']')) {
      p = p.substring(0, p.length - 1);
    }
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.startsWith('/media/') || p.startsWith('/')) return 'https://amsubnig.com$p';
    return 'https://amsubnig.com/media/adsbanner/$p';
  }

  bool get hasValidBanners => banners.any((b) => (b['banner'] ?? '').isNotEmpty);
  List<Map<String, dynamic>> get validBanners =>
      banners.where((b) => (b['banner'] ?? '').isNotEmpty).toList();

  // ── Data fetching ─────────────────────────────────────────────────────────

  Future<void> loadCachedDashboard() async {
    final prefs  = await SharedPreferences.getInstance();
    final cache  = prefs.getString('dashboard_cache');
    if (cache == null) return;

    final data = jsonDecode(cache);
    if (!mounted) return;

    setState(() {
      fullName            = data['fullName'];
      username            = data['username'];
      phone               = data['phone'];
      email               = data['email'];
      notificationMessage = data['notification'];
      banners = (data['banners'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
      isLoading = false;
    });

    final balanceProvider = Provider.of<UserBalanceProvider>(context, listen: false);
    balanceProvider.updateBalance(data['balance'] ?? 0.0, data['bonus'] ?? 0.0);
  }

  Future<http.Response> safeApiCall(Uri url, Map<String, String> headers) async {
    try {
      return await http.get(url, headers: headers).timeout(const Duration(seconds: 15));
    } catch (_) {
      await Future.delayed(const Duration(seconds: 2));
      return await http.get(url, headers: headers);
    }
  }

  Future<void> fetchAccountDetails() async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) return;

      final response = await safeApiCall(
        Uri.parse('https://amsubnig.com/api/user/'),
        {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) return;

      final data             = jsonDecode(response.body);
      final userData         = data['user'];
      final notificationData = data['notification'];
      final bannersData      = data['banners'];

      final newFullName  = userData?['FullName']   as String?;
      final newUsername  = userData?['username']   as String?;
      final newPhone     = userData?['Phone']      as String?;
      final newEmail     = userData?['email']      as String?;
      final newBalance   = double.tryParse(userData?['Account_Balance']?.toString() ?? '0') ?? 0.0;
      final newBonus     = double.tryParse(userData?['bonus_balance']?.toString()   ?? '0') ?? 0.0;
      final newNotif     = notificationData?['message'] as String?;

      List<Map<String, dynamic>> newBanners = [];
      if (bannersData is List) newBanners = List<Map<String, dynamic>>.from(bannersData);

      for (var b in newBanners) {
        final url = getFullImageUrl(b['banner'] ?? '');
        if (url.isNotEmpty && mounted) precacheImage(NetworkImage(url), context);
      }

      // Persist notification
      if (newNotif != null && newNotif.trim().isNotEmpty) {
        await NotificationStore.addNotification(newNotif);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dashboard_cache', jsonEncode({
        'fullName': newFullName, 'username': newUsername,
        'phone': newPhone, 'email': newEmail,
        'balance': newBalance, 'bonus': newBonus,
        'notification': newNotif, 'banners': newBanners,
      }));

      if (!mounted) return;

      setState(() {
        fullName            = newFullName;
        username            = newUsername;
        phone               = newPhone;
        email               = newEmail;
        notificationMessage = newNotif;
        banners             = newBanners;
        isLoading           = false;
      });

      final balanceProvider = Provider.of<UserBalanceProvider>(context, listen: false);
      balanceProvider.updateBalance(newBalance, newBonus);

      // Sync red dot via notifier
      await _syncUnreadDot();

      if (hasValidBanners) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _pageController ??= PageController();
          _isPageViewReady = true;
          _startBannerAutoScroll();
        });
      }
    } catch (e) { debugPrint('Dashboard fetch error: $e'); }
  }

  Future<void> _fetchAlert() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return;

      final response = await safeApiCall(
        Uri.parse('https://amsubnig.com/api/alert/'),
        {'Authorization': 'Token $token', 'Content-Type': 'application/json; charset=utf-8'},
      );

      if (response.statusCode == 200 && mounted) {
        final data    = jsonDecode(utf8.decode(response.bodyBytes));
        final message = data['alert'] as String?;
        if (message != null && message.trim().isNotEmpty) {
          _showAlertDialog(message);
        }
      }
    } catch (e) { debugPrint('Alert fetch error: $e'); }
  }

  // ── Alert as centered dialog ──────────────────────────────────────────────

  void _showAlertDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6B4EFF), Color(0xFF9B7DFF)]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 14),
              const Text('Announcement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.5)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(_),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4EFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Got it', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Notification bell (real-time via notifier) ────────────────────────────

  void _openNotifications() {
    _unreadNotifier.value = false; // clear dot instantly (listener updates UI)
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    ).then((_) => _syncUnreadDot());
  }

  // ── WhatsApp with personalised message ───────────────────────────────────

  Future<void> _openWhatsApp() async {
    const phoneNumber = '2348069450562';
    final uName  = username?.isNotEmpty == true ? username! : (fullName ?? 'a user');
    final uEmail = email?.isNotEmpty    == true ? email!    : 'not provided';

    final message = Uri.encodeComponent(
      'Hello AMSUBNIG Support Team,\n\n'
          'I need assistance with my account.\n\n'
          'Account Details:\n'
          '• Username: $uName\n'
          '• Email: $uEmail\n\n'
          'Please help me. Thank you.',
    );

    final appUri = Uri.parse('whatsapp://send?phone=$phoneNumber&text=$message');
    final webUri = Uri.parse('https://wa.me/$phoneNumber?text=$message');

    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Please install WhatsApp to chat with us'),
          backgroundColor: primaryPurple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  void _handleBannerTap(String route) {
    if (route.isEmpty) return;
    final bp = Provider.of<UserBalanceProvider>(context, listen: false);
    switch (route) {
      case '/datanet':   Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyDataScreen())); break;
      case '/airtimenet':Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyAirtimeScreen())); break;
      case '/cablename': Navigator.push(context, MaterialPageRoute(builder: (_) => const CablePaymentScreen())); break;
      case '/bill':      Navigator.push(context, MaterialPageRoute(builder: (_) => const ElectricityPaymentScreen())); break;
      case '/referal':
        Navigator.push(context, MaterialPageRoute(builder: (_) => BonusScreen(
          bonusBalance: bp.bonusBalance, mainBalance: bp.balance,
          onTransferSuccess: (v) => bp.updateBalance(v, bp.bonusBalance),
        )));
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Route: $route'), backgroundColor: primaryPurple));
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final displayName = fullName?.split(' ').first ?? 'User';
    final balanceProvider = Provider.of<UserBalanceProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 52,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [primaryPurple, primaryBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 7),
          Text('AMSUBNIG', style: TextStyle(color: primaryPurple, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        actions: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: hasUnreadNotification ? Colors.red.shade100 : lightPurple,
              borderRadius: BorderRadius.circular(28),
              boxShadow: hasUnreadNotification
                  ? [
                BoxShadow(
                  color: Colors.red.withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 3,
                )
              ]
                  : null,
            ),
            child: IconButton(
              icon: Icon(
                hasUnreadNotification
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: hasUnreadNotification
                    ? Colors.red.shade700
                    : primaryPurple,
                size: 24,
              ),
              onPressed: _openNotifications,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await fetchAccountDetails();
          await _fetchAlert();
          await balanceProvider.refresh();
        },
        color: primaryPurple,
        child: isLoading
            ? _buildSkeletonDashboard()
            : SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Greeting ────────────────────────────────────────────
              Text('${getGreeting()} 👋', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: lightText)),
              const SizedBox(height: 2),
              Text(displayName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryPurple)),

              const SizedBox(height: 16),

              // ── Wallet card ─────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [primaryPurple, primaryBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: primaryPurple.withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Balance row with eye toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Wallet Balance', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            _balancesHidden ? _masked : '₦ ${balanceProvider.balance.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                          ),
                        ]),
                        GestureDetector(
                          onTap: () => setState(() => _balancesHidden = !_balancesHidden),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                            child: Icon(_balancesHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: _buildWalletAction('Fund Wallet', Icons.add_circle_outline, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FundWalletScreen())))),
                      const SizedBox(width: 10),
                      Expanded(child: _buildWalletAction('History', Icons.history, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())))),
                    ]),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Referral balance card ───────────────────────────────
              GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => BonusScreen(
                    bonusBalance: balanceProvider.bonusBalance,
                    mainBalance: balanceProvider.balance,
                    onTransferSuccess: (v) => balanceProvider.updateBalance(v, balanceProvider.bonusBalance),
                  )));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: lightPurple,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(color: primaryPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.people_outline, color: primaryPurple, size: 17),
                        ),
                        const SizedBox(width: 10),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Referral Balance', style: TextStyle(color: lightText, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            _balancesHidden ? '₦ ••••••' : '₦ ${balanceProvider.bonusBalance.toStringAsFixed(2)}',
                            style: TextStyle(color: primaryPurple, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ]),
                      ]),
                      Icon(Icons.arrow_forward_ios, color: primaryPurple, size: 13),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // ── Features ────────────────────────────────────────────
              Text('Features', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: darkText)),
              const SizedBox(height: 12),

              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 16,
                childAspectRatio: 0.95,
                children: [
                  _buildFeatureItem('Data Bundle',    Icons.wifi,              primaryPurple,      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyDataScreen()))),
                  _buildFeatureItem('Airtime',        Icons.phone_android,     Colors.green,        () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyAirtimeScreen()))),
                  _buildFeatureItem('Electricity',    Icons.lightbulb,         Colors.amber,        () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ElectricityPaymentScreen()))),
                  _buildFeatureItem('Cable',          Icons.tv,                Colors.purple,       () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CablePaymentScreen()))),
                  _buildFeatureItem('Bulk SMS',       Icons.sms,               Colors.lightBlue,    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BulkSmsScreen()))),
                  _buildFeatureItem('Exams PIN',           Icons.school,            Colors.teal,         () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResultCheckerScreen()))),
                  _buildFeatureItem('Data Card Print',      Icons.print_sharp,          Colors.indigo,       () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataCouponScreen()))),
                  _buildFeatureItem('Recharge Card Print',      Icons.print_rounded,          Colors.pink,       () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RechargeCardScreen()))),
                  _buildFeatureItem('Airtime to Cash',Icons.currency_exchange, Colors.blue,         () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AirtimeToCashScreen()))),
                ],
              ),

              const SizedBox(height: 22),

              // ── Banners ─────────────────────────────────────────────
              if (validBanners.isNotEmpty) ...[
                Text('Promotions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: darkText)),
                const SizedBox(height: 12),
                BannerCarousel(
                  banners: validBanners,
                  buildUrl: getFullImageUrl,
                  onBannerTap: _handleBannerTap,
                ),
                const SizedBox(height: 22),
              ],

              // ── Footer tagline ──────────────────────────────────────
              Center(
                child: Column(children: [
                  Text('Grand Father of Data Vendors...', style: TextStyle(color: lightText, fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Container(width: 40, height: 2, decoration: BoxDecoration(color: primaryPurple.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
                ]),
              ),

              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
        height: 62, width: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: FloatingActionButton(
          onPressed: _openWhatsApp,
          backgroundColor: const Color(0xFF6B4EFF),
          elevation: 4,
          shape: const CircleBorder(),
          child: ClipOval(
            child: Image.asset('assets/images/whatsapp.png', width: 62, height: 62, fit: BoxFit.cover),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────

  Widget _buildSkeletonDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 18, width: 120, color: Colors.white),
            const SizedBox(height: 6),
            Container(height: 24, width: 160, color: Colors.white),
            const SizedBox(height: 16),
            Container(height: 130, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
            const SizedBox(height: 12),
            Container(height: 56, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
            const SizedBox(height: 22),
            Container(height: 16, width: 80, color: Colors.white),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 9,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 14, mainAxisSpacing: 16, childAspectRatio: 0.95),
              itemBuilder: (_, __) => Column(children: [
                Container(height: 48, width: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
                const SizedBox(height: 8),
                Container(height: 10, width: 44, color: Colors.white),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────

  Widget _buildWalletAction(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _buildFeatureItem(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: darkText)),
      ]),
    );
  }
}