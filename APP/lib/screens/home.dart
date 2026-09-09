import 'package:flutter/material.dart';

import '../connect.dart';
import '../device.dart';
import '../theme.dart';
import '../widget.dart';

/// 졸음감지 보안경(엣지 디바이스)과의 연결 상태를 보여주는 홈 화면.
/// 연결 상태는 DeviceConnection(connect.dart)에서 전역으로 관리한다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = DeviceConnection.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([connection, DeviceInfo.instance]),
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
          child: SizedBox(
            width: double.infinity,
            child: AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 100, // 홈화면 메인 카드 위아래 여백
              ),
              child: switch (connection.status) {
                ConnectionStatus.bluetoothOff => const _BluetoothOffView(),
                ConnectionStatus.bluetoothOn =>
                  const _DeviceDisconnectedView(),
                ConnectionStatus.deviceConnected => _DeviceInfoView(
                  deviceId: connection.deviceId,
                ),
              },
            ),
          ),
        );
      },
    );
  }
}

class _BluetoothOffView extends StatelessWidget {
  const _BluetoothOffView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.bluetooth_disabled_rounded,
          size: 64,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 16),
        Text('블루투스를 켜주세요', style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _DeviceDisconnectedView extends StatelessWidget {
  const _DeviceDisconnectedView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.bluetooth_searching_rounded,
          size: 64,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 16),
        Text('기기를 연결해주세요', style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

// TODO(bluetooth): 졸음 감지 신호 등 실제 데이터를 받아와 표시하는 화면으로
// 채운다. 지금은 기기 ID / 배터리 / 러닝타임만 보여주는 자리 표시 상태.
class _DeviceInfoView extends StatelessWidget {
  const _DeviceInfoView({required this.deviceId});

  final String? deviceId;

  @override
  Widget build(BuildContext context) {
    final deviceInfo = DeviceInfo.instance;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.bluetooth_connected_rounded,
          size: 64,
          color: AppColors.primary,
        ),
        const SizedBox(height: 16),
        Text('기기 정보', style: Theme.of(context).textTheme.titleMedium),
        if (deviceId != null) ...[
          const SizedBox(height: 4),
          Text(deviceId!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: 220,
          child: Row(
            children: [
              Expanded(
                child: Center(
                  child: _InfoStat(
                    icon: Icons.battery_full_rounded,
                    label: '${deviceInfo.batteryLevel}%',
                    iconColor: _batteryColor(deviceInfo.batteryLevel),
                  ),
                ),
              ),
              const SizedBox(
                height: 48,
                child: VerticalDivider(thickness: 1, color: Color(0x4D1A1C1E)),
              ),
              Expanded(
                child: Center(
                  child: _InfoStat(
                    icon: Icons.timer_outlined,
                    label: _formatDuration(deviceInfo.runningTime),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatDuration(Duration duration) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = two(duration.inHours);
    final minutes = two(duration.inMinutes.remainder(60));
    final seconds = two(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  static Color _batteryColor(int level) {
    if (level <= 10) return const Color(0xFFFF3B30);
    if (level < 30) return const Color(0xFFFF9500);
    return const Color(0xFF34C759);
  }
}

class _InfoStat extends StatelessWidget {
  const _InfoStat({
    required this.icon,
    required this.label,
    this.iconColor = AppColors.textSecondary,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 28, color: iconColor),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
