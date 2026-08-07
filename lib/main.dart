import 'package:flutter/material.dart';

import 'screens/home.dart';
import 'screens/setting.dart';
import 'screens/statistics.dart';
import 'theme.dart';

const List<String> _kTabTitles = ['통계', '홈', '설정'];

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
      appBar: _MainAppBar(title: _kTabTitles[_selectedIndex]),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: _MainBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onTabSelected,
      ),
    );
  }
}

/// 바탕색과 동일한 배경에 하단 구분선만 있는 상단바.
/// 가운데에는 현재 탭 이름만 표시한다.
class _MainAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _MainAppBar({required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      centerTitle: true,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: AppColors.textSecondary.withValues(alpha: 0.2), height: 1),
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
                        selected: currentIndex == 0,
                        onTap: () => onTap(0),
                      ),
                    ),
                    const SizedBox(width: _homeButtonSize),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.settings_rounded,
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
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  static const double _badgeSize = 40;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.primary : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: _badgeSize,
          height: _badgeSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}

/// 선택 시 원이 가운데에서부터 퍼져나가며 채워지는 홈 버튼.
class _HomeButton extends StatefulWidget {
  const _HomeButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  State<_HomeButton> createState() => _HomeButtonState();
}

class _HomeButtonState extends State<_HomeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fillController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    value: widget.selected ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _HomeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      if (widget.selected) {
        _fillController.forward();
      } else {
        _fillController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _fillController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: _MainBottomNavBar._homeButtonSize,
        height: _MainBottomNavBar._homeButtonSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.primaryContainer,
          border: Border.all(color: AppColors.background, width: 4),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipOval(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _fillController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: Curves.easeOut.transform(_fillController.value),
                      child: child,
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _fillController,
                builder: (context, child) {
                  final iconColor = Color.lerp(
                    colorScheme.primary,
                    colorScheme.onPrimary,
                    _fillController.value,
                  );
                  return Icon(
                    Icons.home_rounded,
                    color: iconColor,
                    size: 28,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
