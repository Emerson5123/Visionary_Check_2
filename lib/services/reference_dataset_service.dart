import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import 'package:uuid/uuid.dart';

class ReferenceDatasetService {
  static final ReferenceDatasetService _instance =
  ReferenceDatasetService._internal();
  final DatabaseService _databaseService = DatabaseService();

  factory ReferenceDatasetService() => _instance;
  ReferenceDatasetService._internal();

  /// Indexar dataset de assets
  Future<void> indexAssetDataset() async {
    try {
      print('🔍 Indexando dataset de assets...');

      final db = await _databaseService.database;

      // Verificar si ya está indexado
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM reference_dataset'),
      ) ?? 0;

      if (count > 0) {
        print('⚠️  Dataset ya indexado ($count registros)');
        return;
      }

      // Crear tabla si no existe
      await db.execute('''
        CREATE TABLE IF NOT EXISTS reference_dataset (
          id TEXT PRIMARY KEY,
          denomination TEXT NOT NULL,
          type TEXT NOT NULL,
          assetPath TEXT NOT NULL,
          filename TEXT NOT NULL,
          indexed_at TEXT NOT NULL
        )
      ''');

      // Indexar por denominación
      final denominations = {
        '1': 'assets/datasets/billetes/usa_currency/1_dollar',
        '2': 'assets/datasets/billetes/usa_currency/2 Dollar',
        '5': 'assets/datasets/billetes/usa_currency/5_dollar',
        '10': 'assets/datasets/billetes/usa_currency/10_dollar',
        '50': 'assets/datasets/billetes/usa_currency/50 Dollar',
        '100': 'assets/datasets/billetes/usa_currency/100 Dollar',
      };

      int indexed = 0;

      for (var entry in denominations.entries) {
        final denom = entry.key;
        final basePath = entry.value;

        print('📍 Indexando \$$denom...');

        // Agregar registros de indexación
        const types = ['authentic', 'fake'];

        for (var type in types) {
          // Crear 10-20 referencias por tipo
          for (int i = 1; i <= 15; i++) {
            final filename = '${i.toString().padLeft(3, '0')}.jpg';

            try {
              await db.insert(
                'reference_dataset',
                {
                  'id': const Uuid().v4(),
                  'denomination': '\$$denom',
                  'type': type,
                  'assetPath': basePath,
                  'filename': filename,
                  'indexed_at': DateTime.now().toIso8601String(),
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
              indexed++;
            } catch (e) {
              // Ignorar duplicados
            }
          }
        }
      }

      print('✅ Dataset indexado: $indexed registros');
    } catch (e) {
      print('❌ Error indexando: $e');
    }
  }

  /// Obtener imágenes de referencia por denominación
  Future<List<Map<String, dynamic>>> getReferenceByDenomination(
      String denomination,
      ) async {
    try {
      final db = await _databaseService.database;

      return await db.query(
        'reference_dataset',
        where: 'denomination = ?',
        whereArgs: [denomination],
      );
    } catch (e) {
      print('❌ Error: $e');
      return [];
    }
  }

  /// Obtener todas las imágenes de referencia
  Future<List<Map<String, dynamic>>> getAllReferences() async {
    try {
      final db = await _databaseService.database;
      return await db.query('reference_dataset');
    } catch (e) {
      print('❌ Error: $e');
      return [];
    }
  }

  /// Contar referencias por denominación
  Future<Map<String, int>> countByDenomination() async {
    try {
      final db = await _databaseService.database;

      final result = await db.rawQuery('''
        SELECT denomination, COUNT(*) as count
        FROM reference_dataset
        GROUP BY denomination
      ''');

      final counts = <String, int>{};
      for (var row in result) {
        counts[row['denomination'] as String] = row['count'] as int;
      }

      return counts;
    } catch (e) {
      print('❌ Error: $e');
      return {};
    }
  }

  /// Contar referencias por tipo
  Future<Map<String, int>> countByType() async {
    try {
      final db = await _databaseService.database;

      final result = await db.rawQuery('''
        SELECT type, COUNT(*) as count
        FROM reference_dataset
        GROUP BY type
      ''');

      final counts = <String, int>{};
      for (var row in result) {
        counts[row['type'] as String] = row['count'] as int;
      }

      return counts;
    } catch (e) {
      print('❌ Error: $e');
      return {};
    }
  }

  /// Obtener estadísticas generales
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final byDenom = await countByDenomination();
      final byType = await countByType();

      final total = byDenom.values.fold(0, (sum, val) => sum + val);

      return {
        'total': total,
        'by_denomination': byDenom,
        'by_type': byType,
      };
    } catch (e) {
      print('❌ Error: $e');
      return {};
    }
  }
}