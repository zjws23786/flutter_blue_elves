import 'dart:typed_data';

class Hex{
  /// Creates a `Uint8List` by a hex string.
  static Uint8List createUint8ListFromHexString(String hex) {
    if (hex == null) throw new ArgumentError("hex is null");

    var result = new Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      var num = hex.substring(i, i + 2);
      var byte = int.parse(num, radix: 16);
      result[i ~/ 2] = byte;
    }

    return result;
  }

  /// Returns a hex string by a `Uint8List`.
  static String formatBytesAsHexString(Uint8List bytes) {
    if (bytes == null) throw new ArgumentError("The list is null");

    var result = new StringBuffer();
    for (var i = 0; i < bytes.lengthInBytes; i++) {
      var part = bytes[i];
      result.write('${part < 16 ? '0' : ''}${part.toRadixString(16)}');
    }

    return result.toString();
  }
}
