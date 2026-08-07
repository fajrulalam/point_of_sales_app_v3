import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart';
import 'package:point_of_sales_app_v3/Models/RecommendationModels.dart';
import 'package:point_of_sales_app_v3/Services/DatabaseHelper.dart';

/// Result of recommendation service initialization
class RecommendationInitResult {
  final bool success;
  final int ruleCount;
  final String? errorMessage;

  RecommendationInitResult({
    required this.success,
    required this.ruleCount,
    this.errorMessage,
  });
}

class RecommendationService {
  static final RecommendationService instance = RecommendationService._init();
  final DatabaseHelper _db = DatabaseHelper.instance;

  RecommendationConfig? _config;
  bool _isInitialized = false;
  int _lastRuleCount = 0;

  // Item normalization map - maps canonical names to all aliases (for merging during matching)
  // Also used for de-merging: expanding canonical names back to all variations for recommendations
  static final Map<String, List<String>> itemMerges = {
    'tahu krispy': ['Tahu Krispy', 'Tahu Crispy', 'Tahu G'],
    'nasi goreng': ['Nasi Goreng'],
    'french fries': ['Kentang Goreng', 'French Fries', 'Kentang G'],
    'nasi ayam silep': ['Ayam Silep', 'Nasi Ayam Silep'],
    'soto ayam': ['Soto Ayam', 'Soto'],
    'telur': [
      'Telur Mata Sapi',
      'Telor Matasapi',
      'Telur Dadar',
      'Telur Ceplok'
    ],
    'nasi telur': ['Nasi Telur'],
    'cireng isi': ['Cireng Isi', 'Cireng', 'Cireng Isi Ayam'],
    'sosis goreng': ['Sosis Goreng', 'Sosis', 'Sosis 1rb', 'Sosis 1k'],
    'mie': [
      'Mie',
      'Masak Mie + Telur',
      'Masak Mie+Telur',
      'Masak Mie',
      'Mie Tanpa Telur',
      'Mie (Tanpa Telur)'
    ],
    'nasi sosis goreng': ['Nasi Sosis Goreng'],
    'gorengan': ['Gorengan', 'Martabak Mini'],
    'ayam silep (tanpa nasi)': ['Ayam Silep (Tanpa Nasi)'],
    'nasi putih': ['Nasi Putih', 'Nasi'],
    'air putih': [
      'Aqua 600ml',
      'Air Mineral',
      'Club',
      'Aqua',
      'Air Gelas',
      'Air Panas',
      'Es Batu/Air Panas',
      'Air Panas+Gula'
    ],
    'slushy': ['Es Salju', 'Es Salju (Slushy)'],
    'teh panas': ['Teh Panas', 'Teh Hangat'],
    'es batu': ['Es Batu'],
    'kerupuk': ['Krupuk', 'Kerupuk', 'Kerupuk Udang'],
    'es krim': ['Es Krim'],
    'es jeruk': ['Jeruk Hangat', 'Es Jeruk'],
    'sayur harian': [
      'Sayur Asem Lele',
      'Sayur Sop Tempe Goreng',
      'Sayur Asem Tempe Goreng',
      'Sayur Asem Tempe',
      'Sayur Sop Telur Goreng',
      'Sayur Asem Telur Goreng',
      'Sayur Asem Dadar',
      'Sayur Asem Telur',
      'Sayur Asem Ayam',
      'Sayur Asem Ayam Goreng',
      'Sayur Sop Ayam Goreng',
      'Kuah Sayur Harian',
      'Sayur Asem Pindang',
      'Sayur Asem Mujaer',
      'Pecel Saja',
      'Capjay',
      'Gado-Gado',
      'Urap-Urap Bandeng',
      'Urap-Urap Udang',
      'Sayur Asem Udang',
      'Kuah Sop',
      'Sop',
      'Kuah Gurih Cecek',
      'Soto Ayam',
      'Sayur Harian Mata Sapi',
      'Sayur Harian Tempe',
      'Sayur Harian Dadar',
      'Sayur Harian Ayam',
      'Sayur Harian Lele'
    ],
    'penyetan': [
      'Penyetan Telur',
      'Penyetan Dadar',
      'Penyetan Dadar Tanpa Nasi',
      'Penyetan Mata Sapi',
      'Penyetan Lele',
      'Penyetan Lele Tanpa Nasi',
      'Penyetan Ayam',
      'Penyetan Ayam Tanpa Nasi',
      'Penyetan Tempe',
      'Pecel Tempe',
      'Penyetan Pindang',
      'Nasi+Mujair',
      'Sambelan',
      'Penyetan Ikan Asin',
      'Brengkesan Pindang'
    ],
    'kopi': [
      'Es Kopi',
      'Kopi Panas',
      'Es Kopi/Chocolatos',
      'Kopi Hitam',
      'Aneka Kopi',
      'Kopi Susu',
      'Es Chocolatos',
      'Chocolatos Panas',
      'Es Susu',
      'Es Milo',
      'Es Beng Beng'
    ],
    'float': [
      'Coffee Float',
      'Tea Float',
      'Orange Float',
      'Chocolatos Float',
      'Coca Cola Float',
      'Milo Float',
      'Jeruk Float',
      'Kopi Float',
      'Es Teh Float'
    ],
    'teh': ['Teh', 'Teh Panas', 'Es Teh'],
    'risol mayo': ['Risol Mayo'],
    'pisang coklat keju': ['Pisang Coklat Keju'],
  };

