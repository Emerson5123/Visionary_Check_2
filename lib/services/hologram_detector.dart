import 'package:image/image.dart' as img;
import 'dart:math';

class HologramDetector {
  /// Detecta bandas de hologramas y características 3D
  Future<HologramDetectionResult> detectHologramFeatures(
      img.Image image,
      ) async {
    try {
      print('🔍 Analizando características holográficas...');

      // 1. Detectar bandas brillantes
      final (hasBands, bandScore) = _detectHolographicBands(image);

      // 2. Detectar iridiscencia (cambio de color con ángulo)
      final (hasIridescence, iridScore) = _detectIridescence(image);

      // 3. Detectar efecto óptico de seguridad
      final (hasOpticalEffect, opticalScore) = _detectOpticalSecurityFeatures(image);

      // 4. Validar reflectividad
      final (isReflective, reflectScore) = _validateReflectivity(image);

      // Scoring combinado
      double totalScore = (
          (bandScore * 0.35) +
              (iridScore * 0.25) +
              (opticalScore * 0.25) +
              (reflectScore * 0.15)
      ).clamp(0.0, 1.0);

      final indicators = <String>[];
      if (hasBands) indicators.add('Bandas holográficas detectadas');
      if (hasIridescence) indicators.add('Efecto iridiscente detectado');
      if (hasOpticalEffect) indicators.add('Característica óptica de seguridad');
      if (isReflective) indicators.add('Reflectividad característica');

      final suspicions = <String>[];
      if (!hasBands) suspicions.add('Sin bandas holográficas detectadas');
      if (!hasIridescence) suspicions.add('Sin efecto iridiscente');
      if (!isReflective) suspicions.add('Reflectividad anómala');

      return HologramDetectionResult(
        score: totalScore,
        hasHologram: totalScore > 0.65,
        indicators: indicators,
        suspicions: suspicions,
        details: _generateHologramDetails(
          totalScore,
          bandScore,
          iridScore,
          opticalScore,
          reflectScore,
        ),
      );
    } catch (e) {
      print('❌ Error en detección de hologramas: $e');
      return HologramDetectionResult(
        score: 0.0,
        hasHologram: false,
        indicators: [],
        suspicions: ['Error en análisis holográfico'],
        details: 'Error: $e',
      );
    }
  }

  /// Detecta bandas de hologramas (strip vertical/horizontal brillante)
  (bool, double) _detectHolographicBands(img.Image image) {
    final width = image.width;
    final height = image.height;

    // Buscar área vertical brillante (típicamente en centro-derecha)
    int brightPixels = 0;
    int totalPixels = 0;

    // Muestrear zona de 25% ancho x 100% alto (típica ubicación)
    final startX = (width * 0.65).toInt();
    final endX = (width * 0.90).toInt();

    for (int y = 0; y < height; y++) {
      for (int x = startX; x < endX; x++) {
        final px = image.getPixel(x, y);
        final brightness = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b).toInt();

        totalPixels++;
        if (brightness > 200) brightPixels++;
      }
    }

    final bandDensity = brightPixels / (totalPixels + 1);
    final hasBands = bandDensity > 0.15; // >15% píxeles brillantes

    return (hasBands, min(bandDensity * 2, 1.0));
  }

  /// Detecta iridiscencia (cambio de color)
  (bool, double) _detectIridescence(img.Image image) {
    // La iridiscencia crea variación de color similar en áreas similares
    final width = image.width;
    final height = image.height;

    // Muestrear diferentes zonas
    final samples = <(int, int, int)>[];

    for (int y = height ~/ 4; y < height * 3 ~/ 4; y += height ~/ 8) {
      for (int x = width ~/ 4; x < width * 3 ~/ 4; x += width ~/ 8) {
        final px = image.getPixel(x, y);
        samples.add((px.r.toInt(), px.g.toInt(), px.b.toInt()));
      }
    }

    // Calcular varianza de color
    double avgR = 0, avgG = 0, avgB = 0;
    for (final (r, g, b) in samples) {
      avgR += r;
      avgG += g;
      avgB += b;
    }
    avgR /= samples.length;
    avgG /= samples.length;
    avgB /= samples.length;

    double varR = 0, varG = 0, varB = 0;
    for (final (r, g, b) in samples) {
      varR += (r - avgR).abs();
      varG += (g - avgG).abs();
      varB += (b - avgB).abs();
    }

    final colorVariation = (varR + varG + varB) / (samples.length * 3);
    final hasIridescence = colorVariation > 20 && colorVariation < 100;

    return (hasIridescence, colorVariation / 100);
  }

  /// Detecta características ópticas de seguridad (guilloché, etc.)
  (bool, double) _detectOpticalSecurityFeatures(img.Image image) {
    // Buscar patrones de guilloché (líneas entrelazadas)
    final edges = _detectEdgePatterns(image);
    final hasPattern = edges > 100;

    return (hasPattern, min(edges / 1000, 1.0));
  }

  int _detectEdgePatterns(img.Image image) {
    final gray = _toGrayscale(image);
    int edgeCount = 0;

    for (int i = 1; i < gray.length - 1; i++) {
      final diff = (gray[i] - gray[i - 1]).abs();
      if (diff > 30 && diff < 150) edgeCount++;
    }

    return edgeCount;
  }

  /// Valida reflectividad característica
  (bool, double) _validateReflectivity(img.Image image) {
    // Analizar distribución de brillo
    final gray = _toGrayscale(image);
    gray.sort();

    final q1 = gray[gray.length ~/ 4];
    final q3 = gray[(gray.length * 3) ~/ 4];
    final iqr = q3 - q1;

    // Billetes auténticos tienen IQR típicamente 40-100
    final isReflective = iqr > 40 && iqr < 120;

    return (isReflective, 1.0 - (iqr - 50).abs() / 100);
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

  String _generateHologramDetails(
      double total,
      double band,
      double irid,
      double optical,
      double reflect,
      ) {
    return '''
🔍 ANÁLISIS HOLOGRÁFICO DETALLADO
═════════════════════════════════════
📊 SCORES:
  Bandas holográficas: ${(band * 100).toStringAsFixed(1)}%
  Iridiscencia: ${(irid * 100).toStringAsFixed(1)}%
  Características ópticas: ${(optical * 100).toStringAsFixed(1)}%
  Reflectividad: ${(reflect * 100).toStringAsFixed(1)}%
  
SCORE TOTAL: ${(total * 100).toStringAsFixed(1)}%
${total > 0.65 ? '✅ Hologramas auténticos detectados' : '⚠️ Hologramas ausentes o deficientes'}
    ''';
  }
}

class HologramDetectionResult {
  final double score;
  final bool hasHologram;
  final List<String> indicators;
  final List<String> suspicions;
  final String details;

  HologramDetectionResult({
    required this.score,
    required this.hasHologram,
    required this.indicators,
    required this.suspicions,
    required this.details,
  });
}