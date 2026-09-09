import 'dart:async';

/// How healthy the BLE link looks from the app's side.
enum LinkHealth {
  /// Packets arriving on schedule.
  live,

  /// A gap longer than one sample period. Normal while the on-board camera
  /// is streaming over Wi-Fi — the radio is shared.
  degraded,

  /// Long enough that reconnection has started.
  unstable,

  /// Treated as disconnected regardless of what the OS reports.
  lost,
}

/// Decides whether data is still flowing, without trusting the platform's
/// disconnect callback.
///
/// Android can take seconds to tens of seconds to report a dropped BLE
/// connection. During that window the OS still says "connected" while nothing
/// arrives, and the app would happily show a stale, confident-looking screen.
/// Measuring the time since the last packet is the only reliable signal.
class LinkWatchdog {
  LinkWatchdog({
    this.degradedAfter = const Duration(milliseconds: 500),
    this.unstableAfter = const Duration(seconds: 3),
    this.lostAfter = const Duration(seconds: 10),
    this.tick = const Duration(milliseconds: 250),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration degradedAfter;
  final Duration unstableAfter;
  final Duration lostAfter;

  /// How often the health is re-evaluated when no packets arrive.
  final Duration tick;

  final DateTime Function() _clock;
  final StreamController<LinkHealth> _controller =
      StreamController<LinkHealth>.broadcast();

  Timer? _timer;
  DateTime? _lastPacketAt;
  LinkHealth _health = LinkHealth.lost;

  Stream<LinkHealth> get healthStream => _controller.stream;
  LinkHealth get health => _health;

  Duration? get sinceLastPacket {
    final last = _lastPacketAt;
    return last == null ? null : _clock().difference(last);
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => _evaluate());
  }

  /// Call for every packet received on any characteristic.
  void beat() {
    _lastPacketAt = _clock();
    _evaluate();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _lastPacketAt = null;
    _emit(LinkHealth.lost);
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }

  void _evaluate() {
    final elapsed = sinceLastPacket;
    if (elapsed == null) {
      _emit(LinkHealth.lost);
      return;
    }
    if (elapsed >= lostAfter) {
      _emit(LinkHealth.lost);
    } else if (elapsed >= unstableAfter) {
      _emit(LinkHealth.unstable);
    } else if (elapsed >= degradedAfter) {
      _emit(LinkHealth.degraded);
    } else {
      _emit(LinkHealth.live);
    }
  }

  void _emit(LinkHealth health) {
    if (health == _health) return;
    _health = health;
    if (!_controller.isClosed) _controller.add(health);
  }
}