  /// Expand a canonical item name to all its variations
  /// Example: 'mie' -> ['Mie', 'Masak Mie + Telur', 'Masak Mie', ...]
  List<String> expandItemName(String canonicalName) {
    final normalized = canonicalName.toLowerCase().trim();
    if (itemMerges.containsKey(normalized)) {
      return itemMerges[normalized]!;
    }
    // If not in the merge map, return the original name with proper casing
    return [_toTitleCase(canonicalName)];
  }

  /// Convert string to Title Case
  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  RecommendationService._init();

  /// Normalize an item name to its canonical form
  /// Example: "kentang goreng" -> "french fries"
  String normalizeItemName(String itemName) {
    final normalized = itemName.toLowerCase().trim();

    // Check each canonical name and its aliases
    for (final entry in itemMerges.entries) {
      final canonicalName = entry.key;
      final aliases = entry.value;

      // Check if the item matches any alias (case-insensitive)
      for (final alias in aliases) {
        if (normalized == alias.toLowerCase()) {
          return canonicalName;
        }
      }
    }

    // If no match found, return the normalized original
    return normalized;
  }

  /// Initialize the recommendation system
  /// Call this on app startup
  /// Returns RecommendationInitResult with success status and rule count
  Future<RecommendationInitResult> initialize() async {
    if (_isInitialized) {
      return RecommendationInitResult(
        success: true,
        ruleCount: _lastRuleCount,
      );
    }

    try {
      print('🔄 Initializing recommendation system...');

      // 1. Wait for authentication if not ready
      await _waitForAuth();

      // 2. Load configuration from Firestore
      _config = await _loadConfig();

      if (!_config!.enabled) {
        print('⚠️ Recommendation system is disabled');
        _isInitialized = true;
        _lastRuleCount = 0;
        return RecommendationInitResult(
          success: true,
          ruleCount: 0,
          errorMessage: 'Sistem rekomendasi sedang dinonaktifkan',
        );
      }

      // 2. Check if we need to update rules
      final storedVersion = await _db.getMetadata('version');
      final ruleCount = await _db.getRuleCount();
      final needsUpdate = storedVersion != _config!.version || ruleCount == 0;

      if (needsUpdate) {
        if (storedVersion != _config!.version) {
          print(
              '📥 Downloading new rules (version changed: $storedVersion → ${_config!.version})...');
        } else if (ruleCount == 0) {
          print('📥 Re-downloading rules (database is empty)...');
        }
        await _downloadAndUpdateRules();
      } else {
        print('✅ Rules are up to date (version: $storedVersion)');
      }

      final finalRuleCount = await _db.getRuleCount();
      _lastRuleCount = finalRuleCount;
      print('✅ Recommendation system initialized with $finalRuleCount rules');

      _isInitialized = true;
      return RecommendationInitResult(
        success: true,
        ruleCount: finalRuleCount,
      );
    } catch (e) {
      print('❌ Error initializing recommendation system: $e');
      // Don't throw - allow app to continue without recommendations
      _isInitialized = false;
      return RecommendationInitResult(
        success: false,
        ruleCount: 0,
        errorMessage: e.toString(),
      );
    }
  }

