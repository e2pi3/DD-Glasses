import 'package:flutter/material.dart';

import '../connect.dart';
import '../theme.dart';
import '../widget.dart';

/// 설정 화면.
/// 기기 연결 정보 칸은 고정 크기로 상단에 항상 표시하고, 굵은 구분선으로
/// 나머지 항목들과 분리한다. 기기가 연결된 상태일 때만 그 아래로
/// 기기 연결 해제 / 피드백 강도 조절 / 경고음 음량 설정 항목을 얇은 구분선과 함께 보여준다.
class SettingScreen extends StatelessWidget {
  const SettingScreen({super.key});

  static const _thinDivider = Divider(
    height: 1,
    thickness: 1,
    color: AppColors.divider,
  );
  static const _thickDivider = Divider(
    height: 8,
    thickness: 8,
    color: AppColors.divider,
  );

  @override
  Widget build(BuildContext context) {
    final connection = DeviceConnection.instance;

    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _DeviceInfoTile(connection: connection),
            _thickDivider,
            if (connection.isConnected) ...[
              _SettingTile(
                icon: Icons.bluetooth_disabled_rounded,
                title: '기기 연결 해제',
                onTap: () => showAppDialog(
                  context: context,
                  message: '연결을 해제하시겠습니까?',
                  actions: [
                    const AppDialogAction(label: '닫기'),
                    AppDialogAction(
                      label: '해제',
                      isDestructive: true,
                      onPressed: connection.disconnect,
                    ),
                  ],
                ),
              ),
              _thinDivider,
              _SettingTile(
                icon: Icons.tune_rounded,
                title: '피드백 강도 조절',
                onTap: () {},
              ),
              _thinDivider,
              _SettingTile(
                icon: Icons.volume_up_rounded,
                title: '경고음 음량 설정',
                onTap: () {},
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DeviceInfoTile extends StatelessWidget {
  const _DeviceInfoTile({required this.connection});

  final DeviceConnection connection;

  static const double _height = 112;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final connected = connection.isConnected;

    return SizedBox(
      height: _height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Icon(
              connected
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_rounded,
              color: connected ? colorScheme.primary : AppColors.textSecondary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    connected ? '연결된 기기' : '연결된 기기 없음',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (connected) ...[
                    const SizedBox(height: 4),
                    Text(
                      connection.deviceId ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.bodyMedium),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
