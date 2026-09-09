import 'dart:math' as math;

import 'metric_engine.dart';

/// Feedback stage, matching the three levels in the project proposal.
enum RiskLevel {
  /// No feedback.
  normal,

  /// Weak low-frequency bone-conduction pulse.
  caution,

  /// Bone-conduction voice prompt.
  warning,

  /// Strong pulse train plus voice, cleared only by the pressure sensor.
  danger,
}

extension RiskLevelWire on RiskLevel {
  int get wireValue => index;
  static RiskLevel fromWire(int value) =>
      RiskLevel.values[value.clamp(0, RiskLevel.values.length - 1).toInt()];
}

/// Which indicator pushed the level up. Mirrors the `cause` bitmask in the
/// Alert characteristic so the app can explain the alarm to the wearer.
enum RiskCause {
  perclos,
  blinkDuration,
  headPitch,
  headJerk,
  eyesClosed,

  /// Reserved. HRV was dropped when the sensor set was cut to IR plus IMU;
  /// the slot stays so the bitmask keeps matching AWAKE_CAUSE_* in the
  /// firmware header and a later PPG addition needs no renumbering.
  reservedHrv,

  escalation,
}

extension RiskCauseBit on RiskCause {
  int get bit => 1 << index;
}

/// Thresholds for the fusion. Every value is a starting point to be tuned
/// against labelled drowsiness recordings — the captures we have so far are
/// 12-second alertness clips with no ground truth.
class RiskThresholds {
  const RiskThresholds({
    this.perclosCaution = 0.15,
    this.perclosWarning = 0.30,
    this.blinkDurationCautionMs = 400,
    this.blinkDurationWarningMs = 600,
    this.pitchDropCautionDeg = 12,
    this.pitchDropWarningDeg = 20,
    this.eyesClosedDangerMs = 2000,
    this.cautionScore = 30,
    this.warningScore = 55,
    this.dangerScore = 80,
    this.clearHoldTime = const Duration(seconds: 5),
    this.cautionEscalatesAfter = const Duration(seconds: 30),
    this.warningEscalatesAfter = const Duration(seconds: 20),
  });

  final double perclosCaution;
  final double perclosWarning;
  final double blinkDurationCautionMs;
  final double blinkDurationWarningMs;

  /// Forward head drop, in degrees below the calibrated neutral pose.
  final double pitchDropCautionDeg;
  final double pitchDropWarningDeg;

  /// Continuous eye closure that jumps straight to [RiskLevel.danger].
  final int eyesClosedDangerMs;

  final int cautionScore;
  final int warningScore;
  final int dangerScore;

  /// How long indicators must stay clear before the level steps down. Without
  /// this the alarm flickers on and off around the threshold.
  final Duration clearHoldTime;

  /// "If Level 1 does not improve, escalate" from the proposal.
  final Duration cautionEscalatesAfter;
  final Duration warningEscalatesAfter;
}

class RiskAssessment {
  const RiskAssessment({
    required this.level,
    required this.score,
    required this.causes,
    required this.changed,
  });

  final RiskLevel level;

  /// 0-100 fused score. Drives the ring on the main screen.
  final int score;

  final Set<RiskCause> causes;

  /// True on the sample where [level] changed — the trigger for sending an
  /// Alert over BLE.
  final bool changed;

  int get causeBitmask =>
      causes.fold<int>(0, (mask, cause) => mask | cause.bit);

  @override
  String toString() =>
      'RiskAssessment(${level.name}, score: $score, causes: '
      '${causes.map((c) => c.name).join('+')})';
}

/// Fuses the drowsiness indicators into a feedback level.
///
/// Two behaviours matter as much as the arithmetic: the level rises the
/// instant an indicator crosses, but falls only after the indicators have
/// stayed clear for [RiskThresholds.clearHoldTime]; and a level that persists
/// without improving escalates on its own, which is how the proposal defines
/// Level 2 and Level 3.
class RiskFusion {
  RiskFusion({this.thresholds = const RiskThresholds()});

