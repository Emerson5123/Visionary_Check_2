import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, 'visionary_check.db');

    return await openDatabase(
      path,
      version: 3, // ← v3 agrega tabla statistics
      onCreate: (db, version) async {
        await _createAllTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 → v2: columna currency
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE bill_records ADD COLUMN currency TEXT NOT NULL DEFAULT 'UNKNOWN'",
          );
        }
        // v2 → v3: tabla statistics
        if (oldVersion < 3) {
          await _createStatisticsTable(db);
        }
      },
    );
  }

  Future<void> _createAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE bill_records (
        id          TEXT PRIMARY KEY,
        date        TEXT NOT NULL,
        imagePath   TEXT NOT NULL,
        isAuthentic INTEGER NOT NULL,
        confidence  TEXT NOT NULL,
        denomination TEXT NOT NULL,
        currency    TEXT NOT NULL DEFAULT 'UNKNOWN',
        createdAt   TEXT NOT NULL
      )
    ''');
    await _createStatisticsTable(db);
  }

  Future<void> _createStatisticsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS statistics (
        id                  TEXT PRIMARY KEY,
        totalVerifications  INTEGER NOT NULL DEFAULT 0,
        authenticsCount     INTEGER NOT NULL DEFAULT 0,
        fakesCount          INTEGER NOT NULL DEFAULT 0,
        lastUpdated         TEXT NOT NULL
      )
    ''');
  }
}