import 'package:image/image.dart' as img;
import 'dart:math';

class AuthenticityDetectorV2 {
  static Future<AuthenticityScore> detectPhotocopy(img.Image image) async {
    final indicators = <String>[];
    double score = 0.0;

    // 1. Ruido
    final (noiseLevel, _) = _analyzeNoise(image);
    if (noiseLevel > 0.6) {
      indicators.add('⚠️ Ruido de fotocopia detectado');
      score -= 0.25;
    } else {
      indicators.add('✓ Ruido natural (auténtico)');
      score += 0.25;
    }

    // 2. Patrones periódicos
    final hasPattern = _detectPeriodicPatterns(image);
    if (hasPattern) {
      indicators.add('⚠️ Patrón periódico (fotocopia)');
      score -= 0.2;
    } else {
      indicators.add('✓ Sin patrones repetitivos');
      score += 0.2;
    }

    // 3. Bordes
    final (sharpness, _) = _analyzeEdges(image);
    if (sharpness > 0.75) {
      indicators.add('⚠️ Bordes demasiado nítidos');
      score -= 0.15;
    } else {
      indicators.add('✓ Bordes naturales');
      score += 0.15;
    }

    // 4. Tinta
    final inkScore = _analyzeInkProperties(image);
    if (inkScore > 0.6) {
      indicators.add('✓ Propiedades de tinta auténtica');
      score += 0.2;
    } else {
      indicators.add('⚠️ Tinta sospechosa');
      score -= 0.2;
    }

    // 5. Microtextura
    final microScore = _analyzeMicrotexture(image);
    if (microScore > 0.5) {
      indicators.add('✓ Microtextura característica');
      score += 0.2;
    }

    return AuthenticityScore(
      isLikelyPhotocopy: score < 0.0,
      score: score.clamp(-1.0, 1.0),
      indicators: indicators,
      noiseLevel: noiseLevel,
      edgeSharpness: sharpness,
      inkScore: inkScore,
      microtextureScore: microScore,
    );
  }

  static (double, String) _analyzeNoise(img.Image image) {
    final gray = _toGrayscale(image);

    final mean = gray.reduce((a, b) => a + b) ~/ gray.length;
    final variance = gray
        .map((p) => (p - mean) * (p - mean))
        .reduce((a, b) => a + b) /
        gray.length;
    final stdDev = sqrt(variance.toDouble());

    // NUEVO: Thresholds más realistas
    // Billetes USD auténticos: 12-28 (incluyendo usados)
    // Billetes nuevos: 10-20
    // Fotocopias digitales: 35+

    if (stdDev > 45) {
      // Fotocopia clara
      return (1.0, 'Fotocopia');
    } else if (stdDev > 35) {
      // Posible fotocopia
      return (0.7, 'Posible fotocopia');
    } else if (stdDev > 28) {
      // Billete auténtico usado (normal)
      return (0.0, 'Auténtico');
    } else {
      // Billete auténtico (nuevo o bien mantenido)
      return (0.0, 'Auténtico');
    }
  }

  static bool _detectPeriodicPatterns(img.Image image) {
    final gray = _toGrayscale(image);

    int matchCount = 0;
    for (int period = 40; period < 200; period += 20) {
      int matches = 0;
      for (int i = 0; i < gray.length - period; i += period) {
        if ((gray[i] - gray[i + period]).abs() < 8) {
          matches++;
        }
      }
      if (matches > (gray.length ~/ period) * 0.6) {
        matchCount++;
      }
    }

    return matchCount > 2;
  }

  static (double, String) _analyzeEdges(img.Image image) {
    final gray = _toGrayscale(image);
    final width = image.width;

    int sharpEdges = 0;
    int totalEdges = 0;

    for (int i = 1; i < gray.length - 1; i++) {
      final diff = (gray[i] - gray[i - 1]).abs();
      if (diff > 25) {
        totalEdges++;
        if (diff > 80) sharpEdges++; // Muy nítido
      }
    }

    final sharpness =
    totalEdges > 0 ? sharpEdges / totalEdges : 0.0;
    return (sharpness.clamp(0.0, 1.0), 'analysis');
  }

  static double _analyzeInkProperties(img.Image image) {
    // Validar que colores no sean primarios puros (típico de escáneres)
    int nonPureColors = 0;
    int total = 0;

    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final px = image.getPixel(x, y);
        final r = px.r.toInt();
        final g = px.g.toInt();
        final b = px.b.toInt();

        total++;

        // Colores puros: R=255 G=0 B=0 (típico de fotocopias)
        if (!((r > 200 && g < 50 && b < 50) ||
            (r < 50 && g > 200 && b < 50) ||
            (r < 50 && g < 50 && b > 200))) {
          nonPureColors++;
        }
      }
    }

    return total > 0 ? nonPureColors / total : 0.5;
  }

  static double _analyzeMicrotexture(img.Image image) {
    // Detectar variaciones micro a nivel de píxel
    final gray = _toGrayscale(image);
    final width = image.width;

    int microVariations = 0;
    for (int i = 1; i < gray.length - 1; i++) {
      final diff = (gray[i] - gray[i - 1]).abs();
      if (5 <= diff && diff <= 40) {
        microVariations++;
      }
    }

    return min((microVariations / gray.length) * 2, 1.0);
  }

  static List<int> _toGrayscale(img.Image image) {
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
}

class AuthenticityScore {
  final bool isLikelyPhotocopy;
  final double score;
  final List<String> indicators;
  final double noiseLevel;
  final double edgeSharpness;
  final double inkScore;
  final double microtextureScore;

  AuthenticityScore({
    required this.isLikelyPhotocopy,
    required this.score,
    required this.indicators,
    required this.noiseLevel,
    required this.edgeSharpness,
    required this.inkScore,
    required this.microtextureScore,
  });
}