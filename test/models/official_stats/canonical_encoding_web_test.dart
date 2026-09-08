import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';

void main() {
  const zeroHash =
      '5feceb66ffc86f38d952786c6d696c79c2dbc239dd4e91b46729d73a27fb57e9';

  test('browser runtime canonicalizes every direct and parsed zero as 0', () {
    final values = <Object?>[
      0,
      -0.0,
      jsonDecode('0'),
      jsonDecode('-0'),
      jsonDecode('0.0'),
      jsonDecode('-0.0'),
    ];

    for (final value in values) {
      final canonical = OfficialStatCanonicalEncoding.encode(value);
      expect(canonical, '0', reason: '$value (${value.runtimeType})');
      expect(utf8.encode(canonical), <int>[48]);
      expect(OfficialStatCanonicalEncoding.sha256Hex(value), zeroHash);
    }
  });

  test('browser runtime normalizes nested map and list zeros', () {
    final input = <String, Object?>{
      'positive': 0.0,
      'list': <Object?>[0, -0.0, jsonDecode('-0'), jsonDecode('-0.0')],
      'negative': -0.0,
    };
    const canonical = '{"list":[0,0,0,0],"negative":0,"positive":0}';

    expect(OfficialStatCanonicalEncoding.encode(input), canonical);
    expect(
      utf8.encode(OfficialStatCanonicalEncoding.encode(input)),
      utf8.encode(canonical),
    );
    expect(
      OfficialStatCanonicalEncoding.sha256Hex(input),
      '301285d9b8c9ff3dd0ef41a2a3169e6908b7513bf8f6de2739c1bf2d8de1aab1',
    );
  });

  test(
    'browser runtime preserves safe integers and rejects invalid numbers',
    () {
      expect(
        OfficialStatCanonicalEncoding.encode(-9007199254740991),
        '-9007199254740991',
      );
      expect(
        OfficialStatCanonicalEncoding.encode(9007199254740991),
        '9007199254740991',
      );
      expect(OfficialStatCanonicalEncoding.encode(1.0), '1');
      expect(OfficialStatCanonicalEncoding.encode(jsonDecode('1e0')), '1');

      for (final value in <Object?>[
        -9007199254740992,
        9007199254740992,
        -0.5,
        0.5,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => OfficialStatCanonicalEncoding.encode(value),
          throwsFormatException,
          reason: '$value (${value.runtimeType})',
        );
      }
    },
  );
}
