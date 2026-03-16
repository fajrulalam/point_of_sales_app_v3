import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:point_of_sales_app_v3/Models/RecommendationModels.dart';
import 'package:point_of_sales_app_v3/Models/Member.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('recommendations.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE members (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          phoneNumber TEXT NOT NULL,
          memberId TEXT,
          points INTEGER DEFAULT 0,
          createdAt TEXT
        )
      ''');
      await db.execute('''
        CREATE INDEX idx_member_name ON members(name)
      ''');
    }
    if (oldVersion < 4) {
      // Simplest way for a cache table: drop and recreate
      await db.execute('DROP TABLE IF EXISTS members');
      await _createMembersTable(db);
    }
  }

  Future<void> _createMembersTable(Database db) async {
    await db.execute('''
      CREATE TABLE members (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phoneNumber TEXT NOT NULL,
        memberId TEXT,
        points INTEGER DEFAULT 0,
        createdAt TEXT,
        category TEXT,
        asrama TEXT,
        dateOfBirth TEXT,
        email TEXT,
        faculty TEXT,
        gender TEXT,
        institution TEXT,
        major TEXT,
        residence TEXT,
        unitEducation TEXT,
        workLocation TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_member_name ON members(name)
    ''');
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        antecedents TEXT NOT NULL,
        consequents TEXT NOT NULL,
        confidence REAL NOT NULL,
        support REAL NOT NULL,
        lift REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _createMembersTable(db);

    // Create initial index
    await db.execute('''
      CREATE INDEX idx_antecedents ON rules(antecedents)
    ''');
  }

  // Insert a single rule
  Future<int> insertRule(AssociationRule rule) async {
    final db = await database;
    return await db.insert('rules', rule.toMap());
  }

  // Insert multiple rules (bulk insert for efficiency)
  Future<void> insertRules(List<AssociationRule> rules) async {
    final db = await database;
    final batch = db.batch();

    for (var rule in rules) {
      batch.insert('rules', rule.toMap());
    }

    await batch.commit(noResult: true);
  }

  // Get all rules
  Future<List<AssociationRule>> getAllRules() async {
    final db = await database;
    final result = await db.query('rules');
    return result.map((map) => AssociationRule.fromMap(map)).toList();
  }

  // Get rules where antecedents contain specific items
  Future<List<AssociationRule>> getRulesContaining(List<String> items) async {
    final db = await database;
    final result = await db.query('rules');

    // Filter in memory (more flexible for set matching)
    return result.map((map) => AssociationRule.fromMap(map)).where((rule) {
      // Check if ordered items contain any of the antecedents
      return rule.antecedents
          .any((antecedent) => items.contains(antecedent.toLowerCase().trim()));
    }).toList();
  }

  // Clear all rules
  Future<void> clearRules() async {
    final db = await database;
    await db.delete('rules');
  }

  // Get metadata
  Future<String?> getMetadata(String key) async {
    final db = await database;
    final result = await db.query(
      'metadata',
      where: 'key = ?',
      whereArgs: [key],
    );

    if (result.isNotEmpty) {
      return result.first['value'] as String;
    }
    return null;
  }

  // Set metadata
  Future<void> setMetadata(String key, String value) async {
    final db = await database;
    await db.insert(
      'metadata',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get count of rules
  Future<int> getRuleCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM rules');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }

  // Delete database (for testing or full refresh)
  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'recommendations.db');
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }

  // Member Operations
  Future<void> insertMembers(List<Member> members) async {
    final db = await database;
    final batch = db.batch();

    for (var member in members) {
      batch.insert(
        'members', 
        member.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> insertMember(Member member) async {
    final db = await database;
    await db.insert(
      'members',
      member.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Member>> getAllMembers() async {
    final db = await database;
    final result = await db.query('members', orderBy: 'name ASC');
    return result.map((map) => Member.fromMap(map)).toList();
  }

  Future<void> clearMembers() async {
    final db = await database;
    await db.delete('members');
  }

  Future<List<Member>> searchMembers(String query) async {
    final db = await database;
    final result = await db.query(
      'members',
      where: 'name LIKE ? OR phoneNumber LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'name ASC',
    );
    return result.map((map) => Member.fromMap(map)).toList();
  }
}
