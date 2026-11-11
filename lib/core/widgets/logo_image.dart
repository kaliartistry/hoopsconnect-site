import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// Exact published object paths for the supplied 2025 artwork. The bundled
// files have the same content hashes. A new upload keeps its own URL and is
// never replaced by a name-based match.
const _archiveLogos = {
  '706cd29a5225774f/jbl_full.png',
  '9c0ce4199145c68f/jbl_foska.png',
  '122c4c0e22045b67/jbl_flames.png',
  '2a572f3035e35111/jbl_spartans.png',
  '643e5e004033a46a/jbl_eagles.png',
  '6ba209b2d8c487d5/jbl_tivoli.png',
  '8241bfdbfe0da707/jbl_celtics.png',
  '88d4515a861eed92/jbl_raptors.png',
  'a2d43a03fdd81ffd/jbl_knights.png',
  'ac0efe82545b57b0/jbl_slayers.png',
  'acf9d7187042a833/jbl_rebels.png',
  'cb590d38cd42fc10/jbl_warriors.png',
};

String? _localAsset(String reference) {
  if (reference.startsWith('asset:')) return reference.substring(6);
  final uri = Uri.tryParse(reference);
  if (uri?.scheme != 'https' || uri?.host != 'firebasestorage.googleapis.com') {
    return null;
  }
  final segments = uri!.pathSegments;
  if (segments.length != 5 ||
      segments[0] != 'v0' ||
      segments[1] != 'b' ||
      !const {
        'hoops-connect-jm.firebasestorage.app',
        'hoopsconnect-jba-staging.firebasestorage.app',
      }.contains(segments[2]) ||
      segments[3] != 'o') {
    return null;
  }
  const prefix = 'public/jbl/2025-first-round/';
  final object = segments.last;
  if (!object.startsWith(prefix) ||
      !_archiveLogos.contains(object.substring(prefix.length))) {
    return null;
  }
  return 'assets/images/${object.split('/').last}';
}

typedef LogoImageKey = (Object, bool);

/// Uses Flutter's image cache for the resized, verified logo. A successful
/// download and decode can still produce a blank image (e.g. a transparent
/// placeholder), which must not displace the initials.
class LogoImage extends ImageProvider<LogoImageKey> {
  LogoImage(this.reference, {required this.maxPixels, required this.onWhite})
    : _provider = ResizeImage(
        switch (_localAsset(reference)) {
          final String asset => AssetImage(asset),
          null when kIsWeb => NetworkImage(reference),
          null => CachedNetworkImageProvider(reference),
        },
        width: maxPixels,
        height: maxPixels,
        policy: ResizeImagePolicy.fit,
      );

  final ImageProvider<Object> _provider;
  final String reference;
  final int maxPixels;
  final bool onWhite;

  @override
  Future<LogoImageKey> obtainKey(ImageConfiguration configuration) =>
      _provider.obtainKey(configuration).then((key) => (key, onWhite));

  @override
  ImageStreamCompleter loadImage(
    LogoImageKey key,
    ImageDecoderCallback decode,
  ) => _provider.loadImage(key.$1, (buffer, {getTargetSize}) async {
    final codec = await decode(buffer, getTargetSize: getTargetSize);
    return _VisibleLogoCodec(codec, onWhite: key.$2);
  });

  @override
  bool operator ==(Object other) =>
      other is LogoImage &&
      other.reference == reference &&
      other.maxPixels == maxPixels &&
      other.onWhite == onWhite;

  @override
  int get hashCode => Object.hash(reference, maxPixels, onWhite);
}

class _VisibleLogoCodec implements ui.Codec {
  _VisibleLogoCodec(this.codec, {required this.onWhite});

  final ui.Codec codec;
  final bool onWhite;

  @override
  int get frameCount => codec.frameCount;

  @override
  int get repetitionCount => codec.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      if (image.width < 2 || image.height < 2) {
        throw const FormatException('Logo is too small');
      }
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels != null) {
        for (var i = 0; i < pixels.lengthInBytes; i += 4) {
          final alpha = pixels.getUint8(i + 3);
          if (alpha < 32) continue;
          // rawRgba is premultiplied. On a white plate, a channel is visible
          // only if it is sufficiently darker than the pixel's own alpha.
          if (!onWhite ||
              alpha - pixels.getUint8(i) >= 16 ||
              alpha - pixels.getUint8(i + 1) >= 16 ||
              alpha - pixels.getUint8(i + 2) >= 16) {
            return frame;
          }
        }
      }
      throw const FormatException('Logo has no visible artwork');
    } catch (_) {
      image.dispose();
      rethrow;
    }
  }

  @override
  void dispose() => codec.dispose();
}