  /// Get the last known rule count
  int get lastRuleCount => _lastRuleCount;

  /// Load configuration from Firestore
  Future<RecommendationConfig> _loadConfig() async {
    try {
      print('🔄 Loading recommendation config from Firestore...');
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('recommendations')
          .get();

      if (doc.exists && doc.data() != null) {
        final config = RecommendationConfig.fromFirestore(doc.data()!);
        print(
            '✅ Config loaded: version=${config.version}, file=${config.csvFileName}');
        return config;
      } else {
        print('⚠️ Config document does not exist in Firestore, using defaults');
      }
    } catch (e) {
      print('⚠️ Error loading config from Firestore: $e');
      print('💡 This is likely due to permissions. Using default config.');
    }

    final defaultConfig = RecommendationConfig.defaultConfig();
    print(
        'ℹ️ Using default config: version=${defaultConfig.version}, file=${defaultConfig.csvFileName}');
    return defaultConfig;
  }

  /// Wait for Firebase Auth to be initialized/signed in
  Future<void> _waitForAuth() async {
    int attempts = 0;
    while (FirebaseAuth.instance.currentUser == null && attempts < 10) {
      print(
          '⏳ Waiting for Firebase Authentication... (attempt ${attempts + 1})');
      await Future.delayed(const Duration(milliseconds: 1000));
      attempts++;
    }

    if (FirebaseAuth.instance.currentUser != null) {
      print('✅ Authenticated as: ${FirebaseAuth.instance.currentUser?.uid}');
    } else {
      print('⚠️ Authentication timeout after 10s. Proceeding anyway...');
    }
  }

  /// Download rules file from Firebase Storage and update local database
  Future<void> _downloadAndUpdateRules() async {
    try {
      final fileName = _config!.csvFileName;
      final isExcel = fileName.toLowerCase().endsWith('.xlsx') ||
          fileName.toLowerCase().endsWith('.xls');

      // 1. Download file
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('recommendation_rules/$fileName');

      final tempDir = await getTemporaryDirectory();
      final extension = isExcel ? '.xlsx' : '.csv';
      final tempFile = File('${tempDir.path}/rules_temp$extension');

      await storageRef.writeToFile(tempFile);
      print('✅ File downloaded successfully (${isExcel ? 'XLSX' : 'CSV'})');

      // 2. Parse file based on type
      final List<AssociationRule> rules;
      if (isExcel) {
        rules = await _parseExcel(tempFile);
        print('✅ Parsed ${rules.length} rules from XLSX');
      } else {
        final csvString = await tempFile.readAsString();
        rules = await _parseCSV(csvString);
        print('✅ Parsed ${rules.length} rules from CSV');
      }

      // 3. Clear old rules and insert new ones
      await _db.clearRules();
      await _db.insertRules(rules);

      // 4. Update metadata
      await _db.setMetadata('version', _config!.version);
      await _db.setMetadata('lastUpdated', DateTime.now().toIso8601String());

      // 5. Clean up temp file
      await tempFile.delete();

      print('✅ Rules database updated successfully');
    } catch (e) {
      print('❌ Error downloading/updating rules: $e');
      rethrow;
    }
  }

