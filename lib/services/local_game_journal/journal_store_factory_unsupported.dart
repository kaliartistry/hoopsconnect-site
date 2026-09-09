import 'journal_error.dart';
import 'journal_store.dart';

LocalGameJournalStore createLocalGameJournalStore({String? storageName}) =>
    _UnsupportedLocalGameJournalStore();

final class _UnsupportedLocalGameJournalStore implements LocalGameJournalStore {
  static const _capability = LocalStorageCapability(
    availability: LocalCaptureAvailability.disabledStorageUnavailable,
    adapter: 'unsupported',
    durable: false,
    transactional: false,
    encryptedAtRestClaimed: false,
    localSchemaVersion: 0,
    reasonCode: LocalJournalErrorCode.storageUnavailable,
  );

  @override
  LocalStorageCapability get capability => _capability;

  @override
  Future<LocalStorageCapability> open() async => _capability;

  @override
  Future<T> transaction<T>(
    Future<T> Function(LocalJournalStoreTransaction transaction) action,
  ) => throw LocalJournalException(
    LocalJournalErrorCode.storageUnavailable,
    'No durable local journal adapter exists on this platform',
  );

  @override
  Future<void> close() async {}
}
