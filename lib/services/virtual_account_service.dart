// services/virtual_account_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class VirtualAccountService {
  static const String _baseUrl = 'https://amsubnig.com';

  /// [bvn] or [nin] must be provided — not both required, but at least one.
  static Future<List<Map<String, dynamic>>> createVirtualAccount({
    String? bvn,
    String? nin,
  }) async {
    if ((bvn == null || bvn.isEmpty) && (nin == null || nin.isEmpty)) {
      throw Exception('Please provide your BVN or NIN');
    }

    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Session expired. Please login again.');
    }

    // Build body with whichever was provided
    final Map<String, String> body = {};
    if (nin != null && nin.isNotEmpty) {
      body['nin'] = nin;
    } else if (bvn != null && bvn.isNotEmpty) {
      body['bvn'] = bvn;
    }

    final response = await http
        .post(
      Uri.parse('$_baseUrl/api/create-virtual-account/'),
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    )
        .timeout(const Duration(seconds: 30));

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 || response.statusCode == 201) {
      final accounts = data['accounts'] as List?;
      return accounts
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ??
          [];
    }

    throw Exception(data['message'] ?? 'Could not create virtual account');
  }
}