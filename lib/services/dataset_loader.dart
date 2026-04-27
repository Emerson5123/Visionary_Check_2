import 'package:flutter/services.dart';

class DatasetLoader {
  static final DatasetLoader _instance = DatasetLoader._internal();

  factory DatasetLoader() => _instance;
  DatasetLoader._internal();

  /// Estructura de tus carpetas en assets
  static const Map<String, String> ASSET_PATHS = {
    '1': 'assets/datasets/billetes/usa_currency/1_dollar',
    '2': 'assets/datasets/billetes/usa_currency/2_dollar',
    '5': 'assets/datasets/billetes/usa_currency/5_dollar',
    '10': 'assets/datasets/billetes/usa_currency/10_dollar',
    '50': 'assets/datasets/billetes/usa_currency/50 Dollar',
    '100': 'assets/datasets/billetes/usa_currency/100 Dollar',
    'test': 'assets/datasets/billetes/usa_currency/test_set',
  };

  /// Obtener ruta de imagen de asset
  static String getAssetPath(String denomination) {
    return ASSET_PATHS[denomination] ?? '';
  }

  /// Obtener todas las rutas de imágenes disponibles
  static List<String> getAllAssetPaths() {
    return ASSET_PATHS.values.toList();
  }

  /// Verificar si existe un asset
  static Future<bool> assetExists(String assetPath) async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } catch (e) {
      return false;
    }
  }
}