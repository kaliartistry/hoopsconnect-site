{{flutter_js}}
{{flutter_build_config}}

// The release bundle already contains CanvasKit. Loading that copy keeps the
// renderer version tied to the Flutter engine and avoids a remote renderer
// dependency during the first app frame.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});
