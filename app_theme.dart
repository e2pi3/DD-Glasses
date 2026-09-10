import 'package:flutter/material.dart';

/// 색은 초기 목업의 방향(어두운 그래파이트 + 앰버 한 가지 포인트)을 따릅니다.
/// 와이어프레임은 구조 확인용으로 무채색이었고, 시각 언어는 여기서 복원합니다.
class AppColors {
  static const graphite = Color(0xFF121212);
  static const surface = Color(0xFF1C1C1C);
  static const surfaceHigh = Color(0xFF262626);
  static const hairline = Color(0xFF333333);

  static const amber = Color(0xFFF5A623);
  static const amberDim = Color(0xFF7A5412);

  static const textPrimary = Color(0xFFF2F2F2);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF6B6B6B);

  static const danger = Color(0xFFE0402F);
  static const caution = Color(0xFFF5A623);
  static const ok = Color(0xFF4CAF7D);
}

/// 판정 단계. 초기 데이터가 없어 임계값이 미정이므로
/// [DrowsinessLevel.caution] 노출 여부는 설정에서 끌 수 있게 해두었습니다.
enum DrowsinessLevel { idle, warmup, normal, caution, danger }

extension DrowsinessLevelX on DrowsinessLevel {
  String get label => switch (this) {
        DrowsinessLevel.idle => '대기',
        DrowsinessLevel.warmup => '준비 중',
        DrowsinessLevel.normal => '정상',
        DrowsinessLevel.caution => '주의',
        DrowsinessLevel.danger => '위험',
      };

  Color get color => switch (this) {
        DrowsinessLevel.idle => AppColors.textTertiary,
        DrowsinessLevel.warmup => AppColors.textSecondary,
        DrowsinessLevel.normal => AppColors.ok,
        DrowsinessLevel.caution => AppColors.caution,
        DrowsinessLevel.danger => AppColors.danger,
      };
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.amber,
    onPrimary: AppColors.graphite,
    secondary: AppColors.amber,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    error: AppColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.graphite,
    fontFamily: 'Pretendard',
    dividerColor: AppColors.hairline,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.graphite,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.amber.withOpacity(0.18),
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight:
              states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? AppColors.amber
              : AppColors.textTertiary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? AppColors.amber
              : AppColors.textTertiary,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.amber,
        foregroundColor: AppColors.graphite,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.graphite : AppColors.textTertiary),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.amber : AppColors.surfaceHigh),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.zero,
      titleTextStyle: TextStyle(fontSize: 14, color: AppColors.textPrimary),
      subtitleTextStyle: TextStyle(fontSize: 11, color: AppColors.textTertiary),
    ),
  );
}

const kLabelSmall = TextStyle(fontSize: 11, color: AppColors.textSecondary);
const kLabelTiny = TextStyle(fontSize: 10, color: AppColors.textTertiary);
const kMetricBig = TextStyle(
  fontSize: 40,
  fontWeight: FontWeight.w700,
  height: 1,
  letterSpacing: -1.2,
  color: AppColors.textPrimary,
);
const kMetricMid = TextStyle(
  fontSize: 24,
  fontWeight: FontWeight.w700,
  height: 1,
  color: AppColors.textPrimary,
);
