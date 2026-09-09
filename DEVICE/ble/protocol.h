// AWAKE BLE protocol — shared definitions.
//
// This header is the firmware half of lib/src/protocol/ in the Flutter app.
// Any change here must be mirrored there, and vice versa.

#pragma once
#include <stdint.h>
#include <string.h>

// ---------------------------------------------------------------------------
// GATT identifiers — must match AwakeUuids in the Dart code exactly.
// ---------------------------------------------------------------------------
#define AWAKE_SERVICE_UUID       "7E1C0001-4B53-4545-9A2F-0C1D2E3F4A5B"
#define AWAKE_CHAR_LIVE_METRICS  "7E1C0002-4B53-4545-9A2F-0C1D2E3F4A5B"
#define AWAKE_CHAR_ALERT         "7E1C0003-4B53-4545-9A2F-0C1D2E3F4A5B"
#define AWAKE_CHAR_ALERT_ACK     "7E1C0004-4B53-4545-9A2F-0C1D2E3F4A5B"
#define AWAKE_CHAR_COMMAND       "7E1C0005-4B53-4545-9A2F-0C1D2E3F4A5B"
#define AWAKE_CHAR_CONFIG        "7E1C0006-4B53-4545-9A2F-0C1D2E3F4A5B"
#define AWAKE_CHAR_STATUS        "7E1C0007-4B53-4545-9A2F-0C1D2E3F4A5B"
#define AWAKE_CHAR_LOG_CHUNK     "7E1C0008-4B53-4545-9A2F-0C1D2E3F4A5B"

#define AWAKE_DEVICE_NAME        "AWAKE-G1"

// ---------------------------------------------------------------------------
// CRC-8, polynomial 0x07, init 0x00. Identical to Crc8 in Dart.
// ---------------------------------------------------------------------------
static inline uint8_t awake_crc8(const uint8_t *data, size_t length) {
  uint8_t crc = 0x00;
  for (size_t i = 0; i < length; i++) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; bit++) {
      crc = (crc & 0x80) ? (uint8_t)((crc << 1) ^ 0x07) : (uint8_t)(crc << 1);
    }
  }
  return crc;
}

// ---------------------------------------------------------------------------
// Live Metrics — 20 bytes, little-endian.
//
// Twenty bytes is not arbitrary: it is what fits in the default ATT MTU of 23
// once the 3-byte ATT header is removed. The link therefore works even when
// MTU negotiation fails, which is what makes behaviour consistent across
// phones.
//
// The ESP32-S3 is little-endian and the struct is packed, so a memcpy of the
// struct is already the wire format.
// ---------------------------------------------------------------------------
#define AWAKE_FLAG_WEARING       0x01
#define AWAKE_FLAG_CALIBRATING   0x02
#define AWAKE_FLAG_CAMERA_ACTIVE 0x04
#define AWAKE_FLAG_LOW_POWER     0x08

typedef struct __attribute__((packed)) {
  uint8_t  seq;            //  0  wraps 0-255
  uint8_t  flags;          //  1
  uint16_t dt_ms;          //  2  interval since the previous frame
  uint16_t perclos_x100;   //  4  0-10000
  int16_t  pitch_x10;      //  6  degrees x10, relative to neutral
  int16_t  roll_x10;       //  8
  uint16_t blink_dur_ms;   // 10
  uint8_t  blink_rate;     // 12  per minute
  uint8_t  eye_closure;    // 13  0 fully open .. 255 fully closed
  uint16_t proximity_raw;  // 14  raw IR ADC count, uncalibrated
  uint8_t  risk_level;     // 16  0-3
  uint8_t  risk_score;     // 17  0-100
  uint8_t  battery_pct;    // 18
  uint8_t  crc8;           // 19  over bytes 0..18
} awake_live_metrics_t;

_Static_assert(sizeof(awake_live_metrics_t) == 20,
               "Live Metrics frame must stay at 20 bytes");

static inline void awake_seal(awake_live_metrics_t *frame) {
  frame->crc8 = awake_crc8((const uint8_t *)frame, sizeof(*frame) - 1);
}

// ---------------------------------------------------------------------------
// Alert — 8 bytes, Indicate.
// ---------------------------------------------------------------------------
#define AWAKE_CAUSE_PERCLOS      0x01
#define AWAKE_CAUSE_BLINK_DUR    0x02
#define AWAKE_CAUSE_HEAD_PITCH   0x04
#define AWAKE_CAUSE_HEAD_JERK    0x08
#define AWAKE_CAUSE_EYES_CLOSED  0x10
#define AWAKE_CAUSE_HRV          0x20
#define AWAKE_CAUSE_ESCALATION   0x40

typedef struct __attribute__((packed)) {
  uint16_t alert_id;       // 0  monotonic; the acknowledgement key
  uint8_t  level;          // 2  1 caution, 2 warning, 3 danger
  uint8_t  cause;          // 3  bitmask above
  uint32_t uptime_ms;      // 4
} awake_alert_t;

_Static_assert(sizeof(awake_alert_t) == 8, "Alert frame must stay at 8 bytes");

// Acknowledgement written back by the app (3 bytes).
#define AWAKE_ACK_DISPLAYED   0
#define AWAKE_ACK_CONFIRMED   1
#define AWAKE_ACK_DISMISSED   2

typedef struct __attribute__((packed)) {
  uint16_t alert_id;
  uint8_t  status;
} awake_alert_ack_t;

_Static_assert(sizeof(awake_alert_ack_t) == 3, "Ack must stay at 3 bytes");

// ---------------------------------------------------------------------------
// Commands written by the app (Write With Response).
// ---------------------------------------------------------------------------
#define AWAKE_CMD_PING              0x01
#define AWAKE_CMD_STOP_FEEDBACK     0x02
#define AWAKE_CMD_START_CALIBRATION 0x03
#define AWAKE_CMD_SET_STREAM_RATE   0x04  // + uint8 Hz
#define AWAKE_CMD_TEST_MODE         0x05  // + uint16 packet count
#define AWAKE_CMD_REQUEST_LOG       0x06  // + uint32 from index

// ---------------------------------------------------------------------------
// Status — 8 bytes, Read + Notify at 1 Hz. Doubles as the link heartbeat.
// ---------------------------------------------------------------------------
typedef struct __attribute__((packed)) {
  uint8_t  battery_pct;
  uint8_t  fw_major;
  uint8_t  fw_minor;
  uint16_t uptime_s;
  uint16_t buffered_log_count;
  uint8_t  reserved;
} awake_status_t;

_Static_assert(sizeof(awake_status_t) == 8, "Status must stay at 8 bytes");
