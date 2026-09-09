import 'journal_store.dart';
import 'sqlite_journal_store.dart';

LocalGameJournalStore createLocalGameJournalStore({String? storageName}) =>
    SqliteLocalGameJournalStore(
      databaseName: storageName ?? 'hoopsconnect_local_game_journal.sqlite3',
    );
