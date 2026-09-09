import 'indexed_db_journal_store.dart';
import 'journal_store.dart';

LocalGameJournalStore createLocalGameJournalStore({String? storageName}) =>
    IndexedDbLocalGameJournalStore(
      databaseName: storageName ?? 'hoopsconnect_local_game_journal',
    );
