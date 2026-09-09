import 'dart:async';

/// How a bounded-retry delivery ended.
enum DeliveryOutcome {
  /// Acknowledged, possibly after retries.
  acknowledged,

  /// Every attempt was used without an acknowledgement.
  gaveUp,

  /// Cancelled by [AckedSender.dispose] or [AckedSender.cancel].
  cancelled,
}

class DeliveryReport {
  const DeliveryReport({
    required this.outcome,
    required this.attempts,
    required this.elapsed,
  });

  final DeliveryOutcome outcome;
  final int attempts;
  final Duration elapsed;

  bool get isAcknowledged => outcome == DeliveryOutcome.acknowledged;

  @override
  String toString() =>
      'DeliveryReport(${outcome.name}, attempts: $attempts, '
      '${elapsed.inMilliseconds}ms)';
}

/// Bounded retransmission over BLE — "resend up to n times if no
/// acknowledgement arrives".
///
/// Why this layer exists at all: BLE's link layer already retransmits lost
/// radio packets indefinitely, so nothing is dropped while the connection
/// holds. What it cannot tell us is whether the *application* handled the
/// message — an Indicate confirmation only proves the bytes reached the
/// phone's Bluetooth stack, not that the alarm reached the wearer's screen.
/// For hazard alerts that difference matters, so the peer sends an explicit
/// acknowledgement over a separate characteristic and this class matches
/// acknowledgements to messages.
///
/// Unbounded retry is deliberately not offered. On a safety device an alarm
/// that retries forever drains the battery and hides the fact that the phone
/// is gone; giving up after [maxAttempts] lets the firmware fall back to
/// on-device vibration and voice, which works with no phone at all.
class AckedSender<K> {
  AckedSender({
    required this.send,
    this.timeout = const Duration(seconds: 2),
    this.maxAttempts = 3,
    this.onAttempt,
    this.onGiveUp,
  }) : assert(maxAttempts >= 1, 'maxAttempts must be at least 1');

  /// Performs one transmission attempt. Throwing is treated as a failed
  /// attempt and consumes one of [maxAttempts].
  final Future<void> Function(K key, int attempt) send;

  /// How long to wait for an acknowledgement before resending.
  final Duration timeout;

  /// Total transmissions, including the first.
  final int maxAttempts;

  final void Function(K key, int attempt)? onAttempt;
  final void Function(K key, int attempts)? onGiveUp;

  final Map<K, _Pending> _pending = <K, _Pending>{};

  int get pendingCount => _pending.length;
  bool isPending(K key) => _pending.containsKey(key);

  /// Sends [key] and resolves once it is acknowledged or the attempts run out.
  ///
  /// Calling this for a key already in flight returns that same future rather
  /// than starting a second delivery.
  Future<DeliveryReport> deliver(K key) {
    final existing = _pending[key];
    if (existing != null) return existing.completer.future;

    final pending = _Pending(Stopwatch()..start());
    _pending[key] = pending;
    _attempt(key, pending);
    return pending.completer.future;
  }

  /// Marks [key] acknowledged. Unknown keys are ignored — a duplicate
  /// acknowledgement after a retry is normal, not an error.
  void ack(K key) {
    final pending = _pending.remove(key);
    if (pending == null) return;
    pending.timer?.cancel();
    pending.stopwatch.stop();
    pending.completer.complete(
      DeliveryReport(
        outcome: DeliveryOutcome.acknowledged,
        attempts: pending.attempts,
        elapsed: pending.stopwatch.elapsed,
      ),
    );
  }

  void cancel(K key) => _finish(key, DeliveryOutcome.cancelled);

  void dispose() {
    for (final key in _pending.keys.toList()) {
      _finish(key, DeliveryOutcome.cancelled);
    }
  }

  Future<void> _attempt(K key, _Pending pending) async {
    pending.attempts++;
    onAttempt?.call(key, pending.attempts);
    try {
      await send(key, pending.attempts);
    } catch (_) {
      // A failed write counts as a used attempt; the timer below decides
      // whether to try again.
    }
    if (!_pending.containsKey(key)) return;

    if (pending.attempts >= maxAttempts) {
      pending.timer = Timer(timeout, () {
        if (!_pending.containsKey(key)) return;
        onGiveUp?.call(key, pending.attempts);
        _finish(key, DeliveryOutcome.gaveUp);
      });
    } else {
      pending.timer = Timer(timeout, () {
        if (!_pending.containsKey(key)) return;
        _attempt(key, pending);
      });
    }
  }

  void _finish(K key, DeliveryOutcome outcome) {
    final pending = _pending.remove(key);
    if (pending == null) return;
    pending.timer?.cancel();
    pending.stopwatch.stop();
    pending.completer.complete(
      DeliveryReport(
        outcome: outcome,
        attempts: pending.attempts,
        elapsed: pending.stopwatch.elapsed,
      ),
    );
  }
}

class _Pending {
  _Pending(this.stopwatch);
  final Stopwatch stopwatch;
  final Completer<DeliveryReport> completer = Completer<DeliveryReport>();
  Timer? timer;
  int attempts = 0;
}
