import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

// TODO(bluetooth): 실제 연동 시 기기 스캔/연결 실패 등 세부 상태가 늘어날 수 있음.
enum _ConnectionStatus { bluetoothOff, bluetoothOn, deviceConnected }

/// 졸음감지 보안경(엣지 디바이스)과의 연결 상태를 보여주는 홈 화면.
/// 블루투스 기능이 아직 없어 상태는 임시로 고정해두고, 실제 연동이 들어오면
/// _status를 플랫폼에서 읽어온 값으로 교체하면 된다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // TODO(bluetooth): 임시 로컬 상태. 실제 연동 시 블루투스 어댑터/기기 연결 스트림을
  // 구독해서 _status를 갱신하는 방식으로 교체한다 (예: StreamBuilder, Provider 등).
  _ConnectionStatus _status = _ConnectionStatus.bluetoothOff;

  // TODO(bluetooth): 실제 블루투스 연동 전까지, 디버그 빌드에서 화면을 탭하면
  // 상태가 순환하도록 만든 테스트용 임시 로직. 연동 코드가 들어오면
  // 이 메서드와 build()의 GestureDetector를 제거한다.
  void _debugCycleStatus() {
    if (!kDebugMode) return;
    setState(() {
      final next = (_status.index + 1) % _ConnectionStatus.values.length;
      _status = _ConnectionStatus.values[next];
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _debugCycleStatus,
      behavior: HitTestBehavior.translucent,
      child: Center(
        child: switch (_status) {
          _ConnectionStatus.bluetoothOff => const _BluetoothOffView(),
          _ConnectionStatus.bluetoothOn => const _DeviceDisconnectedView(),
          _ConnectionStatus.deviceConnected => const _DeviceInfoView(),
        },
      ),
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

// TODO(bluetooth): 연결된 기기 이름/배터리/졸음 감지 신호 등 실제 데이터를
// 받아와 표시하는 화면으로 채운다. 지금은 자리만 잡아둔 상태.
class _DeviceInfoView extends StatelessWidget {
  const _DeviceInfoView();

  @override
  Widget build(BuildContext context) {
    return Text('기기 정보', style: Theme.of(context).textTheme.titleMedium);
  }
}
