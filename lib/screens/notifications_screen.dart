import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart'; // For ValueNotifier

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color primaryPurple = Color(0xFF6B4EFF);
  static const Color lightPurple   = Color(0xFFF0EEFF);
  static const Color darkText      = Color(0xFF1E293B);
  static const Color lightText     = Color(0xFF64748B);

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('notifications_history') ?? '[]';
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();

    // Mark all as read
    for (final n in list) {
      n['read'] = true;
    }
    await prefs.setString('notifications_history', jsonEncode(list));
    await prefs.setBool('has_unread_notification', false);

    // Notify listeners (bell icon disappears instantly)
    NotificationStore.hasUnreadNotifier.value = false;

    if (!mounted) return;
    setState(() {
      _notifications = list.reversed.toList();
      _isLoading = false;
    });
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All', style: TextStyle(fontSize: 15)),
        content: const Text('Remove all notifications?', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: lightText))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notifications_history', '[]');
      await prefs.setBool('has_unread_notification', false);
      NotificationStore.hasUnreadNotifier.value = false;
      setState(() => _notifications = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: darkText)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
        toolbarHeight: 48,
        iconTheme: const IconThemeData(color: primaryPurple),
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text('Clear all', style: TextStyle(color: Colors.red, fontSize: 12)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryPurple))
          : _notifications.isEmpty
          ? _buildEmpty()
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        itemCount: _notifications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildNotificationTile(_notifications[i]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: lightPurple, shape: BoxShape.circle),
            child: const Icon(Icons.notifications_none, size: 40, color: primaryPurple),
          ),
          const SizedBox(height: 16),
          const Text('No notifications yet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: darkText)),
          const SizedBox(height: 6),
          Text("You're all caught up!", style: TextStyle(fontSize: 12, color: lightText)),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> n) {
    final isUnread = n['read'] != true;
    final message = n['message']?.toString() ?? '';
    final time = n['timestamp']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isUnread ? lightPurple : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isUnread ? primaryPurple.withOpacity(0.25) : Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isUnread ? primaryPurple : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.notifications_active_outlined,
              color: isUnread ? Colors.white : lightText,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: TextStyle(fontSize: 13, color: darkText, fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal, height: 1.4)),
                if (time.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(time, style: TextStyle(fontSize: 10, color: lightText)),
                ],
              ],
            ),
          ),
          if (isUnread)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 4),
              decoration: const BoxDecoration(color: primaryPurple, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}

// ── NotificationStore with real-time listener ───────────────────────────────
class NotificationStore {
  static final ValueNotifier<bool> hasUnreadNotifier = ValueNotifier(false);

  static Future<void> addNotification(String message) async {
    if (message.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('notifications_history') ?? '[]';
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();

    if (list.any((n) => n['message'] == message)) return;

    list.add({
      'message': message,
      'read': false,
      'timestamp': _formatNow(),
    });

    final trimmed = list.length > 50 ? list.sublist(list.length - 50) : list;
    await prefs.setString('notifications_history', jsonEncode(trimmed));
    await prefs.setBool('has_unread_notification', true);

    hasUnreadNotifier.value = true; // ← Instant update for bell icon
  }

  static Future<bool> hasUnread() async {
    final prefs = await SharedPreferences.getInstance();
    final unread = prefs.getBool('has_unread_notification') ?? false;
    hasUnreadNotifier.value = unread;
    return unread;
  }

  static String _formatNow() {
    final now = DateTime.now();
    final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final m = now.minute.toString().padLeft(2, '0');
    final ap = now.hour >= 12 ? 'PM' : 'AM';
    return '${now.day}/${now.month}/${now.year}  $h:$m $ap';
  }
}