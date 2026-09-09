import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../protocol/acked_sender.dart';
import '../protocol/alert.dart';
import '../protocol/awake_uuids.dart';
import '../protocol/commands.dart';
import '../protocol/link_watchdog.dart';
import '../protocol/live_metrics.dart';
import '../protocol/seq_tracker.dart';

/// Connection stages. "Connected" is deliberately not one of them.
///
/// A GATT connection proves almost nothing: services may not be discovered,
/// the CCCD may not be written, and no data may ever arrive. The app treats
/// the link as usable only at [AwakeLinkState.streaming], which is reached
/// when the first Live Metrics frame decodes successfully.
enum AwakeLinkState {
  idle,
  scanning,
  connecting,
  discovering,
  subscribing,
  streaming,
  reconnecting,
  failed,
}

extension AwakeLinkStateLabel on AwakeLinkState {
  /// Text for the main screen. Only one of these says 연결됨.
  String get label {
    switch (this) {
      case AwakeLinkState.idle:
        return '연결 안 됨';
      case AwakeLinkState.scanning:
        return '기기 검색 중';
      case AwakeLinkState.connecting:
        return '연결 중';
      case AwakeLinkState.discovering:
        return '서비스 확인 중';
      case AwakeLinkState.subscribing:
        return '데이터 구독 중';
      case AwakeLinkState.streaming:
        return '연결됨';
      case AwakeLinkState.reconnecting:
        return '재연결 중';
      case AwakeLinkState.failed:
        return '연결 실패';
    }
  }

  bool get isUsable => this == AwakeLinkState.streaming;
}

/// Talks to the glasses over BLE.
///
/// Targets flutter_blue_plus 2.x. Note its licence: free for non-profit and
/// educational use, separate commercial licence otherwise. All access goes
/// through this one class so swapping to flutter_reactive_ble (BSD-3) later
/// means rewriting this file and nothing else.
class AwakeBleClient {
  AwakeBleClient({
    this.scanTimeout = const Duration(seconds: 15),
    this.connectTimeout = const Duration(seconds: 12),
    this.preferredMtu = 247,
    this.alertAckTimeout = const Duration(seconds: 2),
    this.alertMaxAttempts = 3,
  });

  final Duration scanTimeout;
  final Duration connectTimeout;

  /// Requested ATT MTU. Frames are 20 bytes so this is an optimisation, not a
  /// requirement — the link works at the default MTU of 23.
  final int preferredMtu;

  final Duration alertAckTimeout;
  final int alertMaxAttempts;

  final StreamController<AwakeLinkState> _stateController =
      StreamController<AwakeLinkState>.broadcast();
  final StreamController<LiveMetrics> _metricsController =
      StreamController<LiveMetrics>.broadcast();
  final StreamController<AlertPacket> _alertController =
      StreamController<AlertPacket>.broadcast();
  final StreamController<DeviceStatus> _statusController =
      StreamController<DeviceStatus>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  final SeqTracker seqTracker = SeqTracker();
  final LinkWatchdog watchdog = LinkWatchdog();

  late final AckedSender<int> _alertAcks = AckedSender<int>(
    send: (alertId, attempt) => _writeAlertAck(alertId, attempt),
    timeout: alertAckTimeout,
    maxAttempts: alertMaxAttempts,
    onAttempt: (id, attempt) => _log('alert $id ack attempt $attempt'),
    onGiveUp: (id, attempts) =>
        _log('alert $id NOT acknowledged after $attempts attempts'),
  );

  BluetoothDevice? _device;
  BluetoothCharacteristic? _liveMetrics;
  BluetoothCharacteristic? _alert;
  BluetoothCharacteristic? _alertAck;
  BluetoothCharacteristic? _command;
  BluetoothCharacteristic? _status;

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  AwakeLinkState _state = AwakeLinkState.idle;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  bool _shouldStayConnected = false;
  int _negotiatedMtu = 23;
  int _crcErrors = 0;
  DateTime? _pingSentAt;
  Duration? _lastRoundTrip;

  Stream<AwakeLinkState> get stateStream => _stateController.stream;
  Stream<LiveMetrics> get metrics => _metricsController.stream;
  Stream<AlertPacket> get alerts => _alertController.stream;
  Stream<DeviceStatus> get status => _statusController.stream;
  Stream<String> get log => _logController.stream;

  AwakeLinkState get state => _state;
  int get negotiatedMtu => _negotiatedMtu;
  int get crcErrors => _crcErrors;

  /// Round trip of the last PING. Null until one completes.
  Duration? get lastRoundTrip => _lastRoundTrip;

  String? get deviceName => _device?.platformName;

  // -------------------------------------------------------------------------
  // Connection
  // -------------------------------------------------------------------------

  /// Scans for the glasses and brings the link all the way to streaming.
  ///
  /// Devices are matched by service UUID and advertised name, never by
  /// hardware address: iOS does not expose one, so a MAC-based "remember my
  /// device" breaks there.
  Future<void> connect() async {
    _shouldStayConnected = true;
    _reconnectAttempt = 0;
    await _runConnectSequence();
  }

