import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'image_enhancer_service.dart';
import 'enhanced_denomination_detector.dart';
import 'authenticity_detector_v2.dart';
import 'edge_detection_service.dart';

// Top-level functions requeridas por compute() — no pueden ser métodos de instancia.
Future<ImageEnhancementResult> _runImageEnhancement(String imagePath) =>
    ImageEnhancerService().enhance(imagePath);

Future<EdgeDetectionResult> _runEdgeDetection(String imagePath) =>
    EdgeDetectionService().processImage(imagePath);

// ══════════════════════════════════════════════════════════════════
//  MODELO DE RESULTADO
// ══════════════════════════════════════════════════════════════════

class BillAnalysis {
  final bool hasBilletFeatures;
  final bool isAuthentic;
  final double confidence;
  final String denomination;
  final String currency;
  final String details;
  final List<String> detectedFeatures;
  final List<String> suspiciousIndicators;
  final EdgeDetectionResult? edgeResult;
  final ImageEnhancementResult? enhancementResult;

  BillAnalysis({
    required this.hasBilletFeatures,
    required this.isAuthentic,
    required this.confidence,
    required this.denomination,
    required this.currency,
    required this.details,
    this.detectedFeatures     = const [],
    this.suspiciousIndicators = const [],
    this.edgeResult,
    this.enhancementResult,
  });

  String get confidencePercentage =>
      '${(confidence * 100).toStringAsFixed(0)}%';

  String get currencyLabel {
    switch (currency) {
      case 'USD': return 'USD 🇺🇸';
      case 'ECU': return 'Ecuador 🇪🇨';
      default:    return 'Desconocida';
    }
  }

  bool get isUnknown =>
      denomination == 'Unknown' || denomination == 'No detectada';
}

// ══════════════════════════════════════════════════════════════════
//  SERVICIO PRINCIPAL  (Singleton)
//
//  Pipeline completo:
//    PASO 0 — ImageEnhancerService   → mejorar imagen original
//                                      (recorte, deskew, denoise,
//                                       brillo/contraste)
//    PASO 1 — EdgeDetectionService   → realzar bordes (Sobel v3)
//    PASO 2 — detectar moneda por color
//    PASO 3 — EnhancedDenominationDetector → denominación
//    PASO 4 — AuthenticityDetectorV2       → autenticidad
// ══════════════════════════════════════════════════════════════════

class BillDetectionService {
  // ── Singleton ────────────────────────────────────────────────────
  static final BillDetectionService _instance =
  BillDetectionService._internal();
  factory BillDetectionService() => _instance;
  BillDetectionService._internal();

  final ImageEnhancerService        _enhancer     = ImageEnhancerService();
  final EnhancedDenominationDetector _denomDetector =
  EnhancedDenominationDetector();
  final EdgeDetectionService        _edgeService  = EdgeDetectionService();

  // ══════════════════════════════════════════════════════════════════
  //  MÉTODO PRINCIPAL
  // ══════════════════════════════════════════════════════════════════

