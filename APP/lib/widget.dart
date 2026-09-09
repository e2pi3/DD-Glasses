import 'package:flutter/material.dart';

import 'theme.dart';

/// 모서리가 둥근 사각형 카드 위에 배경과 구분되도록 콘텐츠를 띄우는 공용 컨테이너.
/// 화면 전반의 정보 블록(기기 연결 상태, 설정 항목 등)에서 재사용한다.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  static final BorderRadius _radius = BorderRadius.circular(20);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: _radius,
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// [showAppDialog]에 넘길 버튼 하나를 정의한다.
/// [isDestructive]가 true면 경고성 동작(연결 해제 등)임을 나타내는 강조 색으로 표시된다.
class AppDialogAction {
  const AppDialogAction({
    required this.label,
    this.onPressed,
    this.isDestructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;
}

/// 뒷배경을 어둡게 dim 처리하고 카드에 그림자를 줘서 떠 있는 느낌을 내는,
/// 안내 문구와 버튼들을 구분선으로 나눠 보여주는 공용 확인 팝업.
/// 문구([message])와 버튼 목록([actions])만 정하면 되고,
/// 버튼 개수에 따라 문구 아래 가로 구분선 + 버튼 사이 세로 구분선이 자동으로
/// 배치되어 T자 형태의 구분선을 이룬다.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String message,
  required List<AppDialogAction> actions,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierLabel: '',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _AppDialog(message: message, actions: actions);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AppDialog extends StatelessWidget {
  const _AppDialog({required this.message, required this.actions});

  final String message;
  final List<AppDialogAction> actions;

  static const double _cardWidth = 270;
  static const double _buttonHeight = 52;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Container(
            width: _cardWidth,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const Divider(height: 1, thickness: 1, color: AppColors.divider),
                  SizedBox(
                    height: _buttonHeight,
                    child: Row(
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0)
                            const VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: AppColors.divider,
                            ),
                          Expanded(
                            child: _AppDialogButton(action: actions[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppDialogButton extends StatelessWidget {
  const _AppDialogButton({required this.action});

  final AppDialogAction action;

  @override
  Widget build(BuildContext context) {
    final color = action.isDestructive
        ? Theme.of(context).colorScheme.error
        : AppColors.textPrimary;

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        action.onPressed?.call();
      },
      child: Center(
        child: Text(
          action.label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
