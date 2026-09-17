import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_protocol.dart';

enum ConnectionStatus {
  bluetoothOff,
  bluetoothOn,
  scanning,
  connecting,
  deviceConnected,
}

/// 졸음감지 보안경(엣지 디바이스)과의 연결 상태를 앱 전역에서 공유하는 매니저.
/// 홈/설정 화면이 같은 상태를 보고 갱신할 수 있도록 싱글턴으로 둔다.
///
/// 폰의 블루투스 어댑터 on/off는 [FlutterBluePlus.adapterState] 스트림을 구독해
/// 자동으로 반영하고, [connectToGlasses]로 DD-GLASSES를 스캔 → GATT 연결 →
/// proximity characteristic 구독까지 수행한다. 기기가 보내는 값은 [proximitySamples]
/// 스트림으로 내보내며 ProximityLog(sensor_log.dart)가 이를 받아 보관한다.
class DeviceConnection extends ChangeNotifier {
  DeviceConnection._() {
    _init();
  }

  static final DeviceConnection instance = DeviceConnection._();

  static const Duration _scanTimeout = Duration(seconds: 10);
  static const Duration _connectTimeout = Duration(seconds: 15);

  ConnectionStatus _status = ConnectionStatus.bluetoothOff;
  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.deviceConnected;

  String? _deviceId;
  String? get deviceId => _deviceId;

  /// 마지막 연결 시도가 실패한 이유. 새 시도를 시작하면 지워진다.
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final _proximityController = StreamController<int>.broadcast();
  Stream<int> get proximitySamples => _proximityController.stream;

  BluetoothDevice? _device;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSub;
  StreamSubscription<List<int>>? _proximityValueSub;

  Future<void> _init() async {
    await _ensureBluetoothPermissions();
    _adapterStateSub = FlutterBluePlus.adapterState.listen(
      _onAdapterStateChanged,
    );
  }

  // Android 12+(API 31+)에서는 어댑터 상태 조회/스캔/연결에 런타임 권한 승인이 필요하다.
  Future<bool> _ensureBluetoothPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return results.values.every((s) => s.isGranted);
  }

  void _setStatus(ConnectionStatus next) {
    if (next == _status) return;
    _status = next;
    notifyListeners();
  }

  void _onAdapterStateChanged(BluetoothAdapterState state) {
    if (state == BluetoothAdapterState.on) {
      if (_status == ConnectionStatus.bluetoothOff) {
        _setStatus(ConnectionStatus.bluetoothOn);
      }
      return;
    }
    if (_status == ConnectionStatus.bluetoothOff) return;
    // 어댑터가 꺼지면 OS가 연결을 끊으므로 로컬 상태만 정리한다.
    FlutterBluePlus.stopScan();
    _clearDevice();
    _errorMessage = null;
    _setStatus(ConnectionStatus.bluetoothOff);
  }

  /// DD-GLASSES를 스캔해서 처음 발견된 기기에 연결한다.
  Future<void> connectToGlasses() async {
    if (_status != ConnectionStatus.bluetoothOn) return;
    _errorMessage = null;

    if (!await _ensureBluetoothPermissions()) {
      _fail('블루투스 권한이 필요합니다');
      return;
    }

    _setStatus(ConnectionStatus.scanning);
    final BluetoothDevice? found;
    try {
      found = await _scanForGlasses();
    } catch (e) {
      _fail('기기 검색에 실패했습니다');
      debugPrint('BLE scan error: $e');
      return;
    }
    // 스캔 도중 블루투스가 꺼진 경우.
    if (_status != ConnectionStatus.scanning) return;
    if (found == null) {
      _fail('주변에서 기기를 찾지 못했습니다');
      return;
    }

    _setStatus(ConnectionStatus.connecting);
    try {
      await _connect(found);
    } catch (e) {
      debugPrint('BLE connect error: $e');
      await found.disconnect().catchError((_) {});
      _clearDevice();
      if (_status != ConnectionStatus.bluetoothOff) {
        _fail('기기 연결에 실패했습니다');
      }
    }
  }

  Future<BluetoothDevice?> _scanForGlasses() async {
    final completer = Completer<BluetoothDevice?>();
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isNotEmpty && !completer.isCompleted) {
        completer.complete(results.first.device);
        FlutterBluePlus.stopScan();
      }
    });
    FlutterBluePlus.cancelWhenScanComplete(sub);

    // 필터는 OR 조건이라 서비스 UUID나 이름 중 하나만 맞아도 결과로 들어온다.
    await FlutterBluePlus.startScan(
      withServices: [BleProtocol.proximityService],
      withNames: [BleProtocol.deviceName],
      timeout: _scanTimeout,
    );
    await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    if (!completer.isCompleted) completer.complete(null);
    return completer.future;
  }

  Future<void> _connect(BluetoothDevice device) async {
    _device = device;

    await device.connect(timeout: _connectTimeout, mtu: null);

    _deviceStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && _device == device) {
        _clearDevice();
        if (_status == ConnectionStatus.deviceConnected) {
          _setStatus(ConnectionStatus.bluetoothOn);
        }
      }
    });

    final services = await device.discoverServices();
    final proximityChar = _findChar(
      services,
      BleProtocol.proximityService,
      BleProtocol.proximityChar,
    );
    if (proximityChar != null) {
      _proximityValueSub = proximityChar.onValueReceived.listen((bytes) {
        final sample = ProximitySample.parse(bytes);
        if (sample != null) _proximityController.add(sample.value);
      });
      await proximityChar.setNotifyValue(true);
    }

    // 연결 과정 중 기기가 끊겼다면 connectionState 리스너가 이미 정리했다.
    if (_device != device) throw StateError('disconnected during setup');

    _deviceId = device.platformName.isNotEmpty
        ? '${device.platformName} (${device.remoteId.str})'
        : device.remoteId.str;
    _setStatus(ConnectionStatus.deviceConnected);
  }

  BluetoothCharacteristic? _findChar(
    List<BluetoothService> services,
    Guid serviceUuid,
    Guid charUuid,
  ) {
    for (final service in services) {
      if (service.uuid != serviceUuid) continue;
      for (final c in service.characteristics) {
        if (c.uuid == charUuid) return c;
      }
    }
    return null;
  }

  void _fail(String message) {
    _errorMessage = message;
    _setStatus(ConnectionStatus.bluetoothOn);
    // 상태가 이미 bluetoothOn이었어도 에러 문구는 갱신되어야 한다.
    notifyListeners();
  }

  void _clearDevice() {
    _proximityValueSub?.cancel();
    _proximityValueSub = null;
    _deviceStateSub?.cancel();
    _deviceStateSub = null;
    _device = null;
    _deviceId = null;
  }

  Future<void> disconnect() async {
    final device = _device;
    if (_status != ConnectionStatus.deviceConnected || device == null) return;
    _clearDevice();
    _setStatus(ConnectionStatus.bluetoothOn);
    await device.disconnect();
  }

  @override
  void dispose() {
    _adapterStateSub?.cancel();
    _clearDevice();
    _proximityController.close();
    super.dispose();
  }
}
