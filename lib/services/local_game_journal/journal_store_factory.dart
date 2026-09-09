export 'journal_store_factory_unsupported.dart'
    if (dart.library.io) 'journal_store_factory_native.dart'
    if (dart.library.js_interop) 'journal_store_factory_web.dart';
