import 'package:image/image.dart' as img;
import 'dart:math';

class WatermarkDetector {
  /// Detecta y valida marcas de agua
  Future<WatermarkDetectionResult> detectWatermarks(
      img.Image image,
      ) async {
    try {
      print('🔍 Analizando marcas de agua...');

      // 1. Detectar marca de agua principal (retrato)
      final (hasPortraitWM, portraitScore) = _detectPortraitWatermark(image);

      // 2. Detectar marca de agua de denominación
      final (hasDenomWM, denomScore) = _detectDenominationWatermark(image);

      // 3. Detectar trama de fondo (background pattern)
      final (hasPattern, patternScore) = _detectBackgroundPattern(image);

      // 4. Validar ubicación típica
      final (correctLocation, locationScore) = _validateWatermarkLocation(image);

      double totalScore = (
          (portraitScore * 0.35) +
              (denomScore * 0.25) +
              (patternScore * 0.25) +
              (locationScore * 0.15)
      ).clamp(0.0, 1.0);

      final indicators = <String>[];
      if (hasPortraitWM) indicators.add('Marca de agua de retrato detectada');
      if (hasDenomWM) indicators.add('Marca de agua de denominación');
      if (hasPattern) indicators.add('Patrón de fondo detectado');
      if (correctLocation) indicators.add('Ubicación correcta de marca de agua');

      final suspicions = <String>[];
      if (!hasPortraitWM) suspicions.add('Marca de agua de retrato ausente');
      if (!hasDenomWM) suspicions.add('Marca de agua de denominación ausente');
      if (!correctLocation) suspicions.add('Marca de agua en ubicación anómala');

      return WatermarkDetectionResult(
        score: totalScore,
        hasWatermark: totalScore > 0.65,
        portraitWatermark: hasPortraitWM,
        denominationWatermark: hasDenomWM,
        indicators: indicators,
        suspicions: suspicions,
        details: _generateWatermarkDetails(
          totalScore,
          portraitScore,
          denomScore,
          patternScore,
        ),
      );
    } catch (e) {
      print('❌ Error detectando marcas de agua: $e');
      return WatermarkDetectionResult(
        score: 0.0,
        hasWatermark: false,
        portraitWatermark: false,
        denominationWatermark: false,
        indicators: [],
        suspicions: ['Error en análisis de marca de agua'],
        details: 'Error: $e',
      );
    }
  }

  /// Detecta marca de agua de retrato (típicamente en left center)
  (bool, double) _detectPortraitWatermark(img.Image image) {
    // La marca de agua es semi-transparente (gris medio)
    // Buscar zona izquierda-centro

    final width = image.width;
    final height = image.height;

    int watermarkPixels = 0;
    int totalPixels = 0;

    // Zona típica: 15-35% horizontal, 25-75% vertical
    final startX = (width * 0.15).toInt();
    final endX = (width * 0.35).toInt();
    final startY = (height * 0.25).toInt();
    final endY = (height * 0.75).toInt();

    for (int y = startY; y < endY; y++) {
      for (int x = startX; x < endX; x++) {
        final px = image.getPixel(x, y);
        final brightness = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b).toInt();

        totalPixels++;
        // Marca de agua típicamente 100-150 (gris medio)
        if (brightness >= 100 && brightness <= 150) {
          watermarkPixels++;
        }
      }
    }

    final watermarkDensity = watermarkPixels / (totalPixels + 1);
    final hasWatermark = watermarkDensity > 0.15;

    return (hasWatermark, min(watermarkDensity, 1.0));
  }

  /// Detecta marca de agua de denominación (esquina superior)
  (bool, double) _detectDenominationWatermark(img.Image image) {
    final width = image.width;
    final height = image.height;

    // Esquina superior derecha típicamente
    final startX = (width * 0.65).toInt();
    final endX = width;
    final startY = 0;
    final endY = (height * 0.25).toInt();

    int wmPixels = 0;
    int total = 0;

    for (int y = startY; y < endY; y++) {
      for (int x = startX; x < endX; x++) {
        final px = image.getPixel(x, y);
        final brightness = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b).toInt();

        total++;
        if (brightness >= 100 && brightness <= 150) {
          wmPixels++;
        }
      }
    }

    final density = wmPixels / (total + 1);
    return (density > 0.10, min(density, 1.0));
  }

  /// Detecta patrón de fondo (guilloché)
  (bool, double) _detectBackgroundPattern(img.Image image) {
    // Los billetes tienen patrones de líneas finas de fondo
    final edges = _computeHighFrequencyContent(image);
    final hasPattern = edges > 5000;

    return (hasPattern, min(edges / 50000, 1.0));
  }

  int _computeHighFrequencyContent(img.Image image) {
    // FFT-like analysis (simplified)
    final gray = _toGrayscale(image);
    int highFreq = 0;

    for (int i = 1; i < gray.length - 1; i++) {
      final diff = (gray[i] - gray[i - 1]).abs();
      if (diff > 15 && diff < 100) {
        highFreq++;
      }
    }

    return highFreq;
  }

  /// Valida que las marcas de agua estén en ubicación correcta
  (bool, double) _validateWatermarkLocation(img.Image image) {
    // Las marcas de agua deben estar en posiciones específicas
    // Si aparecen en lugares anómalos = falsificación

    final width = image.width;
    final height = image.height;

    // Buscar áreas de no-watermark que deberían serlo
    bool correctLocation = true;
    double locationScore = 0.8;

    // Validar que el centro tenga contenido (no sea solo watermark)
    final centerX = width ~/ 2;
    final centerY = height ~/ 2;

    int centerBrightness = 0;
    for (int y = centerY - 10; y < centerY + 10; y++) {
      for (int x = centerX - 10; x < centerX + 10; x++) {
        if (x >= 0 && x < width && y >= 0 && y < height) {
          final px = image.getPixel(x, y);
          centerBrightness +=
              (0.299 * px.r + 0.587 * px.g + 0.114 * px.b).toInt();
        }
      }
    }

    centerBrightness ~/= 400;

    // Centro debe ser más oscuro (contiene información)
    if (centerBrightness < 100) {
      correctLocation = true;
      locationScore = 0.95;
    } else if (centerBrightness < 140) {
      locationScore = 0.7;
    } else {
      correctLocation = false;
      locationScore = 0.3;
    }

    return (correctLocation, locationScore);
  }

  List<int> _toGrayscale(img.Image image) {
    final result = <int>[];
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        final gray = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b).toInt();
        result.add(gray);
      }
    }
    return result;
  }

  String _generateWatermarkDetails(
      double total,
      double portrait,
      double denom,
      double pattern,
      ) {
    return '''
💧 ANÁLISIS DE MARCAS DE AGUA
═════════════════════════════════════
📊 SCORES:
  Retrato: ${(portrait * 100).toStringAsFixed(1)}%
  Denominación: ${(denom * 100).toStringAsFixed(1)}%
  Patrón de fondo: ${(pattern * 100).toStringAsFixed(1)}%
  
SCORE TOTAL: ${(total * 100).toStringAsFixed(1)}%
${total > 0.65 ? '✅ Marcas de agua auténticas' : '⚠️ Marcas de agua ausentes o deficientes'}
    ''';
  }
}

class WatermarkDetectionResult {
  final double score;
  final bool hasWatermark;
  final bool portraitWatermark;
  final bool denominationWatermark;
  final List<String> indicators;
  final List<String> suspicions;
  final String details;

  WatermarkDetectionResult({
    required this.score,
    required this.hasWatermark,
    required this.portraitWatermark,
    required this.denominationWatermark,
    required this.indicators,
    required this.suspicions,
    required this.details,
  });
}