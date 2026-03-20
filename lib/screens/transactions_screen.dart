import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../services/auth_service.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  List<Map<String, dynamic>> displayedTransactions = [];
  bool isLoading = false;
  bool isInitialLoading = true;
  bool isRefreshing = false;
  String? errorMessage;

  static const int pageSize = 20;
  int currentPage = 1;
  bool hasMore = true;
  int totalCount = 0;

  final ScrollController _scrollController = ScrollController();

  // Cache keys
  static const String _cacheKey = 'wallet_history_cache';
  static const String _cacheTimestampKey = 'wallet_history_timestamp';
  static const Duration _cacheDuration = Duration(seconds: 5);

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Debounce for scroll loading
  Timer? _scrollDebounceTimer;

  @override
  void initState() {
    super.initState();

    // Initialize animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    WidgetsBinding.instance.addObserver(this);

    // Load cached data immediately
    _loadCachedData();

    // Then fetch fresh data
    _fetchTransactions();

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollDebounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh when app returns to foreground if cache is stale
      _checkAndRefreshCache();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _scrollDebounceTimer?.cancel();
      _scrollDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (!isLoading && hasMore) _loadNextPage();
      });
    }
  }

  Future<void> _checkAndRefreshCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (now - timestamp > _cacheDuration.inMilliseconds) {
        _fetchTransactions(isBackground: true);
      }
    } catch (e) {
      debugPrint('Cache check error: $e');
    }
  }

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Use cache if fresh
      if (now - timestamp < _cacheDuration.inMilliseconds) {
        final cachedData = prefs.getString(_cacheKey);
        if (cachedData != null) {
          final data = jsonDecode(cachedData);
          final transactions = (data['transactions'] as List?)
              ?.map((item) => Map<String, dynamic>.from(item))
              .toList() ?? [];

          final cachedTotal = data['total_count'] ?? transactions.length;
          final cachedPage = data['current_page'] ?? 1;
          final cachedHasMore = data['has_more'] ?? (transactions.length < cachedTotal);

          setState(() {
            displayedTransactions = transactions;
            totalCount = cachedTotal;
            currentPage = cachedPage;
            hasMore = cachedHasMore;
            isInitialLoading = false;
          });

          _animationController.forward();
        }
      }
    } catch (e) {
      debugPrint('Cache load error: $e');
    }
  }

  Future<void> _cacheData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode({
        'transactions': displayedTransactions,
        'total_count': totalCount,
        'current_page': currentPage,
        'has_more': hasMore,
      }));
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Cache save error: $e');
    }
  }

  void _loadNextPage() {
    if (!hasMore || isLoading) return;

    setState(() => isLoading = true);

    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 100), () async {
      try {
        final apiResult = await _performApiFetch(currentPage + 1);

        if (!mounted) return;

        setState(() {
          displayedTransactions.addAll(apiResult['items'] as List<Map<String, dynamic>>);
          currentPage++;
          hasMore = apiResult['next'] != null;
          isLoading = false;
        });

        // Update cache with newly loaded pages
        _cacheData();
      } catch (e) {
        if (!mounted) return;
        setState(() => isLoading = false);
        debugPrint('Load next page error: $e');
      }
    });
  }

  // Safe API call with retry logic
  Future<http.Response> _safeApiCall(
      Future<http.Response> Function() apiCall, {
        int maxRetries = 2,
        Duration initialDelay = const Duration(seconds: 1),
      }) async {
    int attempt = 0;
    while (attempt < maxRetries) {
      try {
        return await apiCall().timeout(const Duration(seconds: 90));
      } catch (e) {
        attempt++;
        if (attempt == maxRetries) rethrow;
        await Future.delayed(initialDelay * (2 ^ (attempt - 1)));
      }
    }
    throw Exception('Max retries exceeded');
  }

  // New helper: perform paginated API fetch (optimized endpoint)
  Future<Map<String, dynamic>> _performApiFetch(int page) async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('No authentication token found. Please login again.');
    }

    final response = await _safeApiCall(() => http.get(
      Uri.parse(
        'https://amsubnig.com/api/wallet-summary/optimized/?page=$page&page_size=$pageSize&days=60',
      ),
      headers: {
        'Authorization': 'Token $token',
        'Accept': 'application/json',
      },
    ));

    if (response.statusCode == 200) {
      final rawData = jsonDecode(response.body);
      final results = rawData['results'] as List<dynamic>? ?? [];

      final newItems = await _processTransactions(results);

      return {
        'items': newItems,
        'count': rawData['count'] ?? 0,
        'next': rawData['next'],
        'total_pages': rawData['total_pages'] ?? 1,
      };
    } else {
      throw Exception(_getErrorMessage(response.statusCode));
    }
  }

  Future<void> _fetchTransactions({bool isRefresh = false, bool isBackground = false}) async {
    if (isRefresh) {
      setState(() {
        displayedTransactions.clear();
        currentPage = 1;
        hasMore = true;
        totalCount = 0;
        errorMessage = null;
        if (!isBackground) isInitialLoading = true;
      });
    }

    // Skip re-fetch if we already have data (unless it's a forced refresh or background stale check)
    if (!isRefresh && displayedTransactions.isNotEmpty && !isBackground) return;

    if (isBackground) {
      setState(() => isRefreshing = true);
    }

    try {
      final apiResult = await _performApiFetch(1);

      setState(() {
        displayedTransactions = apiResult['items'] as List<Map<String, dynamic>>;
        totalCount = apiResult['count'] as int;
        currentPage = 1;
        hasMore = apiResult['next'] != null;
        isInitialLoading = false;
        isRefreshing = false;
        errorMessage = null;
      });

      // Cache the fresh data
      _cacheData();
      _animationController.forward();
    } catch (e) {
      if (!isBackground) {
        final msg = e.toString().startsWith('Exception: ')
            ? e.toString().substring(11)
            : 'Network error. Please check your connection.';
        setState(() {
          errorMessage = msg;
          isInitialLoading = false;
          isRefreshing = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _processTransactions(List<dynamic> results) async {
    // Sort newest first
    results.sort((a, b) {
      final dateA = DateTime.tryParse(a['create_date']?.toString() ?? '') ?? DateTime.now();
      final dateB = DateTime.tryParse(b['create_date']?.toString() ?? '') ?? DateTime.now();
      return dateB.compareTo(dateA);
    });

    return results.map((item) {
      final map = item as Map<String, dynamic>;
      return _formatTransaction(map);
    }).toList();
  }

  Map<String, dynamic> _formatTransaction(Map<String, dynamic> map) {
    String fullDate = map['create_date']?.toString() ?? '';
    String datePart = '';
    String timePart = '';

    if (fullDate.isNotEmpty) {
      try {
        final dt = DateTime.parse(fullDate);
        datePart = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        timePart = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        final parts = fullDate.split('T');
        datePart = parts.isNotEmpty ? parts[0] : '';
        timePart = parts.length > 1 ? parts[1].substring(0, 5) : '';
      }
    }

    double amountValue = double.tryParse(map['amount']?.toString() ?? '0') ?? 0.0;
    double previousBalance = double.tryParse(map['previous_balance']?.toString() ?? '0') ?? 0.0;
    double afterBalance = double.tryParse(map['after_balance']?.toString() ?? '0') ?? 0.0;

    // Debit / Credit classification
    bool isDebit;
    String transactionType;
    final productLower = (map['product']?.toString() ?? '').toLowerCase();

    if (productLower.contains('refund') ||
        productLower.contains('cashback') ||
        productLower.contains('reversal') ||
        productLower.contains('admin funding') ||
        productLower.contains('deposit') ||
        productLower.contains('credit') ||
        productLower.contains('fund')) {
      isDebit = false;
      transactionType = 'Credit';
    } else if (productLower.contains('charge') ||
        productLower.contains('purchase') ||
        productLower.contains('withdrawal') ||
        productLower.contains('transfer') ||
        productLower.contains('payment') ||
        productLower.contains('debit') ||
        productLower.contains('data') ||
        productLower.contains('airtime') ||
        productLower.contains('topup')) {
      isDebit = true;
      transactionType = 'Debit';
    } else if (amountValue < 0) {
      isDebit = true;
      transactionType = 'Debit';
    } else {
      isDebit = false;
      transactionType = 'Credit';
    }

    return {
      'type': 'Wallet',
      'ident': map['ident']?.toString() ?? 'N/A',
      'product': map['product']?.toString() ?? 'Unknown',
      'amount': amountValue,
      'amount_display': amountValue.abs().toString(),
      'previous_balance': previousBalance,
      'after_balance': afterBalance,
      'previous_balance_display': previousBalance.toString(),
      'after_balance_display': afterBalance.toString(),
      'full_date': fullDate,
      'date': datePart,
      'time': timePart,
      'is_debit': isDebit,
      'transaction_type': transactionType,
      'status': 'Completed',
    };
  }

  String _getErrorMessage(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return 'Session expired. Please login again.';
    } else if (statusCode == 404) {
      return 'Wallet summary not found.';
    } else if (statusCode == 500) {
      return 'Server error. Please try again later.';
    }
    return 'Failed to load wallet history ($statusCode)';
  }

  String formatAmount(String amount) {
    try {
      final value = double.parse(amount);
      if (value == 0) return '0.00';
      return value.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (Match m) => '${m[1]},',
      );
    } catch (_) {
      return amount;
    }
  }

  // Loading skeleton for better UX
  Widget _buildSkeletonLoader() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Wallet History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF6B4EFF),
        actions: [
          if (isRefreshing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _fetchTransactions(isRefresh: true),
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF6B4EFF),
        onRefresh: () => _fetchTransactions(isRefresh: true, isBackground: true),
        child: isInitialLoading
            ? _buildSkeletonLoader()
            : errorMessage != null
            ? _buildErrorWidget()
            : displayedTransactions.isEmpty
            ? _buildEmptyWidget()
            : FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              // Info banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey[200],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${displayedTransactions.length} of $totalCount',
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                    if (hasMore)
                      Text('↓ Pull for more',
                          style: TextStyle(
                            color: const Color(0xFF6B4EFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          )),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: displayedTransactions.length + (hasMore && isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == displayedTransactions.length) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    return _buildTransactionCard(displayedTransactions[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: () => _fetchTransactions(isRefresh: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B4EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No transactions yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your wallet activity will appear here',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final isDebit = tx['is_debit'] as bool;
    final amountColor = isDebit ? Colors.red : Colors.green;
    final amountPrefix = isDebit ? '-₦' : '+₦';
    final amount = formatAmount(tx['amount_display'] as String);
    final prevBal = formatAmount(tx['previous_balance'].toString());
    final afterBal = formatAmount(tx['after_balance'].toString());

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showTransactionDetails(tx),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: product name + amount
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: amountColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isDebit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      color: amountColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx['product'] ?? 'Transaction',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 3),
                            Text(tx['date'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            const SizedBox(width: 10),
                            Icon(Icons.access_time_rounded, size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 3),
                            Text(tx['time'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Amount badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: amountColor.withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$amountPrefix$amount',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: amountColor),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Balance before → after
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.grey.shade100, Colors.grey.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    // Before
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('BEFORE', style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[500],
                              letterSpacing: 0.8
                          )),
                          const SizedBox(height: 4),
                          Text('₦$prevBal',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                        ],
                      ),
                    ),
                    // Arrow
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.arrow_forward_rounded, size: 20,
                          color: amountColor.withAlpha(180)),
                    ),
                    // After
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('AFTER', style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[500],
                              letterSpacing: 0.8
                          )),
                          const SizedBox(height: 4),
                          Text('₦$afterBal',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                                  color: isDebit ? Colors.red.shade700 : Colors.green.shade700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Footer: reference + type badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.receipt_rounded, size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Ref: ${tx['ident'] ?? 'N/A'}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: amountColor.withAlpha(18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tx['transaction_type'] ?? '',
                      style: TextStyle(fontSize: 11, color: amountColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionDetails(Map<String, dynamic> tx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TransactionDetailsSheet(
        transaction: tx,
        formatAmount: formatAmount,
      ),
    );
  }
}

// Bottom sheet for transaction details
class _TransactionDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final String Function(String) formatAmount;

  const _TransactionDetailsSheet({
    required this.transaction,
    required this.formatAmount,
  });

  @override
  Widget build(BuildContext context) {
    final isDebit = transaction['is_debit'] as bool;
    final amountColor = isDebit ? Colors.red : Colors.green;
    final amountPrefix = isDebit ? '-' : '+';
    final amount = formatAmount(transaction['amount_display'] as String);
    final prevBal = formatAmount(transaction['previous_balance'].toString());
    final afterBal = formatAmount(transaction['after_balance'].toString());

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: amountColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isDebit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    color: amountColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction['product'] ?? 'Transaction',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${transaction['date']} ${transaction['time']}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Amount
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: amountColor.withAlpha(8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: amountColor.withAlpha(30)),
            ),
            child: Column(
              children: [
                const Text('AMOUNT', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Text(
                  '$amountPrefix₦$amount',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: amountColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Balance changes
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _buildBalanceBox('BEFORE', '₦$prevBal', Colors.grey),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward, color: Colors.grey[400]),
                ),
                Expanded(
                  child: _buildBalanceBox('AFTER', '₦$afterBal', amountColor),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Reference
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('REFERENCE', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 6),
                SelectableText(
                  transaction['ident'] ?? 'N/A',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildBalanceBox(String label, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(30)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text(
            amount,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}