  final RiskThresholds thresholds;

  RiskLevel _level = RiskLevel.normal;
  int _levelSinceMs = 0;
  int? _clearSinceMs;

  RiskLevel get level => _level;

  void reset() {
    _level = RiskLevel.normal;
    _levelSinceMs = 0;
    _clearSinceMs = null;
  }

  RiskAssessment assess(DrowsinessMetrics m) {
    final causes = <RiskCause>{};
    var score = 0.0;

    // PERCLOS — the primary indicator when the sample rate supports it.
    final perclos = m.perclos;
    if (perclos != null && m.confidence != MetricConfidence.poseOnly) {
      if (perclos >= thresholds.perclosWarning) {
        score += 55;
        causes.add(RiskCause.perclos);
      } else if (perclos >= thresholds.perclosCaution) {
        score += 30;
        causes.add(RiskCause.perclos);
      }
    }

    // Blink duration — only trustworthy at a blink-capable sample rate.
    final blinkMs = m.meanBlinkDurationMs;
    if (blinkMs != null && m.confidence == MetricConfidence.full) {
      if (blinkMs >= thresholds.blinkDurationWarningMs) {
        score += 40;
        causes.add(RiskCause.blinkDuration);
      } else if (blinkMs >= thresholds.blinkDurationCautionMs) {
        score += 20;
        causes.add(RiskCause.blinkDuration);
      }
    }

    // Forward head drop. Available at any sample rate.
    final drop = -m.pitchDeg;
    if (drop >= thresholds.pitchDropWarningDeg) {
      score += 40;
      causes.add(RiskCause.headPitch);
    } else if (drop >= thresholds.pitchDropCautionDeg) {
      score += 20;
      causes.add(RiskCause.headPitch);
    }

    // Hard rules that bypass the score entirely.
    var forced = RiskLevel.normal;
    if (m.isHeadJerk) {
      causes.add(RiskCause.headJerk);
      score += 45;
      forced = RiskLevel.danger;
    }
    if (m.closedDurationMs >= thresholds.eyesClosedDangerMs) {
      causes.add(RiskCause.eyesClosed);
      score = math.max(score, 90.0);
      forced = RiskLevel.danger;
    }

    final clamped = score.clamp(0, 100).round();

    var candidate = RiskLevel.normal;
    if (clamped >= thresholds.dangerScore) {
      candidate = RiskLevel.danger;
    } else if (clamped >= thresholds.warningScore) {
      candidate = RiskLevel.warning;
    } else if (clamped >= thresholds.cautionScore) {
      candidate = RiskLevel.caution;
    }
    if (forced.index > candidate.index) candidate = forced;

    // Time-based escalation: an unimproved level moves up on its own.
    final heldMs = m.timestampMs - _levelSinceMs;
    if (_level == RiskLevel.caution &&
        candidate.index >= RiskLevel.caution.index &&
        heldMs >= thresholds.cautionEscalatesAfter.inMilliseconds) {
      candidate = RiskLevel.warning;
      causes.add(RiskCause.escalation);
    } else if (_level == RiskLevel.warning &&
        candidate.index >= RiskLevel.warning.index &&
        heldMs >= thresholds.warningEscalatesAfter.inMilliseconds) {
      candidate = RiskLevel.danger;
      causes.add(RiskCause.escalation);
    }

    var changed = false;
    if (candidate.index > _level.index) {
      _level = candidate;
      _levelSinceMs = m.timestampMs;
      _clearSinceMs = null;
      changed = true;
    } else if (candidate.index < _level.index) {
      _clearSinceMs ??= m.timestampMs;
      if (m.timestampMs - _clearSinceMs! >=
          thresholds.clearHoldTime.inMilliseconds) {
        _level = candidate;
        _levelSinceMs = m.timestampMs;
        _clearSinceMs = null;
        changed = true;
      }
    } else {
      _clearSinceMs = null;
    }

    return RiskAssessment(
      level: _level,
      score: clamped,
      causes: causes,
      changed: changed,
    );
  }
}
