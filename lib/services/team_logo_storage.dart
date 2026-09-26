import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

class TeamLogoStorage {
  TeamLogoStorage({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Future<String> upload({
    required String associationId,
    required String teamId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty || bytes.lengthInBytes > 2 * 1024 * 1024) {
      throw ArgumentError('Team logos must be between 1 byte and 2 MB.');
    }
    final extension = _extension(fileName);
    final reference = _storage.ref(
      'associations/$associationId/teams/$teamId/logo.$extension',
    );
    await reference.putData(
      bytes,
      SettableMetadata(
        contentType: _contentType(extension),
        cacheControl: 'public,max-age=86400',
        customMetadata: {'associationId': associationId, 'teamId': teamId},
      ),
    );
    return reference.getDownloadURL();
  }
}

String _extension(String fileName) {
  final value = fileName.toLowerCase();
  if (value.endsWith('.jpg') || value.endsWith('.jpeg')) return 'jpg';
  if (value.endsWith('.webp')) return 'webp';
  return 'png';
}

String _contentType(String extension) => switch (extension) {
  'jpg' => 'image/jpeg',
  'webp' => 'image/webp',
  _ => 'image/png',
};
