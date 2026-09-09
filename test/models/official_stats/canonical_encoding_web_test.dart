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

  test('browser NFC keeps the first post-Hangul scalar distinct from Jamo', () {
    const lastSyllable = '\uD7A3';
    const decomposedLastSyllable = '\u1112\u1175\u11C2';
    const firstAfterHangul = '\uD7A4';
    const followingJamoPair = '\u1113\u1161';

    expect(
      OfficialStatCanonicalEncoding.encode({'text': decomposedLastSyllable}),
      OfficialStatCanonicalEncoding.encode({'text': lastSyllable}),
    );
    expect(
      OfficialStatCanonicalEncoding.encode({'text': firstAfterHangul}),
      isNot(OfficialStatCanonicalEncoding.encode({'text': followingJamoPair})),
    );
    expect(
      OfficialStatCanonicalEncoding.sha256Hex({'text': firstAfterHangul}),
      'c8e54b190098560dec440e828e00176fc1b2f555a31dd56014b6b8787278faaf',
    );
  });

  test('browser NFC follows the Unicode 17 combining-order sentinel', () {
    expect(
      OfficialStatCanonicalEncoding.encode({'text': 'a\u1ACF\u0323'}),
      '{"text":"ạ᫏"}',
    );
    expect(
      OfficialStatCanonicalEncoding.sha256Hex({'text': 'a\u1ACF\u0323'}),
      'db4cd44367fe4b2a54e20efa6b4ef3dc0df5becaabdbb199f2c964abcc29e310',
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