  /// Parse CSV string into list of AssociationRule objects
  /// Supports two formats:
  /// 1. Simple format: item1;item2,item3,0.5 (semicolon-separated items, comma-separated columns)
  /// 2. Frozenset format: frozenset({'item1'; 'item2'}),frozenset({'item3'}),0.5
  Future<List<AssociationRule>> _parseCSV(String csvString) async {
    final List<AssociationRule> rules = [];

    print('📄 CSV String length: ${csvString.length} characters');
    print('📄 First 500 characters of CSV:');
    print(csvString.substring(
        0, csvString.length > 500 ? 500 : csvString.length));

    // Split by lines and process each line manually
    final lines = csvString.split('\n');
    print('📊 Total lines in CSV: ${lines.length}');

    // Detect format from first data line
    bool isFrozensetFormat = false;
    if (lines.length > 1) {
      isFrozensetFormat = lines[1].contains('frozenset');
      print(
          '📋 Detected format: ${isFrozensetFormat ? "frozenset" : "simple"}');
    }

    // Regex pattern for frozenset format
    final frozensetPattern = RegExp(
      r"frozenset\(\{([^}]*)\}\)[,\s]*frozenset\(\{([^}]*)\}\)[,\s]*([\d.]+)",
      caseSensitive: false,
    );

    // Log first 5 lines for debugging
    print('🔍 ===== FIRST 5 LINES FROM CSV =====');
    for (int i = 0; i < (lines.length > 5 ? 5 : lines.length); i++) {
      print('Line $i: ${lines[i]}');
    }
    print('====================================');

    // Skip header row (line 0)
    for (int i = 1; i < lines.length; i++) {
      try {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        // Remove surrounding quotes if the entire line is quoted (CSV escaping)
        String cleanLine = line;
        if (cleanLine.startsWith('"') && cleanLine.endsWith('"')) {
          cleanLine = cleanLine.substring(1, cleanLine.length - 1);
          cleanLine = cleanLine.replaceAll('""', '"');
        }

        List<String> antecedents;
        List<String> consequents;
        double confidence;

        if (isFrozensetFormat) {
          // Parse frozenset format
          final match = frozensetPattern.firstMatch(cleanLine);
          if (match == null) {
            if (i <= 5) {
              print('⚠️ Line $i: No frozenset pattern match found');
              print('   Line content: $cleanLine');
            }
            continue;
          }

          final antecedentsRaw = match.group(1) ?? '';
          final consequentsRaw = match.group(2) ?? '';
          final confidenceRaw = match.group(3) ?? '0';

          antecedents = _parseItemsFromFrozensetContent(antecedentsRaw);
          consequents = _parseItemsFromFrozensetContent(consequentsRaw);
          confidence = double.tryParse(confidenceRaw) ?? 0.0;
        } else {
          // Parse simple format: antecedents,consequents,confidence
          // Items within antecedents/consequents are separated by semicolons
          final parts = cleanLine.split(',');
          if (parts.length < 3) {
            if (i <= 5) {
              print('⚠️ Line $i: Insufficient columns (${parts.length})');
            }
            continue;
          }

          final antecedentsRaw = parts[0].trim();
          final consequentsRaw = parts[1].trim();
          final confidenceRaw = parts[2].trim();

          // Split by semicolon for multiple items
          antecedents = _parseSimpleItemList(antecedentsRaw);
          consequents = _parseSimpleItemList(consequentsRaw);
          confidence = double.tryParse(confidenceRaw) ?? 0.0;
        }

        if (i <= 5) {
          print('🔍 Line $i - Antecedents parsed: $antecedents');
          print('🔍 Line $i - Consequents parsed: $consequents');
          print('🔍 Line $i - Confidence parsed: $confidence');
        }

        // Create rule
        if (antecedents.isNotEmpty && consequents.isNotEmpty) {
          rules.add(AssociationRule(
            id: i,
            antecedents: antecedents,
            consequents: consequents,
            confidence: confidence,
            support: 0.0,
            lift: 0.0,
          ));
        } else {
          if (i <= 5) {
            print(
                '⚠️ Line $i skipped: antecedents empty=${antecedents.isEmpty}, consequents empty=${consequents.isEmpty}');
          }
        }
      } catch (e) {
        print('⚠️ Error parsing line $i: $e');
        // Continue with other lines
      }
    }

    print(
        '✅ Successfully parsed ${rules.length} rules from ${lines.length - 1} data lines');

    return rules;
  }

