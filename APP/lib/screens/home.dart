import 'package:flutter/material.dart';

import '../connect.dart';
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
      listenable: connection,
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

/// 기기가 연결되었음을 보여준다. 눈 상태/배터리/러닝타임 등은 다음 단계에서 추가한다.
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
        Text('연결됨', style: Theme.of(context).textTheme.titleMedium),
        if (deviceId != null) ...[
          const SizedBox(height: 4),
          Text(deviceId!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}
