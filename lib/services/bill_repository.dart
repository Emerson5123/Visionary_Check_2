import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import '../models/bill_record.dart';

class BillRepository {
  static final BillRepository _instance = BillRepository._internal();
  final DatabaseService _databaseService = DatabaseService();

  factory BillRepository() {
    return _instance;
  }

  BillRepository._internal();

  // CREATE - Insertar nuevo billete
  Future<bool> insertBill(BillRecord bill) async {
    try {
      final db = await _databaseService.database;
      await db.insert(
        'bill_records',
        bill.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _updateStatistics(bill);
      return true;
    } catch (e) {
      print('❌ Error al insertar billete: $e');
      return false;
    }
  }

  // READ - Obtener todos los billetes
  Future<List<BillRecord>> getAllBills() async {
    try {
      final db = await _databaseService.database;
      final maps = await db.query(
        'bill_records',
        orderBy: 'date DESC',
      );

      return List.generate(maps.length, (i) {
        return BillRecord.fromMap(maps[i]);
      });
    } catch (e) {
      print('❌ Error al obtener billetes: $e');
      return [];
    }
  }

  // READ - Obtener billete por ID
  Future<BillRecord?> getBillById(String id) async {
    try {
      final db = await _databaseService.database;
      final maps = await db.query(
        'bill_records',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (maps.isNotEmpty) {
        return BillRecord.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      print('❌ Error al obtener billete: $e');
      return null;
    }
  }

  // READ - Obtener billetes por denominación
  Future<List<BillRecord>> getBillsByDenomination(String denomination) async {
    try {
      final db = await _databaseService.database;
      final maps = await db.query(
        'bill_records',
        where: 'denomination = ?',
        whereArgs: [denomination],
        orderBy: 'date DESC',
      );

      return List.generate(maps.length, (i) {
        return BillRecord.fromMap(maps[i]);
      });
    } catch (e) {
      print('❌ Error al obtener billetes por denominación: $e');
      return [];
    }
  }

  // READ - Obtener billetes auténticos
  Future<List<BillRecord>> getAuthenticBills() async {
    try {
      final db = await _databaseService.database;
      final maps = await db.query(
        'bill_records',
        where: 'isAuthentic = ?',
        whereArgs: [1],
        orderBy: 'date DESC',
      );

      return List.generate(maps.length, (i) {
        return BillRecord.fromMap(maps[i]);
      });
    } catch (e) {
      print('❌ Error al obtener billetes auténticos: $e');
      return [];
    }
  }

  // READ - Obtener billetes falsos
  Future<List<BillRecord>> getFakeBills() async {
    try {
      final db = await _databaseService.database;
      final maps = await db.query(
        'bill_records',
        where: 'isAuthentic = ?',
        whereArgs: [0],
        orderBy: 'date DESC',
      );

      return List.generate(maps.length, (i) {
        return BillRecord.fromMap(maps[i]);
      });
    } catch (e) {
      print('❌ Error al obtener billetes falsos: $e');
      return [];
    }
  }

  // UPDATE - Actualizar billete
  Future<bool> updateBill(BillRecord bill) async {
    try {
      final db = await _databaseService.database;
      final result = await db.update(
        'bill_records',
        bill.toMap(),
        where: 'id = ?',
        whereArgs: [bill.id],
      );

      return result > 0;
    } catch (e) {
      print('❌ Error al actualizar billete: $e');
      return false;
    }
  }

  // DELETE - Eliminar billete
  Future<bool> deleteBill(String id) async {
    try {
      final db = await _databaseService.database;
      final result = await db.delete(
        'bill_records',
        where: 'id = ?',
        whereArgs: [id],
      );

      return result > 0;
    } catch (e) {
      print('❌ Error al eliminar billete: $e');
      return false;
    }
  }

  // DELETE - Limpiar todo el historial
  Future<bool> clearAllBills() async {
    try {
      final db = await _databaseService.database;
      await db.delete('bill_records');
      await db.delete('statistics');
      return true;
    } catch (e) {
      print('❌ Error al limpiar historial: $e');
      return false;
    }
  }

  // ESTADÍSTICAS
  Future<void> _updateStatistics(BillRecord bill) async {
    try {
      final db = await _databaseService.database;
      final stats = await db.query('statistics');

      final totalVerifications = (await getAllBills()).length;
      final authenticsCount = (await getAuthenticBills()).length;
      final fakesCount = (await getFakeBills()).length;

      if (stats.isEmpty) {
        await db.insert('statistics', {
          'id': 'main',
          'totalVerifications': totalVerifications,
          'authenticsCount': authenticsCount,
          'fakesCount': fakesCount,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      } else {
        await db.update(
          'statistics',
          {
            'totalVerifications': totalVerifications,
            'authenticsCount': authenticsCount,
            'fakesCount': fakesCount,
            'lastUpdated': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: ['main'],
        );
      }
    } catch (e) {
      print('❌ Error al actualizar estadísticas: $e');
    }
  }

  // OBTENER ESTADÍSTICAS
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final db = await _databaseService.database;
      final stats = await db.query('statistics');

      if (stats.isNotEmpty) {
        return {
          'totalVerifications': stats.first['totalVerifications'] ?? 0,
          'authenticsCount': stats.first['authenticsCount'] ?? 0,
          'fakesCount': stats.first['fakesCount'] ?? 0,
          'lastUpdated': stats.first['lastUpdated'],
        };
      }

      return {
        'totalVerifications': 0,
        'authenticsCount': 0,
        'fakesCount': 0,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error al obtener estadísticas: $e');
      return {
        'totalVerifications': 0,
        'authenticsCount': 0,
        'fakesCount': 0,
      };
    }
  }
}