  Future<BillAnalysis> analyzeBill(String imagePath) async {
    try {
      print('\n🏦 ═══════════════════════════════════════');
      print('🏦  ANÁLISIS DE BILLETE');
      print('🏦 ═══════════════════════════════════════\n');

      // ── PASO 0: Mejora de imagen original ────────────────────
      // Se corre en un Isolate para no bloquear el hilo de UI.
      // Incluye: recorte automático, corrección de perspectiva,
      // reducción de ruido bilateral y corrección de brillo/contraste.
      print('🖼️  PASO 0/4 — Mejorando imagen original...');
      final enhancementResult =
      await compute(_runImageEnhancement, imagePath);

      // Si el enhancer falló, continuamos con la imagen original
      final pathAfterEnhancement = enhancementResult.pathForNextStep;
      if (enhancementResult.success) {
        print('   ✓ Pasos: ${enhancementResult.stepsApplied.join(" → ")}');
      } else {
        print('   ⚠️ Enhancer falló (${enhancementResult.skipReason})'
            ' — usando imagen original');
      }

      // ── PASO 1: Detección de bordes (Sobel v3) ───────────────
      // Se corre en un Isolate separado para no bloquear la UI.
      print('\n🔲 PASO 1/4 — Aplicando filtro de bordes...');
      final edgeResult =
      await compute(_runEdgeDetection, pathAfterEnhancement);

      final analysisPath = edgeResult.success
          ? edgeResult.enhancedPath
          : pathAfterEnhancement;

      if (edgeResult.success) {
        print('   ${edgeResult.imageQuality}'
            '  (fuerza=${(edgeResult.edgeStrength * 100).toStringAsFixed(1)}%)');
      } else {
        print('   ⚠️ Edge detection falló, usando imagen del paso anterior');
      }

      // ── PASO 2: Leer imagen procesada + detectar moneda ──────
      final imageBytes = await File(analysisPath).readAsBytes();
      final image      = img.decodeImage(imageBytes);

      if (image == null) {
        return _errorResult('No se pudo decodificar la imagen');
      }

      final currency = _detectCurrency(image);
      print('💱 Moneda: $currency\n');

      // ── PASO 3: Denominación ──────────────────────────────────
      print('🔢 PASO 2/4 — Detectando denominación...');
      final denomResult = await _denomDetector.detectDenomination(
        analysisPath,
        currency,
      );

      // ── PASO 4: Autenticidad ──────────────────────────────────
      print('🔐 PASO 3/4 — Verificando autenticidad...');
      final authResult = await AuthenticityDetectorV2.detectPhotocopy(image);

      return _buildResult(
        currency:          currency,
        denomResult:       denomResult,
        authResult:        authResult,
        edgeResult:        edgeResult,
        enhancementResult: enhancementResult,
      );
    } catch (e) {
      print('❌ Error en analyzeBill: $e');
      return _errorResult('Error al procesar la imagen: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  DETECCIÓN DE MONEDA POR COLOR
  //
  //  Muestreo en cuadrícula 5×5 sobre el 60% central de la imagen.
  //  Filtra pixels demasiado oscuros (<30) o saturados (>240).
  // ══════════════════════════════════════════════════════════════════

  String _detectCurrency(img.Image image) {
    try {
      final w = image.width;
      final h = image.height;

      final x0 = (w * 0.20).round();
      final x1 = (w * 0.80).round();
      final y0 = (h * 0.20).round();
      final y1 = (h * 0.80).round();

      final xStep = (x1 - x0) ~/ 4;
      final yStep = (y1 - y0) ~/ 4;

      int tR = 0, tG = 0, tB = 0, n = 0;

      for (int yi = 0; yi <= 4; yi++) {
        for (int xi = 0; xi <= 4; xi++) {
          final x = x0 + xi * xStep;
          final y = y0 + yi * yStep;
          if (x >= w || y >= h) continue;
          final px = image.getPixel(x, y);
          final r  = px.r.toInt();
          final g  = px.g.toInt();
          final b  = px.b.toInt();
          final lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
          if (lum < 30 || lum > 240) continue;
          tR += r; tG += g; tB += b; n++;
        }
      }

      if (n == 0) return 'USD';
      final aR = tR ~/ n;
      final aG = tG ~/ n;
      final aB = tB ~/ n;
      print('🎨 Color promedio (zona central, n=$n): RGB($aR, $aG, $aB)');

      if (aR > 160 && aR > aG + 40 && aR > aB + 40) return 'ECU';
      if (aG > aR + 10 || aB > aR + 10) return 'USD';
      return 'USD';
    } catch (_) {
      return 'USD';
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  CONSTRUCCIÓN DEL RESULTADO
  // ══════════════════════════════════════════════════════════════════

  BillAnalysis _buildResult({
    required String                   currency,
    required DenominationDetectionResult denomResult,
    required AuthenticityScore        authResult,
    required EdgeDetectionResult      edgeResult,
    required ImageEnhancementResult   enhancementResult,
  }) {
    double finalConfidence = denomResult.confidence;

    if (authResult.isLikelyPhotocopy) {
      finalConfidence *= 0.50;
      print('\n⚠️  Fotocopia detectada — confianza reducida al 50%');
    }

    if (edgeResult.success && edgeResult.edgeStrength < 0.05) {
      finalConfidence *= 0.80;
      print('⚠️  Imagen borrosa — confianza reducida al 80%');
    }

    finalConfidence = finalConfidence.clamp(0.0, 1.0);
    final isAuthentic =
        !authResult.isLikelyPhotocopy && finalConfidence >= 0.45;

    final features   = <String>[];
    final suspicious = <String>[];
    for (final ind in authResult.indicators) {
      (ind.startsWith('✓') ? features : suspicious).add(ind);
    }

    final details = _buildDetails(
      denomination:      denomResult.denomination,
      confidence:        finalConfidence,
      authResult:        authResult,
      isAuthentic:       isAuthentic,
      allCandidates:     denomResult.allCandidates,
      edgeResult:        edgeResult,
      enhancementResult: enhancementResult,
    );

    print('\n════════════════════════════════════════════');
    print('✅ Denominación : \$${denomResult.denomination}');
    print('🔐 Autenticidad : ${isAuthentic ? "AUTÉNTICO ✅" : "SOSPECHOSO ⚠️"}');
    print('📊 Confianza    : ${(finalConfidence * 100).toStringAsFixed(1)}%');
    print('🖼️  Mejora img  : ${enhancementResult.stepsApplied.join(" → ")}');
    print('🔲 Bordes       : ${edgeResult.imageQuality}');
    print('════════════════════════════════════════════\n');

    return BillAnalysis(
      hasBilletFeatures:    true,
      isAuthentic:          isAuthentic,
      confidence:           finalConfidence,
      denomination:         denomResult.denomination,
      currency:             currency,
      details:              details,
      detectedFeatures:     features,
      suspiciousIndicators: suspicious,
      edgeResult:           edgeResult,
      enhancementResult:    enhancementResult,
    );
  }

  String _buildDetails({
    required String                   denomination,
    required double                   confidence,
    required AuthenticityScore        authResult,
    required bool                     isAuthentic,
    required Map<String, double>      allCandidates,
    required EdgeDetectionResult      edgeResult,
    required ImageEnhancementResult   enhancementResult,
  }) {
    final buf = StringBuffer();
    buf.writeln('RESULTADO DEL ANÁLISIS');
    buf.writeln('═' * 40);

    buf.writeln('\n🖼️  MEJORA DE IMAGEN:');
    if (enhancementResult.success) {
      for (final s in enhancementResult.stepsApplied) {
        buf.writeln('   • $s');
      }
    } else {
      buf.writeln('   Omitida (${enhancementResult.skipReason})');
    }

    buf.writeln('\n🔲 CALIDAD DE IMAGEN:');
    buf.writeln('   ${edgeResult.imageQuality}');

    buf.writeln('\n💵 DENOMINACIÓN: \$$denomination');
    buf.writeln('   Confianza: ${(confidence * 100).toStringAsFixed(1)}%');

    if (allCandidates.isNotEmpty) {
      buf.writeln('\n   Otros candidatos:');
      final sorted = allCandidates.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted.take(3)) {
        if (e.key != denomination) {
          buf.writeln(
              '   • \$${e.key}: ${(e.value * 100).toStringAsFixed(1)}%');
        }
      }
    }

    buf.writeln('\n🔐 AUTENTICIDAD:');
    for (final ind in authResult.indicators) {
      buf.writeln('   $ind');
    }

    buf.writeln('\n📋 CONCLUSIÓN:');
    if (isAuthentic) {
      buf.writeln('   ✅ Billete con características auténticas.');
      buf.writeln('   Recomendación: ACEPTAR');
    } else if (authResult.isLikelyPhotocopy) {
      buf.writeln('   ⚠️ Se detectaron patrones de fotocopia/falsificación.');
      buf.writeln('   Recomendación: RECHAZAR');
    } else {
      buf.writeln('   ⚠️ Confianza insuficiente.');
      buf.writeln('   Recomendación: VERIFICAR MANUALMENTE');
    }

    return buf.toString();
  }

  BillAnalysis _errorResult(String message) => BillAnalysis(
    hasBilletFeatures: false,
    isAuthentic:       false,
    confidence:        0.0,
    denomination:      'Error',
    currency:          'UNKNOWN',
    details:           message,
  );

  void dispose() => _denomDetector.dispose();
}