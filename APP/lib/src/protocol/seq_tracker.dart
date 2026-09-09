/// Counts loss on an unacknowledged (Notify) stream.
///
/// The Live Metrics stream is fire-and-forget by design: a missed sample is
/// replaced by the next one 100-250 ms later, so retransmitting it would only
/// deliver stale data. What we do need is a number — this class turns the
/// 8-bit sequence field into a loss rate the log screen and the acceptance
/// test can report.
///
/// The counter wraps at 256, so a raw subtraction is wrong once per 256
/// packets. Gaps are evaluated modulo 256, and a gap larger than half the
/// space is read as reordering rather than as 200-odd lost packets.
class SeqTracker {
  SeqTracker({this.reorderWindow = 128});

  /// Gaps at or above this are treated as out-of-order, not loss.
  final int reorderWindow;

  int _received = 0;
  int _lost = 0;
  int _duplicates = 0;
  int _outOfOrder = 0;
  int? _last;

  int get received => _received;
  int get lost => _lost;
  int get duplicates => _duplicates;
  int get outOfOrder => _outOfOrder;
  int get expected => _received + _lost;

  /// 0.0 - 1.0. Zero before anything has arrived.
  double get lossRate => expected == 0 ? 0 : _lost / expected;

  /// Sequence numbers missing from the most recent step, oldest first.
  /// Useful for the log view: `seq 138 missing`.
  List<int> lastGap = const <int>[];

  void reset() {
    _received = 0;
    _lost = 0;
    _duplicates = 0;
    _outOfOrder = 0;
    _last = null;
    lastGap = const <int>[];
  }

  /// Records one arrival. Returns the number of packets presumed lost
  /// immediately before it.
  int accept(int seq) {
    final value = seq & 0xFF;
    _received++;
    final previous = _last;
    if (previous == null) {
      _last = value;
      lastGap = const <int>[];
      return 0;
    }

    final gap = (value - previous) & 0xFF;
    if (gap == 0) {
      _duplicates++;
      lastGap = const <int>[];
      return 0;
    }
    if (gap >= reorderWindow) {
      _outOfOrder++;
      lastGap = const <int>[];
      return 0;
    }

    final missing = gap - 1;
    if (missing > 0) {
      _lost += missing;
      lastGap = List<int>.generate(missing, (i) => (previous + 1 + i) & 0xFF);
    } else {
      lastGap = const <int>[];
    }
    _last = value;
    return missing;
  }

  @override
  String toString() => 'SeqTracker(received: $_received, lost: $_lost, '
      'loss: ${(lossRate * 100).toStringAsFixed(2)}%, '
      'dup: $_duplicates, reordered: $_outOfOrder)';
}
