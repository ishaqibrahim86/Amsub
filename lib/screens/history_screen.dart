import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:gal/gal.dart';
import '../services/auth_service.dart';

class HistoryScreen extends StatefulWidget {
  final String? initialCategory;

  const HistoryScreen({super.key, this.initialCategory});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  // Brand colors
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue = const Color(0xFF3B82F6);
  final Color lightPurple = const Color(0xFFF0EEFF);
  final Color darkText = const Color(0xFF1E293B);
  final Color lightText = const Color(0xFF64748B);

  late TabController _tabController;

  final List<TransactionCategory> categories = [
    TransactionCategory(type: 'data', title: 'Data', icon: Icons.data_usage, endpoint: 'data', hasPagination: true),
    TransactionCategory(type: 'topup', title: 'Airtime', icon: Icons.phone_android, endpoint: 'topup', hasPagination: true),
    TransactionCategory(type: 'cablesub', title: 'Cablesub', icon: Icons.live_tv, endpoint: 'cablesub', hasPagination: true),
    TransactionCategory(type: 'paymentgateway', title: 'Payment', icon: Icons.payment, endpoint: 'history', hasPagination: true),
    TransactionCategory(type: 'electricity', title: 'Electricity', icon: Icons.electric_bolt, endpoint: 'billpayment', hasPagination: true),
    TransactionCategory(type: 'epin', title: 'Result', icon: Icons.assignment, endpoint: 'epin', hasPagination: true),
    TransactionCategory(type: 'rechargepin', title: 'Recharge Card', icon: Icons.card_giftcard, endpoint: 'rechargepin', hasPagination: true),
    TransactionCategory(type: 'sms', title: 'Bulk SMS', icon: Icons.sms, endpoint: 'sms', hasPagination: true),
    TransactionCategory(type: 'datarechargepin', title: 'Data Coupon', icon: Icons.sim_card, endpoint: 'datarechargepin', hasPagination: true),
  ];

