import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _tokenKey = 'authToken';
  static String? _cachedToken; // ← in-memory cache

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    _cachedToken = token; // cache it
    print('Token saved & cached: ${token.substring(0, 10)}...');
  }

  static Future<String?> getToken() async {
    // Return cached value first (fast & reliable)
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      print('Returning cached token: ${_cachedToken!.substring(0, 10)}...');
      return _cachedToken;
    }

    // Fallback to storage
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    _cachedToken = token; // cache it for next calls
    print('Token read from storage & cached: ${token != null ? token.substring(0, 10) + "..." : "NULL"}');
    return token;
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _cachedToken = null;
    print('Token cleared & cache removed');
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    final loggedIn = token != null && token.isNotEmpty;
    print('isLoggedIn: $loggedIn');
    return loggedIn;
  }

  // Optional: call this on app start or after login to warm the cache
  static Future<void> warmCache() async {
    await getToken();
  }

  static Future<void> logout() async {
    await clearToken();
    print('User logged out successfully');
  }

}