import 'dart:typed_data';

import 'package:dd_glasses/ble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sample = LiveMetrics(
    seq: 137,
    flags: LiveMetrics.flagWearing | LiveMetrics.flagCameraActive,
    dtMs: 250,
    perclos: 0.0812,
    pitchDeg: -12.4,
    rollDeg: 3.7,
    blinkDurMs: 480,
    blinkRatePerMin: 14,
    eyeClosure: 72,
    proximityRaw: 41,
    riskLevel: 2,
    riskScore: 58,
    batteryPct: 78,
  );

  group('LiveMetrics wire format', () {
    test('is exactly 20 bytes so it survives the default ATT MTU', () {
      expect(sample.encode().length, LiveMetrics.byteLength);
      expect(LiveMetrics.byteLength, 20);
    });

    test('round-trips without losing meaningful precision', () {
      final decoded = LiveMetrics.decode(sample.encode());

      expect(decoded.seq, sample.seq);
      expect(decoded.flags, sample.flags);
      expect(decoded.dtMs, sample.dtMs);
      expect(decoded.perclos, closeTo(sample.perclos, 0.0001));
      expect(decoded.pitchDeg, closeTo(sample.pitchDeg, 0.05));
      expect(decoded.rollDeg, closeTo(sample.rollDeg, 0.05));
      expect(decoded.blinkDurMs, sample.blinkDurMs);
      expect(decoded.eyeClosure, sample.eyeClosure);
      expect(decoded.proximityRaw, sample.proximityRaw);
      expect(decoded.riskLevel, sample.riskLevel);
      expect(decoded.riskScore, sample.riskScore);
      expect(decoded.batteryPct, sample.batteryPct);
    });

    test('decodes flag bits', () {
      final decoded = LiveMetrics.decode(sample.encode());
      expect(decoded.isWearing, isTrue);
      expect(decoded.isCameraActive, isTrue);
      expect(decoded.isCalibrating, isFalse);
      expect(decoded.isLowPower, isFalse);
    });

    test('rejects a corrupted byte via CRC', () {
      final raw = sample.encode();
      raw[6] = raw[6] ^ 0xFF; // flip the pitch low byte
      expect(
        () => LiveMetrics.decode(raw),
        throwsA(isA<PacketFormatException>()),
      );
    });

    test('rejects a truncated frame', () {
      final short = Uint8List.sublistView(sample.encode(), 0, 19);
      expect(
        () => LiveMetrics.decode(short),
        throwsA(isA<PacketFormatException>()),
      );
    });

    test('is little-endian, matching the ESP32 byte order', () {
      final raw = sample.encode();
      // dtMs = 250 = 0x00FA at offset 2
      expect(raw[2], 0xFA);
      expect(raw[3], 0x00);
    });

    test('clamps out-of-range values instead of overflowing', () {
      const extreme = LiveMetrics(
        seq: 300,
        flags: 0,
        dtMs: 99999,
        perclos: 2.5,
        pitchDeg: 0,
        rollDeg: 0,
        blinkDurMs: 0,
        blinkRatePerMin: 0,
        eyeClosure: 0,
        proximityRaw: 0,
        riskLevel: 9,
        riskScore: 250,
        batteryPct: 180,
      );
      final decoded = LiveMetrics.decode(extreme.encode());
      expect(decoded.seq, 300 & 0xFF);
      expect(decoded.perclos, 1.0);
      expect(decoded.riskLevel, 3);
      expect(decoded.riskScore, 100);
      expect(decoded.batteryPct, 100);
    });
  });

  group('AlertPacket and AlertAck', () {
    test('alert round-trips', () {
      const alert = AlertPacket(
        alertId: 42,
        level: 3,
        causeBitmask: 0x08,
        deviceUptimeMs: 98244,
      );
      final decoded = AlertPacket.decode(alert.encode());
      expect(decoded.alertId, 42);
      expect(decoded.level, 3);
      expect(decoded.causeBitmask, 0x08);
      expect(decoded.deviceUptimeMs, 98244);
      expect(alert.encode().length, AlertPacket.byteLength);
    });

    test('ack round-trips with its status', () {
      const ack = AlertAck(
        alertId: 42,
        status: AlertAckStatus.confirmedByUser,
      );
      final decoded = AlertAck.decode(ack.encode());
      expect(decoded.alertId, 42);
      expect(decoded.status, AlertAckStatus.confirmedByUser);
    });
  });

  group('Crc8', () {
    test('is stable and order-dependent', () {
      expect(Crc8.compute(<int>[0x01, 0x02, 0x03]),
          Crc8.compute(<int>[0x01, 0x02, 0x03]));
      expect(Crc8.compute(<int>[0x01, 0x02, 0x03]),
          isNot(Crc8.compute(<int>[0x03, 0x02, 0x01])));
    });

    test('empty input is zero', () {
      expect(Crc8.compute(<int>[]), 0);
    });
  });
}