  late Map<String, CategoryData> categoryDataMap;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    categoryDataMap = {for (var cat in categories) cat.type: CategoryData()};
    _tabController = TabController(length: categories.length, vsync: this);

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final currentCategory = categories[_tabController.index];
        final catData = categoryDataMap[currentCategory.type]!;
        if (catData.transactions.isEmpty && !catData.isLoading) {
          fetchCategoryTransactions(currentCategory, isRefresh: true);
        }
      }
    });

    if (widget.initialCategory != null) {
      final index = categories.indexWhere((cat) => cat.type == widget.initialCategory);
      if (index != -1) _tabController.index = index;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialCategory = categories[_tabController.index];
      fetchCategoryTransactions(initialCategory, isRefresh: true);
    });
  }

  @override
  void dispose() {
    for (var catData in categoryDataMap.values) {
      catData.scrollController.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  Future<void> fetchCategoryTransactions(TransactionCategory category, {bool isRefresh = false, String? url}) async {
    final catData = categoryDataMap[category.type]!;
    if (isRefresh) catData.reset();
    if (catData.isLoading || (!catData.hasMore && !isRefresh)) return;

    setState(() {
      catData.isLoading = true;
      catData.error = null;
    });

    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        setState(() { catData.error = 'No authentication token found'; catData.isLoading = false; });
        return;
      }

      String requestUrl;
      if (url != null) {
        requestUrl = url;
      } else {
        requestUrl = category.type == 'paymentgateway'
            ? 'https://amsubnig.com/api/history/'
            : 'https://amsubnig.com/api/${category.endpoint}/';
        if (!isRefresh && catData.nextPageUrl != null) {
          requestUrl = catData.nextPageUrl!;
        } else if (!isRefresh && catData.currentPage > 1) {
          requestUrl += '?page=${catData.currentPage}';
        }
      }

      final response = await http.get(Uri.parse(requestUrl), headers: {
        'Authorization': 'Token $token',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> results = [];
        String? nextUrl;

        if (data is Map) {
          if (category.type == 'paymentgateway' && data.containsKey('paymentgateway')) {
            results = data['paymentgateway'] ?? [];
            nextUrl = data['next'];
          } else {
            results = data['results'] ?? [];
            nextUrl = data['next'];
          }
        } else if (data is List) {
          results = data;
        }

        final newTransactions = results.map((item) => _formatTransaction(item, category.type)).toList();

        setState(() {
          if (isRefresh) {
            catData.transactions = newTransactions;
            catData.currentPage = 1;
          } else {
            catData.transactions.addAll(newTransactions);
            catData.currentPage++;
          }
          catData.nextPageUrl = nextUrl;
          catData.hasMore = nextUrl != null && nextUrl.isNotEmpty;
          catData.isLoading = false;
          catData.error = null;
        });
      } else if (response.statusCode == 401) {
        setState(() { catData.error = 'Session expired'; catData.isLoading = false; });
      } else {
        setState(() { catData.error = 'Error ${response.statusCode}'; catData.isLoading = false; });
      }
    } catch (e) {
      setState(() { catData.error = 'Network error'; catData.isLoading = false; });
    }
  }

  Map<String, dynamic> _formatTransaction(dynamic item, String type) {
    final map = item is Map ? Map<String, dynamic>.from(item) : {};

    String cleanAmount(String amount) {
      if (amount.isEmpty) return '0';
      String cleaned = amount.replaceAll(RegExp(r'[^0-9.-]'), '');
      return cleaned.isEmpty ? '0' : cleaned;
    }

    Map<String, dynamic> formatted = {
      'id': map['id'] ?? map['pk']?.toString() ?? '',
      'status': map['Status'] ?? map['status'] ?? 'Unknown',
      'date': map['create_date'] ?? map['created_on'] ?? map['created_at'] ?? '',
      'reference': map['ident'] ?? map['reference'] ?? map['ref'] ?? map['id']?.toString() ?? '',
      'raw_data': map,
      'type': type,
    };

    switch (type) {
      case 'topup':
        final purchasedAmount = map['amount']?.toString() ?? '0';
        final paidAmount = map['paid_amount']?.toString() ?? purchasedAmount;
        formatted.addAll({
          'title': '${map['plan_network'] ?? 'Airtime'} Topup',
          'subtitle': map['mobile_number'] ?? '',
          'purchased_amount': cleanAmount(purchasedAmount),
          'debited_amount': cleanAmount(paidAmount),
          'discount': (double.parse(cleanAmount(purchasedAmount)) - double.parse(cleanAmount(paidAmount))).toString(),
          'icon': Icons.phone_android,
        });
        break;
      case 'data':
        formatted.addAll({
          'title': '${map['plan_network'] ?? 'Data'} • ${map['plan_name'] ?? 'Plan'}',
          'subtitle': map['mobile_number'] ?? '',
          'amount': cleanAmount(map['plan_amount']?.toString().replaceAll('₦', '') ?? map['amount']?.toString() ?? '0'),
          'icon': Icons.data_usage,
          'api_response': map['api_response'],
        });
        break;
      case 'cablesub':
        formatted.addAll({
          'title': map['package'] ?? 'Cable Subscription',
          'subtitle': 'Smart Card: ${map['smart_card_number'] ?? ''}',
          'amount': cleanAmount(map['paid_amount']?.toString() ?? map['amount']?.toString() ?? '0'),
          'icon': Icons.live_tv,
          'customer_name': map['customer_name'],
        });
        break;
      case 'paymentgateway':
        formatted.addAll({
          'title': 'Funding via ${map['gateway']?.toString().toUpperCase() ?? 'Payment'}',
          'subtitle': map['reference'] ?? '',
          'amount': cleanAmount(map['amount']?.toString() ?? '0'),
          'icon': Icons.payment,
        });
        break;
      case 'electricity':
        formatted.addAll({
          'title': map['package'] ?? 'Electricity Bill',
          'subtitle': 'Meter: ${map['meter_number'] ?? ''}',
          'amount': cleanAmount(map['paid_amount']?.toString() ?? map['amount']?.toString() ?? '0'),
          'icon': Icons.electric_bolt,
          'customer_name': map['customer_name'],
          'token': map['token'] ?? 'No token generated',
          'meter_number': map['meter_number'],
          'customer_address': map['customer_address'],
          'has_token': map['token'] != null && map['token'].toString().isNotEmpty,
        });
        break;
      case 'epin':
        final pins = map['pins']?.toString() ?? '';
        formatted.addAll({
          'title': '${map['exam_name'] ?? 'Result'} Checker PIN',
          'subtitle': 'PIN: $pins',
          'amount': cleanAmount(map['amount']?.toString() ?? '0'),
          'quantity': map['quantity'] ?? 1,
          'icon': Icons.assignment,
          'pins': pins,
          'exam_name': map['exam_name'] ?? 'Result',
          'has_pin': pins.isNotEmpty,
        });
        break;
      case 'rechargepin':
        if (map.containsKey('data_pin') && map['data_pin'] is List && map['data_pin'].isNotEmpty) {
          final pinData = map['data_pin'].first;
          if (pinData is Map && pinData.containsKey('fields')) {
            final fields = pinData['fields'];
            formatted.addAll({
              'title': '${map['network_name'] ?? 'Recharge'} Card',
              'subtitle': 'PIN: ${fields['pin'] ?? ''}',
              'amount': cleanAmount(fields['amount']?.toString() ?? map['network_amount']?.toString() ?? '0'),
              'icon': Icons.card_giftcard,
              'serial': fields['serial'],
              'load_code': fields['load_code'],
            });
          }
        } else {
          formatted.addAll({
            'title': '${map['network_name'] ?? 'Recharge'} Card',
            'subtitle': 'PIN: ${map['pins'] ?? ''}',
            'amount': cleanAmount(map['network_amount']?.toString() ?? '0'),
            'icon': Icons.card_giftcard,
          });
        }
        break;
      case 'sms':
        if (map.containsKey('fields')) {
          final fields = map['fields'] ?? {};
          formatted.addAll({
            'title': 'Bulk SMS',
            'subtitle': 'To: ${fields['to'] ?? ''}',
            'amount': cleanAmount(fields['amount']?.toString() ?? '0'),
            'total_messages': fields['total'] ?? 0,
            'icon': Icons.sms,
            'sender': fields['sendername'],
            'message': fields['message'],
          });
        }
        break;
      case 'datarechargepin':
        if (map.containsKey('data_pins') && map['data_pins'] is List && map['data_pins'].isNotEmpty) {
          final pinData = map['data_pins'].first;
          if (pinData is Map && pinData.containsKey('fields')) {
            final fields = pinData['fields'];
            formatted.addAll({
              'title': '${map['plan_network'] ?? 'Data'} Coupon',
              'subtitle': 'PIN: ${fields['pin'] ?? ''}',
              'amount': cleanAmount(fields['amount']?.toString() ?? '0'),
              'icon': Icons.sim_card,
              'serial': fields['serial'],
              'load_code': fields['load_code'],
              'expire_date': fields['expire_date'],
            });
          }
        } else {
          formatted.addAll({
            'title': '${map['plan_network'] ?? 'Data'} Coupon',
            'subtitle': 'PIN: ${map['pins'] ?? ''}',
            'amount': cleanAmount(map['amount']?.toString() ?? '0'),
            'icon': Icons.sim_card,
          });
        }
        break;
    }

    return formatted;
  }

  String formatDate(String dateStr) {
    try {
      return DateFormat('yyyy-MM-dd – HH:mm').format(DateTime.parse(dateStr));
    } catch (e) {
      return dateStr;
    }
  }

  String formatCurrency(String amount) {
    try {
      if (amount.isEmpty) return '₦0';
      return '₦${NumberFormat('#,###.00', 'en_US').format(double.parse(amount))}';
    } catch (e) {
      return '₦$amount';
    }
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'successful': case 'success': case 'completed': return Colors.green;
      case 'failed': case 'error': case 'failure': return Colors.red;
      case 'processing': case 'pending': return Colors.orange;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Transactions',
          style: TextStyle(color: darkText, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: primaryPurple,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: primaryPurple),
            onPressed: () {
              final currentCategory = categories[_tabController.index];
              fetchCategoryTransactions(currentCategory, isRefresh: true);
            },
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: [
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: primaryPurple,
                  unselectedLabelColor: lightText,
                  indicatorColor: primaryPurple,
                  indicatorWeight: 3,
                  dividerColor: Colors.transparent,
                  tabs: categories.map((cat) => Tab(icon: Icon(cat.icon), text: cat.title)).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search transactions...',
                      hintStyle: TextStyle(color: lightText),
                      prefixIcon: Icon(Icons.search, size: 20, color: primaryPurple),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    ),
                    onChanged: (value) => setState(() => searchQuery = value.toLowerCase()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: categories.map((category) {
          final catData = categoryDataMap[category.type]!;
          return RefreshIndicator(
            color: primaryPurple,
            onRefresh: () => fetchCategoryTransactions(category, isRefresh: true),
            child: _buildTransactionList(category, catData),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTransactionList(TransactionCategory category, CategoryData catData) {
    if (catData.error != null && catData.transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: lightText),
              const SizedBox(height: 16),
              Text(catData.error!, style: TextStyle(color: lightText, fontSize: 16)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => fetchCategoryTransactions(category, isRefresh: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (catData.isLoading && catData.transactions.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(primaryPurple),
        ),
      );
    }

    final filteredTransactions = searchQuery.isEmpty
        ? catData.transactions
        : catData.transactions.where((tx) {
      return [tx['title'], tx['subtitle'], tx['reference'], tx['status']].join(' ').toLowerCase().contains(searchQuery);
    }).toList();

    if (filteredTransactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(category.icon, size: 64, color: lightText),
            const SizedBox(height: 16),
            Text(
              searchQuery.isEmpty ? 'No ${category.title} transactions' : 'No matches found',
              style: TextStyle(fontSize: 16, color: lightText),
            ),
            if (searchQuery.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => searchQuery = ''),
                child: Text('Clear search', style: TextStyle(color: primaryPurple)),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: catData.scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: filteredTransactions.length + (catData.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == filteredTransactions.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (catData.hasMore && !catData.isLoading) fetchCategoryTransactions(category);
          });
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildTransactionCard(filteredTransactions[index]);
      },
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final statusColor = getStatusColor(tx['status'] ?? '');
    final String displayAmount = tx.containsKey('purchased_amount')
        ? formatCurrency(tx['purchased_amount'])
        : formatCurrency(tx['amount']?.toString() ?? '0');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showTransactionDetails(tx),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: lightPurple,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(tx['icon'] ?? Icons.receipt, size: 20, color: primaryPurple),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tx['title'] ?? 'Transaction',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (tx['subtitle'] != null && tx['subtitle'].toString().isNotEmpty)
                          Text(tx['subtitle'],
                              style: TextStyle(fontSize: 13, color: lightText),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Electricity token
              if (tx['type'] == 'electricity' && tx['has_token'] == true) ...[
                _buildPinBox(
                  label: 'Token:',
                  value: tx['token'],
                  color: primaryPurple,
                ),
                const SizedBox(height: 8),
              ],

              // Exam result PIN
              if (tx['type'] == 'epin' && tx['has_pin'] == true) ...[
                _buildPinBox(
                  label: 'PIN:',
                  value: tx['pins'],
                  color: primaryPurple,
                ),
                const SizedBox(height: 8),
              ],

              // Data API response
              if (tx['type'] == 'data' && tx['api_response'] != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (tx['status']?.toLowerCase() == 'failed' ? Colors.red : primaryPurple).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tx['api_response'],
                    style: TextStyle(
                      fontSize: 12,
                      color: tx['status']?.toLowerCase() == 'failed' ? Colors.red : primaryPurple,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayAmount,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryPurple)),
                        const SizedBox(height: 4),
                        Text(formatDate(tx['date'] ?? ''),
                            style: TextStyle(fontSize: 12, color: lightText)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(tx['status'] ?? 'Unknown',
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Reusable PIN/Token box with copy button
  Widget _buildPinBox({required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: color,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied to clipboard'),
                    backgroundColor: primaryPurple,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.copy_rounded, size: 18, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTransactionDetails(Map<String, dynamic> tx) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: TransactionDetailsContent(
          transaction: tx,
          formatDate: formatDate,
          formatCurrency: formatCurrency,
          primaryPurple: primaryPurple,
          primaryBlue: primaryBlue,
          lightPurple: lightPurple,
          darkText: darkText,
          lightText: lightText,
        ),
      ),
    );
  }
}

class TransactionDetailsContent extends StatefulWidget {
  final Map<String, dynamic> transaction;
  final Function(String) formatDate;
  final Function(String) formatCurrency;
  final Color primaryPurple;
  final Color primaryBlue;
  final Color lightPurple;
  final Color darkText;
  final Color lightText;

  const TransactionDetailsContent({
    super.key,
    required this.transaction,
    required this.formatDate,
    required this.formatCurrency,
    required this.primaryPurple,
    required this.primaryBlue,
    required this.lightPurple,
    required this.darkText,
    required this.lightText,
  });

  @override
  State<TransactionDetailsContent> createState() => _TransactionDetailsContentState();
}

class _TransactionDetailsContentState extends State<TransactionDetailsContent> {
  final GlobalKey _captureKey = GlobalKey();
  bool _isSaving = false;

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'successful': case 'success': case 'completed': return Colors.green;
      case 'failed': case 'error': case 'failure': return Colors.red;
      case 'processing': case 'pending': return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'successful': case 'success': case 'completed': return Icons.check_circle_rounded;
      case 'failed': case 'error': case 'failure': return Icons.cancel_rounded;
      case 'processing': case 'pending': return Icons.hourglass_top_rounded;
      default: return Icons.help_rounded;
    }
  }

  Future<Uint8List?> _renderToBytes() async {
    final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _saveToGallery() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final pngBytes = await _renderToBytes();
      if (pngBytes == null) throw Exception('Render failed');

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/txn_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);

      final hasAccess = await Gal.hasAccess(toAlbum: false);
      if (!hasAccess) await Gal.requestAccess(toAlbum: false);

      await Gal.putImage(file.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('✅ Saved to gallery'),
          backgroundColor: widget.primaryPurple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Could not save image'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _captureAndShare() async {
    try {
      final pngBytes = await _renderToBytes();
      if (pngBytes == null || !mounted) return;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/transaction_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);
      if (!mounted) return;

      await Share.shareXFiles([XFile(file.path)], text: 'Transaction Details');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share image')));
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copied to clipboard'),
      backgroundColor: widget.primaryPurple,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    final status = tx['status'] ?? 'Unknown';
    final statusColor = _statusColor(status);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with brand gradient
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [widget.primaryPurple, widget.primaryBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(tx['icon'] ?? Icons.receipt_long, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tx['title'] ?? 'Transaction Details',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Scrollable body
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _captureKey,
                child: Container(
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status hero
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [statusColor.withOpacity(0.08), statusColor.withOpacity(0.02)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(_statusIcon(status), size: 44, color: statusColor),
                            const SizedBox(height: 6),
                            Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailSection('TRANSACTION DETAILS', _buildTypeRows(tx)),
                            const SizedBox(height: 8),
                            Divider(color: widget.lightText.withOpacity(0.2)),
                            const SizedBox(height: 8),
                            _buildDetailSection('META', [
                              _buildDetailRow('Date', widget.formatDate(tx['date'] ?? '')),
                              _buildDetailRow('Reference', tx['reference'] ?? ''),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Action buttons
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _captureAndShare,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: widget.primaryPurple),
                      foregroundColor: widget.primaryPurple,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _saveToGallery,
                    icon: _isSaving
                        ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(widget.primaryPurple),
                      ),
                    )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(_isSaving ? 'Saving…' : 'Save'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: widget.primaryPurple),
                      foregroundColor: widget.primaryPurple,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Close'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: widget.primaryPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTypeRows(Map<String, dynamic> tx) {
    final type = tx['type'] as String? ?? '';

    switch (type) {
      case 'topup':
        return [
          _buildDetailRow('Purchased', widget.formatCurrency(tx['purchased_amount'] ?? '0')),
          _buildDetailRow('Debited', widget.formatCurrency(tx['debited_amount'] ?? '0')),
          if (double.tryParse(tx['discount'] ?? '0') != null && double.parse(tx['discount'] ?? '0') > 0)
            _buildDetailRow('Discount', widget.formatCurrency(tx['discount']), valueColor: Colors.green),
          _buildDetailRow('Phone', tx['subtitle'] ?? ''),
        ];

      case 'electricity':
        return [
          _buildDetailRow('Amount', widget.formatCurrency(tx['amount']?.toString() ?? '0')),
          if (_isNotEmpty(tx['customer_name'])) _buildDetailRow('Customer', tx['customer_name']),
          if (_isNotEmpty(tx['meter_number'])) _buildDetailRow('Meter No.', tx['meter_number']),
          if (_isNotEmpty(tx['customer_address'])) _buildDetailRow('Address', tx['customer_address']),
          if (_isNotEmpty(tx['token'])) ...[
            const SizedBox(height: 12),
            _buildHighlightBox(
              label: 'ELECTRICITY TOKEN',
              value: tx['token'],
              color: widget.primaryPurple,
              onCopy: () => _copyToClipboard(tx['token'], 'Token'),
            ),
          ],
        ];

      case 'epin':
        return [
          _buildDetailRow('Amount', widget.formatCurrency(tx['amount']?.toString() ?? '0')),
          _buildDetailRow('Exam', tx['exam_name'] ?? ''),
          if (tx['quantity'] != null) _buildDetailRow('Quantity', tx['quantity'].toString()),
          if (_isNotEmpty(tx['pins'])) ...[
            const SizedBox(height: 12),
            _buildHighlightBox(
              label: 'RESULT CHECKER PIN',
              value: tx['pins'],
              color: widget.primaryPurple,
              onCopy: () => _copyToClipboard(tx['pins'], 'PIN'),
            ),
          ],
        ];

      case 'data':
        return [
          _buildDetailRow('Amount', widget.formatCurrency(tx['amount']?.toString() ?? '0')),
          if (_isNotEmpty(tx['subtitle'])) _buildDetailRow('Phone', tx['subtitle']),
          if (tx['api_response'] != null) ...[
            const SizedBox(height: 12),
            _buildSectionLabel('API RESPONSE'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (tx['status']?.toLowerCase() == 'failed' ? Colors.red : widget.primaryPurple).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                tx['api_response'],
                style: TextStyle(
                  fontSize: 12,
                  color: tx['status']?.toLowerCase() == 'failed' ? Colors.red : widget.primaryPurple,
                ),
              ),
            ),
          ],
        ];

      case 'rechargepin':
      case 'datarechargepin':
        return [
          _buildDetailRow('Amount', widget.formatCurrency(tx['amount']?.toString() ?? '0')),
          if (_isNotEmpty(tx['subtitle'])) _buildDetailRow('PIN Info', tx['subtitle'].toString().replaceAll('PIN: ', '')),
          if (_isNotEmpty(tx['serial'])) _buildDetailRow('Serial', tx['serial']),
          if (_isNotEmpty(tx['load_code'])) _buildDetailRow('Load Code', tx['load_code']),
          if (_isNotEmpty(tx['expire_date'])) _buildDetailRow('Expires', widget.formatDate(tx['expire_date'])),
        ];

      case 'sms':
        return [
          _buildDetailRow('Amount', widget.formatCurrency(tx['amount']?.toString() ?? '0')),
          if (tx['total_messages'] != null) _buildDetailRow('Messages', tx['total_messages'].toString()),
          if (_isNotEmpty(tx['sender'])) _buildDetailRow('Sender ID', tx['sender']),
          if (_isNotEmpty(tx['message'])) ...[
            const SizedBox(height: 12),
            _buildSectionLabel('MESSAGE'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.lightPurple,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                tx['message'],
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ];

      case 'cablesub':
        return [
          _buildDetailRow('Amount', widget.formatCurrency(tx['amount']?.toString() ?? '0')),
          if (_isNotEmpty(tx['customer_name'])) _buildDetailRow('Customer', tx['customer_name']),
          if (_isNotEmpty(tx['subtitle'])) _buildDetailRow('Smart Card', tx['subtitle'].toString().replaceAll('Smart Card: ', '')),
        ];

      case 'paymentgateway':
        return [
          _buildDetailRow('Amount', widget.formatCurrency(tx['amount']?.toString() ?? '0')),
          _buildDetailRow('Reference', tx['subtitle'] ?? tx['reference'] ?? ''),
        ];

      default:
        return [_buildDetailRow('Amount', widget.formatCurrency(tx['amount']?.toString() ?? '0'))];
    }
  }

  bool _isNotEmpty(dynamic value) => value != null && value.toString().trim().isNotEmpty;

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 11,
        color: widget.lightText,
        letterSpacing: 0.8,
      ),
    );
  }

  /// Highlighted box for tokens/PINs with copy button
  Widget _buildHighlightBox({
    required String label,
    required String value,
    required Color color,
    required VoidCallback onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.vpn_key_rounded, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: color,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Material(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onCopy,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 16, color: color),
                        const SizedBox(width: 4),
                        Text('Copy', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: widget.lightText,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        ...rows,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.grey),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                color: valueColor ?? widget.darkText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionCategory {
  final String type;
  final String title;
  final IconData icon;
  final String endpoint;
  final bool hasPagination;

  TransactionCategory({
    required this.type,
    required this.title,
    required this.icon,
    required this.endpoint,
    this.hasPagination = true,
  });
}

class CategoryData {
  List<Map<String, dynamic>> transactions = [];
  int currentPage = 1;
  String? nextPageUrl;
  bool hasMore = true;
  bool isLoading = false;
  String? error;
  late ScrollController scrollController;

  CategoryData() {
    scrollController = ScrollController();
  }

  void reset() {
    transactions.clear();
    currentPage = 1;
    nextPageUrl = null;
    hasMore = true;
    isLoading = false;
    error = null;
  }
}