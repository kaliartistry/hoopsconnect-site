import 'package:unorm_dart/unorm_dart.dart' as unicode;

/// Repository-pinned Unicode NFC implementation shared by every official-stat
/// canonical encoder and calculator.
///
/// The implementation is the vendored Unicode 17 `unorm_dart` 0.3.2 source
/// with the reviewed Hangul range boundary correction documented under
/// `third_party/unorm_dart/HOOPSCONNECT_PATCH.md`.
abstract final class OfficialStatUnicodeNormalization {
  static const String implementationVersion =
      'unicode-17.0-unorm-dart-0.3.2-hangul-boundary-patch1';

  static String nfc(String value) => unicode.nfc(value);
}
