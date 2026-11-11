{{flutter_js}}
{{flutter_build_config}}

async function removeLegacyAppShellWorker() {
  if (!('serviceWorker' in navigator)) return;
  const registrations = await navigator.serviceWorker.getRegistrations();
  const legacyRegistration = registrations.find((registration) => {
    const worker = registration.active || registration.waiting || registration.installing;
    return worker && new URL(worker.scriptURL).pathname.endsWith('/flutter_service_worker.js');
  });
  if (!legacyRegistration) return;

  // Flutter 3.41 emits an unregister-only worker. Register it only when an
  // older app-shell worker already exists, so update users are released from
  // stale cached assets while fresh users do not acquire a persistent cache.
  await navigator.serviceWorker.register('flutter_service_worker.js', {
    scope: legacyRegistration.scope,
    updateViaCache: 'none',
  });
}

removeLegacyAppShellWorker()
  .catch((error) => console.warn('Unable to schedule stale worker cleanup.', error));

function bootFailed(error) {
  console.error('HoopsConnect startup failed.', error);
  window.dispatchEvent(new Event('hoops-bootstrap-error'));
}

// The release bundle already contains CanvasKit. Keep the renderer tied to the
// Flutter engine and do not make app startup depend on worker cleanup.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
  onEntrypointLoaded: async (initializer) => {
    try {
      const runner = await initializer.initializeEngine();
      await runner.runApp();
    } catch (error) {
      bootFailed(error);
    }
  },
}).catch(bootFailed);
