// screens/app_wrapper.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart'; // Add this import
import 'main_screen.dart';
import 'lock_screen.dart';
import '../services/auth_service.dart';
import '../providers/user_balance_provider.dart'; // Add this import

class AppWrapper extends StatefulWidget {
  final Widget child;

  const AppWrapper({Key? key, required this.child}) : super(key: key);

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> with WidgetsBindingObserver {
  bool _isLocked = false;
  bool _isAuthenticated = false;
  bool _lockEnabled = true; // Default to true

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialLockState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkInitialLockState() async {
    final prefs = await SharedPreferences.getInstance();
    // Get lock setting, default to true if not set
    final lockEnabled = prefs.getBool('lock_enabled') ?? true;
    final isLoggedIn = await AuthService.isLoggedIn();

    print('=== INITIAL LOCK STATE CHECK ===');
    print('Lock enabled (default true): $lockEnabled');
    print('Is logged in: $isLoggedIn');

    setState(() {
      _lockEnabled = lockEnabled;
    });

    if (lockEnabled && isLoggedIn && mounted) {
      setState(() {
        _isLocked = true;
        _isAuthenticated = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('=== APP LIFECYCLE STATE CHANGED ===');
    print('New state: $state');

    if (state == AppLifecycleState.paused) {
      // App is going to background
      _lockApp();
    } else if (state == AppLifecycleState.resumed) {
      // App is coming to foreground
      _checkIfShouldShowLock();
    }
  }

  Future<void> _lockApp() async {
    final prefs = await SharedPreferences.getInstance();
    // Get current lock setting
    final lockEnabled = prefs.getBool('lock_enabled') ?? true; // Default to true
    final isLoggedIn = await AuthService.isLoggedIn();

    print('=== LOCKING APP ===');
    print('Lock enabled: $lockEnabled');
    print('Is logged in: $isLoggedIn');

    if (lockEnabled && isLoggedIn && mounted) {
      setState(() {
        _isLocked = true;
        _isAuthenticated = false;
        _lockEnabled = lockEnabled;
      });
    }
  }

  Future<void> _checkIfShouldShowLock() async {
    print('=== CHECKING IF SHOULD SHOW LOCK ===');
    print('Is locked: $_isLocked');
    print('Is authenticated: $_isAuthenticated');
    print('Lock enabled: $_lockEnabled');

    if (_isLocked && !_isAuthenticated && mounted) {
      print('Showing lock screen now');

      // Show lock screen as a dialog that covers the entire screen
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false, // User must authenticate
        builder: (BuildContext context) {
          return const Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: EdgeInsets.zero,
            child: LockScreen(),
          );
        },
      );

      if (result == true && mounted) {
        print('Authentication successful, unlocking app');
        setState(() {
          _isLocked = false;
          _isAuthenticated = true;
        });

        // Optional: Refresh balance when app is unlocked
        if (mounted) {
          final balanceProvider = Provider.of<UserBalanceProvider>(context, listen: false);
          balanceProvider.refresh();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If locked and not authenticated, show a scaffold with lock screen
    if (_isLocked && !_isAuthenticated) {
      return Scaffold(
        body: LockScreen(
          onUnlock: () {
            print('Lock screen onUnlock called');
            setState(() {
              _isLocked = false;
              _isAuthenticated = true;
            });

            // Optional: Refresh balance when unlocked
            final balanceProvider = Provider.of<UserBalanceProvider>(context, listen: false);
            balanceProvider.refresh();
          },
        ),
      );
    }

    // Otherwise show the main content
    return widget.child;
  }
}