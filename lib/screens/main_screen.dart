// screens/main_screen.dart (Animated Version)
import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'transactions_screen.dart';
import 'profile_screen.dart';
import 'history_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  // Brand colors
  final Color primaryPurple = const Color(0xFF6B4EFF);
  final Color primaryBlue = const Color(0xFF3B82F6);
  final Color lightPurple = const Color(0xFFF0EEFF);
  final Color darkText = const Color(0xFF1E293B);
  final Color lightText = const Color(0xFF64748B);

  int _selectedIndex = 0;
  late List<AnimationController> _animationControllers;
  late List<Animation<double>> _animations;

  static const List<Widget> _screens = <Widget>[
    DashboardScreen(),
    HistoryScreen(),
    TransactionsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _animationControllers = List.generate(4, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
    });

    _animations = _animationControllers.map((controller) {
      return Tween<double>(begin: 1.0, end: 1.2).animate(
        CurvedAnimation(parent: controller, curve: Curves.elasticInOut),
      );
    }).toList();

    // Start animation for initial selected index
    _animationControllers[_selectedIndex].forward();
  }

  @override
  void dispose() {
    for (var controller in _animationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;

    setState(() {
      // Reverse animation for previously selected item
      _animationControllers[_selectedIndex].reverse();

      // Start animation for newly selected item
      _selectedIndex = index;
      _animationControllers[_selectedIndex].forward();
    });
  }

  // Helper to get appropriate icon for each tab
  IconData _getIconForIndex(int index, {bool isSelected = false}) {
    switch (index) {
      case 0:
        return isSelected ? Icons.home : Icons.home_outlined;
      case 1:
        return isSelected ? Icons.history : Icons.history_outlined;
      case 2:
        return isSelected ? Icons.account_balance_wallet : Icons.account_balance_wallet_outlined;
      case 3:
        return isSelected ? Icons.person : Icons.person_outline;
      default:
        return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          child: BottomNavigationBar(
            items: List.generate(4, (index) {
              final isSelected = _selectedIndex == index;
              return BottomNavigationBarItem(
                icon: AnimatedBuilder(
                  animation: _animations[index],
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _animations[index].value,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getIconForIndex(index, isSelected: isSelected),
                            color: isSelected ? primaryPurple : lightText,
                            size: 24,
                          ),
                          const SizedBox(height: 2),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: isSelected ? 20 : 4,
                            height: 3,
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? LinearGradient(
                                colors: [primaryPurple, primaryBlue],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              )
                                  : null,
                              color: isSelected ? null : Colors.transparent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                label: _getLabelForIndex(index),
              );
            }),
            currentIndex: _selectedIndex,
            selectedItemColor: primaryPurple,
            unselectedItemColor: lightText,
            selectedLabelStyle: TextStyle(
              color: primaryPurple,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            unselectedLabelStyle: TextStyle(
              color: lightText,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
            onTap: _onItemTapped,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            elevation: 0,
            showSelectedLabels: true,
            showUnselectedLabels: true,
          ),
        ),
      ),
    );
  }

  String _getLabelForIndex(int index) {
    switch (index) {
      case 0:
        return 'Home';
      case 1:
        return 'History';
      case 2:
        return 'Wallet Summary';
      case 3:
        return 'Profile';
      default:
        return '';
    }
  }
}