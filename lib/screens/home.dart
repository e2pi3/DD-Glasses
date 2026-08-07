import 'package:flutter/material.dart';

import '../connect.dart';
import '../theme.dart';

/// 졸음감지 보안경(엣지 디바이스)과의 연결 상태를 보여주는 홈 화면.
/// 연결 상태는 DeviceConnection(connect.dart)에서 전역으로 관리한다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = DeviceConnection.instance;

    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        return Center(
          child: switch (connection.status) {
            ConnectionStatus.bluetoothOff => const _BluetoothOffView(),
            ConnectionStatus.bluetoothOn => const _DeviceDisconnectedView(),
            ConnectionStatus.deviceConnected => _DeviceInfoView(
              deviceId: connection.deviceId,
            ),
          },
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

// TODO(bluetooth): 배터리/졸음 감지 신호 등 실제 데이터를 받아와 표시하는
// 화면으로 채운다. 지금은 기기 ID만 보여주는 자리 표시 상태.
class _DeviceInfoView extends StatelessWidget {
  const _DeviceInfoView({required this.deviceId});

  final String? deviceId;

  @override
  Widget build(BuildContext context) {
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
      ],
    );
  }
}