  Future<void> disconnect() async {
    _shouldStayConnected = false;
    _reconnectTimer?.cancel();
    await _teardown();
    _setState(AwakeLinkState.idle);
  }

  Future<void> _runConnectSequence() async {
    try {
      _setState(AwakeLinkState.scanning);
      final device = await _scanForDevice();
      if (device == null) {
        _log('no AWAKE device found within ${scanTimeout.inSeconds}s');
        _scheduleReconnect();
        return;
      }

      // Android throws GATT_ERROR (133) when a connection is attempted while a
      // scan is running. Stop first, always.
      await FlutterBluePlus.stopScan();

      _setState(AwakeLinkState.connecting);
      _device = device;
      _subscriptions.add(
        device.connectionState.listen(_onConnectionStateChanged),
      );
      await device.connect(timeout: connectTimeout, autoConnect: false);

      _setState(AwakeLinkState.discovering);
      final services = await device.discoverServices();
      _bindCharacteristics(services);

      // Optional: larger frames are not needed, but a bigger MTU lowers
      // per-packet overhead during log catch-up. iOS negotiates on its own and
      // throws here, which is not an error.
      try {
        _negotiatedMtu = await device.requestMtu(preferredMtu);
        _log('MTU negotiated: $_negotiatedMtu');
      } catch (error) {
        _log('MTU request skipped: $error');
      }

      _setState(AwakeLinkState.subscribing);
      await _subscribeAll();

      watchdog.start();
      _subscriptions.add(watchdog.healthStream.listen(_onHealthChanged));
      // The state advances to streaming on the first decoded frame, not here.
    } catch (error) {
      _log('connect failed: $error');
      await _teardown();
      _scheduleReconnect();
    }
  }

