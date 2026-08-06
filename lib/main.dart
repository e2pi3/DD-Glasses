import 'package:flutter/material.dart';

import 'screens/home.dart';
import 'screens/setting.dart';
import 'screens/statistics.dart';
import 'theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DD Glasses',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const MainNavigation(),
    );
  }
}

/// 하단 네비게이션을 소유하는 루트 화면.
/// 탭 전환 시 하단바가 다시 그려지지 않도록 IndexedStack으로 화면을 유지한다.
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 1;

  static const List<Widget> _screens = [
    StatisticsScreen(),
    HomeScreen(),
    SettingScreen(),
  ];

  void _onTabSelected(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: _MainBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onTabSelected,
      ),
    );
  }
}

/// 통계 - 홈(돌출된 원형 버튼) - 설정 순서의 하단바.
/// 가운데 원형 홈 버튼을 중심으로 실린더(캡슐) 모양이 양옆으로 뻗어나가는 형태.
class _MainBottomNavBar extends StatelessWidget {
  const _MainBottomNavBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double _barHeight = 60;
  static const double _homeButtonSize = 72;
  static const double _horizontalMargin = 20;
  static const double _bottomMargin = 16;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      minimum: const EdgeInsets.only(bottom: _bottomMargin),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalMargin),
        child: SizedBox(
          height: _homeButtonSize,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                height: _barHeight,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(_barHeight / 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _NavItem(
                        icon: Icons.bar_chart_rounded,
                        label: '통계',
                        selected: currentIndex == 0,
                        onTap: () => onTap(0),
                      ),
                    ),
                    const SizedBox(width: _homeButtonSize),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.settings_rounded,
                        label: '설정',
                        selected: currentIndex == 2,
                        onTap: () => onTap(2),
                      ),
                    ),
                  ],
                ),
              ),
              _HomeButton(selected: currentIndex == 1, onTap: () => onTap(1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.primary : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  const _HomeButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _MainBottomNavBar._homeButtonSize,
        height: _MainBottomNavBar._homeButtonSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? colorScheme.primary : colorScheme.primaryContainer,
          border: Border.all(color: AppColors.background, width: 4),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          Icons.home_rounded,
          color: selected ? colorScheme.onPrimary : colorScheme.primary,
          size: 28,
        ),
      ),
    );
  }
}
