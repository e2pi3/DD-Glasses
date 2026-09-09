/// GATT identifiers for the AWAKE Safety Service.
///
/// 16-bit UUIDs are reserved for Bluetooth SIG adopted services, so the
/// project uses one 128-bit base and varies only the third and fourth hex
/// digits. Keep these in sync with `firmware/awake_ble_server/protocol.h`.
class AwakeUuids {
  AwakeUuids._();

  static const String _base = '-4B53-4545-9A2F-0C1D2E3F4A5B';

  /// Advertised primary service.
  static const String service = '7E1C0001$_base';

  /// 20-byte sensor frame, Notify. See [LiveMetrics].
  static const String liveMetrics = '7E1C0002$_base';

  /// 8-byte hazard event, Indicate. See [AlertPacket].
  static const String alert = '7E1C0003$_base';

  /// 3-byte acknowledgement, Write With Response. See [AlertAck].
  static const String alertAck = '7E1C0004$_base';

  /// 1-5 byte command, Write With Response. See [AwakeCommand].
  static const String command = '7E1C0005$_base';

  /// 8-byte configuration block, Read / Write With Response.
  static const String config = '7E1C0006$_base';

  /// 8-byte device status, Read + Notify. Doubles as the link watchdog beat.
  static const String status = '7E1C0007$_base';

  /// 20-byte buffered log chunk, Notify.
  static const String logChunk = '7E1C0008$_base';

  /// Name prefix used in advertising data. iOS never exposes a MAC address,
  /// so the app identifies devices by service UUID plus this prefix rather
  /// than by hardware address.
  static const String advertisedNamePrefix = 'AWAKE-';
}
