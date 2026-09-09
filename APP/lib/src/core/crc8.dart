/// CRC-8 (polynomial 0x07, init 0x00, no reflection, no final XOR).
///
/// The ESP32 firmware must use the identical implementation — see
/// `firmware/awake_ble_server/crc8.h` in this repository.
class Crc8 {
  Crc8._();

  static const int _polynomial = 0x07;

  static final List<int> _table = _buildTable();

  static List<int> _buildTable() {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var crc = i;
      for (var bit = 0; bit < 8; bit++) {
        if ((crc & 0x80) != 0) {
          crc = ((crc << 1) ^ _polynomial) & 0xFF;
        } else {
          crc = (crc << 1) & 0xFF;
        }
      }
      table[i] = crc;
    }
    return table;
  }

  /// Computes the CRC over `bytes[start .. end)`.
  static int compute(List<int> bytes, {int start = 0, int? end}) {
    final stop = end ?? bytes.length;
    var crc = 0;
    for (var i = start; i < stop; i++) {
      crc = _table[(crc ^ (bytes[i] & 0xFF)) & 0xFF];
    }
    return crc;
  }
}
