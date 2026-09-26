/// Compile-time controls for the unlisted, public presentation build.
///
/// The preview uses a bundled synthetic public snapshot and keeps account
/// actions disabled so a showcase cannot create or change production data.
class PresentationPreviewEnvironment {
  static const enabled = bool.fromEnvironment(
    'HOOPSCONNECT_PRESENTATION_PREVIEW',
  );
}