  Future<BluetoothDevice?> _scanForDevice() async {
    final completer = Completer<BluetoothDevice?>();
    final serviceGuid = Guid(AwakeUuids.service);

    late StreamSubscription<List<ScanResult>> sub;
    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final advertisesService =
            result.advertisementData.serviceUuids.contains(serviceGuid);
        final nameMatches = result.device.platformName
            .startsWith(AwakeUuids.advertisedNamePrefix);
        if (advertisesService || nameMatches) {
          if (!completer.isCompleted) {
            _log('found ${result.device.platformName} '
                'at ${result.rssi} dBm');
            completer.complete(result.device);
          }
          return;
        }
      }
    });

    await FlutterBluePlus.startScan(
      withServices: <Guid>[serviceGuid],
      timeout: scanTimeout,
    );

    final device = await completer.future
        .timeout(scanTimeout, onTimeout: () => null)
        .whenComplete(() async {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    });
    return device;
  }

  void _bindCharacteristics(List<BluetoothService> services) {
    BluetoothCharacteristic? find(String uuid) {
      final wanted = Guid(uuid);
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == wanted) return characteristic;
        }
      }
      return null;
    }

    _liveMetrics = find(AwakeUuids.liveMetrics);
    _alert = find(AwakeUuids.alert);
    _alertAck = find(AwakeUuids.alertAck);
    _command = find(AwakeUuids.command);
    _status = find(AwakeUuids.status);

    if (_liveMetrics == null) {
      throw StateError(
        'AWAKE service found but the Live Metrics characteristic is missing — '
        'check the firmware UUIDs against AwakeUuids.',
      );
    }
  }

  Future<void> _subscribeAll() async {
    final live = _liveMetrics!;
    await live.setNotifyValue(true);
    _subscriptions.add(live.onValueReceived.listen(_onLiveMetrics));

    final alert = _alert;
    if (alert != null) {
      await alert.setNotifyValue(true);
      _subscriptions.add(alert.onValueReceived.listen(_onAlert));
    }

    final status = _status;
    if (status != null) {
      await status.setNotifyValue(true);
      _subscriptions.add(status.onValueReceived.listen(_onStatus));
    }
  }

  // -------------------------------------------------------------------------
  // Inbound
  // -------------------------------------------------------------------------

  void _onLiveMetrics(List<int> raw) {
    watchdog.beat();
    try {
      final frame = LiveMetrics.decode(Uint8List.fromList(raw));
      final missing = seqTracker.accept(frame.seq);
      if (missing > 0) {
        _log('seq gap: ${seqTracker.lastGap.join(", ")} missing '
            '(${(seqTracker.lossRate * 100).toStringAsFixed(2)}% total)');
      }
      if (_state != AwakeLinkState.streaming) {
        _reconnectAttempt = 0;
        _setState(AwakeLinkState.streaming);
      }
      if (!_metricsController.isClosed) _metricsController.add(frame);
    } on PacketFormatException catch (error) {
      _crcErrors++;
      _log('bad frame: ${error.message}');
    }
  }

  void _onAlert(List<int> raw) {
    watchdog.beat();
    try {
      final alert = AlertPacket.decode(Uint8List.fromList(raw));
      if (!_alertController.isClosed) _alertController.add(alert);
      // Acknowledge that the app has the alert. The UI calls
      // [confirmAlert] separately once the wearer responds.
      _alertAcks.deliver(alert.alertId);
    } on PacketFormatException catch (error) {
      _log('bad alert: ${error.message}');
    }
  }

  void _onStatus(List<int> raw) {
    watchdog.beat();
    if (raw.length < DeviceStatus.byteLength) return;
    final sentAt = _pingSentAt;
    if (sentAt != null) {
      _lastRoundTrip = DateTime.now().difference(sentAt);
      _pingSentAt = null;
      _log('PING round trip ${_lastRoundTrip!.inMilliseconds}ms');
    }
    if (!_statusController.isClosed) {
      _statusController.add(DeviceStatus.decode(Uint8List.fromList(raw)));
    }
  }

  void _onConnectionStateChanged(BluetoothConnectionState state) {
    if (state == BluetoothConnectionState.disconnected &&
        _state != AwakeLinkState.idle) {
      _log('platform reported disconnect');
      _teardown().then((_) => _scheduleReconnect());
    }
  }

  void _onHealthChanged(LinkHealth health) {
    _log('link health: ${health.name}');
    if (health == LinkHealth.lost && _state == AwakeLinkState.streaming) {
      // The watchdog fires well before Android's disconnect callback does.
      _teardown().then((_) => _scheduleReconnect());
    }
  }

  // -------------------------------------------------------------------------
  // Outbound
  // -------------------------------------------------------------------------

  /// Tells the glasses the wearer confirmed the alarm — the app-side path to
  /// the proposal's feedback-stop condition.
  Future<void> confirmAlert(int alertId) async {
    _alertAcks.ack(alertId);
    await _writeCharacteristic(
      _alertAck,
      AlertAck(alertId: alertId, status: AlertAckStatus.confirmedByUser)
          .encode(),
    );
  }

  Future<void> _writeAlertAck(int alertId, int attempt) => _writeCharacteristic(
        _alertAck,
        AlertAck(alertId: alertId, status: AlertAckStatus.displayed).encode(),
      );

  /// Round-trip probe behind the main screen's test button.
  Future<void> ping() async {
    _pingSentAt = DateTime.now();
    await _writeCharacteristic(_command, AwakeCommand.buildPing());
  }

  Future<void> stopFeedback() =>
      _writeCharacteristic(_command, AwakeCommand.buildStopFeedback());

  Future<void> startCalibration() =>
      _writeCharacteristic(_command, AwakeCommand.buildStartCalibration());

  Future<void> setStreamRate(int hz) =>
      _writeCharacteristic(_command, AwakeCommand.buildSetStreamRate(hz));

  /// Asks the firmware to emit a known sequence so loss can be measured with
  /// no sensor involved. Reset [seqTracker] first, then read it afterwards.
  Future<void> runLossTest({int packetCount = 1000}) async {
    seqTracker.reset();
    await _writeCharacteristic(
      _command,
      AwakeCommand.buildTestMode(packetCount),
    );
  }

  Future<void> _writeCharacteristic(
    BluetoothCharacteristic? characteristic,
    Uint8List value,
  ) async {
    if (characteristic == null) {
      throw StateError('characteristic unavailable — link is not ready');
    }
    await characteristic.write(value, withoutResponse: false);
  }

  // -------------------------------------------------------------------------
  // Reconnection
  // -------------------------------------------------------------------------

  void _scheduleReconnect() {
    if (!_shouldStayConnected) return;
    _reconnectAttempt++;
    // 1, 2, 4, 8, 16, capped at 30 seconds.
    final seconds = math.min(30, 1 << math.min(_reconnectAttempt - 1, 5));
    _setState(AwakeLinkState.reconnecting);
    _log('reconnect attempt $_reconnectAttempt in ${seconds}s');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: seconds), _runConnectSequence);
  }

  Future<void> _teardown() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    watchdog.stop();
    // Always disconnect explicitly before retrying. Skipping this leaks GATT
    // client slots on Android and the next connect fails with error 133.
    try {
      await _device?.disconnect();
    } catch (_) {
      // Already gone.
    }
    _device = null;
    _liveMetrics = null;
    _alert = null;
    _alertAck = null;
    _command = null;
    _status = null;
  }

  void _setState(AwakeLinkState state) {
    if (_state == state) return;
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
    _log('state -> ${state.name}');
  }

  void _log(String message) {
    if (!_logController.isClosed) {
      _logController.add('[${DateTime.now().toIso8601String()}] $message');
    }
  }

  Future<void> dispose() async {
    _shouldStayConnected = false;
    _reconnectTimer?.cancel();
    _alertAcks.dispose();
    await _teardown();
    await watchdog.dispose();
    await _stateController.close();
    await _metricsController.close();
    await _alertController.close();
    await _statusController.close();
    await _logController.close();
  }
}