  /// Parse items from the content inside a frozenset (without the frozenset wrapper)
  /// Example: "'nasi putih'; 'cireng isi'" -> ['nasi putih', 'cireng isi']
  List<String> _parseItemsFromFrozensetContent(String content) {
    if (content.trim().isEmpty) return [];

    // Each item is wrapped in single quotes, extract them using regex
    final itemPattern = RegExp(r"'([^']*)'");
    final matches = itemPattern.allMatches(content);

    return matches
        .map((m) => m.group(1)?.toLowerCase().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  /// Parse simple item list (no quotes, semicolon-separated)
  /// Example: "nasi putih;cireng isi" -> ['nasi putih', 'cireng isi']
  /// Example: "mie" -> ['mie']
  List<String> _parseSimpleItemList(String content) {
    if (content.trim().isEmpty) return [];

    // Split by semicolon for multiple items
    return content
        .split(';')
        .map((item) => item.toLowerCase().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  /// Parse XLSX file into list of AssociationRule objects using column names
  Future<List<AssociationRule>> _parseExcel(File excelFile) async {
    final List<AssociationRule> rules = [];

    try {
      print('📊 Reading XLSX file...');
      print('📊 File path: ${excelFile.path}');
      print('📊 File exists: ${await excelFile.exists()}');
      print('📊 File size: ${await excelFile.length()} bytes');

      final bytes = await excelFile.readAsBytes();
      print('📊 Bytes read: ${bytes.length}');

      print('📊 Attempting to decode Excel file...');
      print(
          '💡 If this fails, your Excel file might be corrupted or have unsupported formatting.');

      Excel? excel;
      try {
        excel = Excel.decodeBytes(bytes);
        print('📊 Excel decoded successfully');
      } catch (e) {
        print('❌ Excel decoding failed: $e');
        print('');
        print('🔧 SOLUTION: Try one of these:');
        print('   1. Open Excel file → Save As → New file → Re-upload');
        print(
            '   2. Copy only antecedents, consequents, confidence columns to new sheet');
        print('   3. Save as CSV instead (simpler format)');
        print('   4. Check for cells with formulas or special formatting');
        print('');
        rethrow;
      }
      print('📊 Number of sheets: ${excel.tables.keys.length}');
      print('📊 Sheet names: ${excel.tables.keys.toList()}');

      if (excel.tables.isEmpty) {
        print('❌ Excel file has no sheets!');
        return rules;
      }

      // Get the first sheet
      final sheetName = excel.tables.keys.first;
      print('📊 Using sheet: $sheetName');

      final sheet = excel.tables[sheetName];

      if (sheet == null) {
        print('❌ Sheet "$sheetName" is null!');
        return rules;
      }

      print('📊 Sheet has ${sheet.maxRows} rows');

      if (sheet.maxRows == 0) {
        print('❌ Sheet is empty (0 rows)');
        return rules;
      }

      // Find column indices by name
      print('📊 Reading header row...');
      final headerRow = sheet.rows.first;
      print('📊 Header row has ${headerRow.length} cells');

      // Log all headers
      print('📊 ===== ALL COLUMN HEADERS =====');
      for (int i = 0; i < headerRow.length; i++) {
        final cell = headerRow[i];
        final cellValue = cell?.value;
        print('Column $i: value="$cellValue" (type: ${cellValue.runtimeType})');
      }
      print('==================================');

      int? antecedentsCol;
      int? consequentsCol;
      int? confidenceCol;

      for (int i = 0; i < headerRow.length; i++) {
        final cell = headerRow[i];
        if (cell == null || cell.value == null) {
          print('⚠️ Column $i: Cell or value is null');
          continue;
        }

        final cellValue = cell.value.toString().toLowerCase().trim();
        print('🔍 Column $i: "$cellValue"');

        if (cellValue == 'antecedents') {
          antecedentsCol = i;
          print('✅ Found antecedents at column $i');
        }
        if (cellValue == 'consequents') {
          consequentsCol = i;
          print('✅ Found consequents at column $i');
        }
        if (cellValue == 'confidence') {
          confidenceCol = i;
          print('✅ Found confidence at column $i');
        }
      }

      print(
          '🔍 Column indices - Antecedents: $antecedentsCol, Consequents: $consequentsCol, Confidence: $confidenceCol');

      if (antecedentsCol == null ||
          consequentsCol == null ||
          confidenceCol == null) {
        print(
            '❌ Required columns not found. Expected: antecedents, consequents, confidence');
        print(
            '📋 Found columns: ${headerRow.map((cell) => cell?.value?.toString()).toList()}');
        return rules;
      }

      // Log first 5 data rows
      print('🔍 ===== FIRST 5 ROWS FROM XLSX =====');
      for (int i = 1; i < (sheet.maxRows > 6 ? 6 : sheet.maxRows); i++) {
        final row = sheet.rows[i];
        print(
            'Row $i: Antecedents=${row[antecedentsCol]?.value}, Consequents=${row[consequentsCol]?.value}, Confidence=${row[confidenceCol]?.value}');
      }
      print('=====================================');

      // Parse each row (skip header)
      for (int i = 1; i < sheet.maxRows; i++) {
        try {
          final row = sheet.rows[i];

          final antecedentsRaw = row[antecedentsCol]?.value?.toString() ?? '';
          final consequentsRaw = row[consequentsCol]?.value?.toString() ?? '';
          final confidenceRaw = row[confidenceCol]?.value;

          if (antecedentsRaw.isEmpty || consequentsRaw.isEmpty) {
            if (i <= 5) {
              print('⚠️ Row $i: Empty antecedents or consequents, skipping');
            }
            continue;
          }

          // Parse frozenset strings
          final antecedents = _parseFrozenset(antecedentsRaw);
          final consequents = _parseFrozenset(consequentsRaw);

          if (i <= 3) {
            print('🔍 Row $i - Antecedents raw: $antecedentsRaw');
            print('🔍 Row $i - Consequents raw: $consequentsRaw');
            print('🔍 Row $i - Antecedents parsed: $antecedents');
            print('🔍 Row $i - Consequents parsed: $consequents');
          }

          // Parse confidence
          final confidence = _parseDouble(confidenceRaw);

          if (antecedents.isNotEmpty && consequents.isNotEmpty) {
            rules.add(AssociationRule(
              id: i,
              antecedents: antecedents,
              consequents: consequents,
              confidence: confidence,
              support: 0.0, // Optional in XLSX
              lift: 0.0, // Optional in XLSX
            ));
          } else {
            if (i <= 5) {
              print(
                  '⚠️ Row $i skipped: antecedents empty=${antecedents.isEmpty}, consequents empty=${consequents.isEmpty}');
            }
          }
        } catch (e) {
          print('⚠️ Error parsing row $i: $e');
        }
      }

      print(
          '✅ Successfully parsed ${rules.length} rules from ${sheet.maxRows - 1} data rows');
    } catch (e, stackTrace) {
      print('❌ Error reading Excel file: $e');
      print('📍 Stack trace:');
      print(stackTrace);

      // More specific error messages
      if (e.toString().contains('Null check operator')) {
        print('');
        print(
            '💡 This error means something expected to have a value is null.');
        print('💡 Common causes:');
        print('   1. Excel file might be corrupted');
        print('   2. Sheet might be empty');
        print('   3. Required columns might be missing');
        print('   4. Cell values might be null/empty');
        print('');
        print('🔧 Try:');
        print('   1. Open Excel file and verify it has data');
        print('   2. Save Excel file again (File > Save As)');
        print(
            '   3. Check column headers are: antecedents, consequents, confidence');
      }

      rethrow;
    }

    return rules;
  }

  /// Parse frozenset string to list of items
  /// Example: "frozenset({'ayam goreng'; 'nasi putih'})" -> ['ayam goreng', 'nasi putih']
  /// Supports both semicolon (;) and comma (,) as separators for backwards compatibility
  List<String> _parseFrozenset(String frozensetStr) {
    try {
      // Remove "frozenset({" and "})"
      final content = frozensetStr
          .replaceAll('frozenset({', '')
          .replaceAll('})', '')
          .trim();

      if (content.isEmpty) return [];

      // Use regex to extract quoted items - works with both ; and , separators
      final itemPattern = RegExp(r"'([^']*)'");
      final matches = itemPattern.allMatches(content);

      return matches
          .map((m) => m.group(1)?.toLowerCase().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
    } catch (e) {
      print('⚠️ Error parsing frozenset: $frozensetStr - $e');
      return [];
    }
  }

  /// Safely parse double from dynamic value
  double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Get recommendations based on current order items
  /// Returns canonical category names (e.g., 'mie', 'penyetan', 'teh')
  /// Use expandItemName() to get all variations for each category
  Future<List<Recommendation>> getRecommendations(
      List<String> orderItems) async {
    if (!_isInitialized || _config == null || !_config!.enabled) {
      print('⚠️ Recommendation system not initialized or disabled');
      return [];
    }

    if (orderItems.isEmpty) {
      return [];
    }

    try {
      // Normalize order items using item merges
      print('🔄 Normalizing order items...');
      final normalizedOrder = orderItems.map((item) {
        final normalized = normalizeItemName(item);
        if (normalized != item.toLowerCase().trim()) {
          print('   📝 "$item" → "$normalized"');
        }
        return normalized;
      }).toSet();

      print('📋 Normalized order: ${normalizedOrder.join(", ")}');

      // Get all rules from database
      final allRules = await _db.getAllRules();
      print('📊 Checking ${allRules.length} rules...');

      // Find matching rules and collect canonical consequents with their confidence
      final Map<String, double> canonicalRecommendations = {};
      final Map<String, List<String>> canonicalBasedOn = {};
      int rulesChecked = 0;
      int rulesMatched = 0;

      for (final rule in allRules) {
        rulesChecked++;

        // Normalize antecedents (they're already canonical from CSV)
        final normalizedAntecedents =
            rule.antecedents.map((item) => item.toLowerCase().trim()).toSet();

        // Calculate match percentage
        final matchCount = normalizedAntecedents
            .where((antecedent) => normalizedOrder.contains(antecedent))
            .length;

        final matchPercentage = matchCount / normalizedAntecedents.length;

        // Check if rule meets threshold
        if (matchPercentage >= _config!.matchThreshold &&
            rule.confidence >= _config!.minConfidence) {
          rulesMatched++;

          if (rulesMatched <= 3) {
            print(
                '✅ Rule matched: ${rule.antecedents.join(", ")} → ${rule.consequents.join(", ")} (${(rule.confidence * 100).toStringAsFixed(1)}%)');
          }

          // Add consequents that aren't already in the order
          for (final consequent in rule.consequents) {
            final normalizedConsequent = consequent.toLowerCase().trim();

            if (!normalizedOrder.contains(normalizedConsequent)) {
              // Keep the highest confidence for each canonical item
              if (!canonicalRecommendations.containsKey(normalizedConsequent) ||
                  canonicalRecommendations[normalizedConsequent]! <
                      rule.confidence) {
                canonicalRecommendations[normalizedConsequent] =
                    rule.confidence;
                canonicalBasedOn[normalizedConsequent] = rule.antecedents;
              }
            }
          }
        }
      }

      // Build recommendations list with canonical names (categories)
      final List<Recommendation> recommendations = [];

      for (final entry in canonicalRecommendations.entries) {
        final canonicalName = entry.key;
        final confidence = entry.value;
        final basedOn = canonicalBasedOn[canonicalName] ?? [];

        recommendations.add(Recommendation(
          itemName: _toTitleCase(canonicalName), // Display name
          confidence: confidence,
          basedOn: basedOn,
          ruleDescription: '${basedOn.join(", ")} → $canonicalName',
        ));
      }

      // Sort by confidence (descending)
      recommendations.sort((a, b) => b.confidence.compareTo(a.confidence));

      print(
          '📊 Summary: Checked $rulesChecked rules, matched $rulesMatched, found ${recommendations.length} category recommendations');

      // Apply max recommendations limit
      return recommendations.take(_config!.maxRecommendations).toList();
    } catch (e) {
      print('❌ Error generating recommendations: $e');
      return [];
    }
  }

  /// Get variations for a canonical item, filtered by available menu items
  /// Returns only variations that exist in the provided menu list
  List<String> getAvailableVariations(
      String canonicalName, List<String> menuItems) {
    final allVariations = expandItemName(canonicalName);

    // Normalize menu items for comparison
    final normalizedMenu = menuItems.map((m) => m.toLowerCase().trim()).toSet();

    // Filter to only include variations that exist in the menu
    return allVariations.where((variation) {
      return normalizedMenu.contains(variation.toLowerCase().trim());
    }).toList();
  }

  /// Force refresh rules from Firebase
  Future<void> forceRefresh() async {
    try {
      print('🔄 Forcing rules refresh...');
      _config = await _loadConfig();
      await _downloadAndUpdateRules();
      print('✅ Rules refreshed successfully');
    } catch (e) {
      print('❌ Error refreshing rules: $e');
      rethrow;
    }
  }

  /// Get current configuration
  RecommendationConfig? get config => _config;

  /// Check if system is initialized
  bool get isInitialized => _isInitialized;

  /// Get statistics
  Future<Map<String, dynamic>> getStatistics() async {
    final ruleCount = await _db.getRuleCount();
    final version = await _db.getMetadata('version');
    final lastUpdated = await _db.getMetadata('lastUpdated');

    return {
      'ruleCount': ruleCount,
      'version': version ?? 'unknown',
      'lastUpdated': lastUpdated ?? 'never',
      'enabled': _config?.enabled ?? false,
      'initialized': _isInitialized,
    };
  }
}
