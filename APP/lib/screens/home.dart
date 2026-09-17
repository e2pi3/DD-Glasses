import 'package:flutter/material.dart';

import '../ble_protocol.dart';
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
                ConnectionStatus.bluetoothOn => _DeviceDisconnectedView(
                  errorMessage: connection.errorMessage,
                  onConnect: connection.connectToGlasses,
                ),
                ConnectionStatus.scanning => const _ProgressView(
                  message: '기기를 찾는 중...',
                ),
                ConnectionStatus.connecting => const _ProgressView(
                  message: '기기에 연결하는 중...',
                ),
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
  const _DeviceDisconnectedView({
    required this.errorMessage,
    required this.onConnect,
  });

  final String? errorMessage;
  final VoidCallback onConnect;

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
        if (errorMessage != null) ...[
          const SizedBox(height: 4),
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onConnect,
          icon: const Icon(Icons.bluetooth_rounded),
          label: Text(errorMessage == null ? '기기 연결' : '다시 시도'),
        ),
      ],
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 64,
          height: 64,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
        ),
        const SizedBox(height: 16),
        Text(message, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

/// 연결된 기기의 실시간 눈 상태와 배터리 / 러닝타임을 보여준다.
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
        const SizedBox(height: 20),
        _EyeStateBadge(eyeState: deviceInfo.eyeState),
        const SizedBox(height: 20),
        SizedBox(
          width: 220,
          child: Row(
            children: [
              Expanded(
                child: Center(
                  child: _InfoStat(
                    icon: Icons.battery_full_rounded,
                    label: deviceInfo.batteryLevel == null
                        ? '--%'
                        : '${deviceInfo.batteryLevel}%',
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

  static Color _batteryColor(int? level) {
    if (level == null) return AppColors.textSecondary;
    if (level <= 10) return const Color(0xFFFF3B30);
    if (level < 30) return const Color(0xFFFF9500);
    return const Color(0xFF34C759);
  }
}

/// 기기가 보낸 가장 최근 추론 결과(눈 뜸/감음)를 표시하는 배지.
class _EyeStateBadge extends StatelessWidget {
  const _EyeStateBadge({required this.eyeState});

  final EyeState? eyeState;

  @override
  Widget build(BuildContext context) {
    final state = eyeState;
    final (IconData icon, String label, Color color) = switch (state) {
      null => (
        Icons.hourglass_empty_rounded,
        '데이터 수신 대기 중',
        AppColors.textSecondary,
      ),
      EyeState(closed: true) => (
        Icons.visibility_off_rounded,
        '눈 감음',
        const Color(0xFFFF3B30),
      ),
      EyeState(closed: false) => (
        Icons.visibility_rounded,
        '눈 뜸',
        const Color(0xFF34C759),
      ),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (state != null) ...[
            const SizedBox(width: 6),
            Text(
              '${(state.closedProbability * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
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
