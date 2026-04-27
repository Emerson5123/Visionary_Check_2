import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'enhanced_denomination_detector.dart';
import 'authenticity_detector_v2.dart';
import 'edge_detection_service.dart';

// Top-level function requerida por compute() — no puede ser método de instancia.
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

  BillAnalysis({
    required this.hasBilletFeatures,
    required this.isAuthentic,
    required this.confidence,
    required this.denomination,
    required this.currency,
    required this.details,
    this.detectedFeatures    = const [],
    this.suspiciousIndicators = const [],
    this.edgeResult,
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
//  Usa SOLO tres servicios:
//    • EdgeDetectionService          → realzar bordes antes del análisis
//    • EnhancedDenominationDetector  → detectar denominación
//    • AuthenticityDetectorV2        → detectar fotocopia / autenticidad
// ══════════════════════════════════════════════════════════════════

class BillDetectionService {
  // ── Singleton ────────────────────────────────────────────────────
  static final BillDetectionService _instance =
  BillDetectionService._internal();
  factory BillDetectionService() => _instance;
  BillDetectionService._internal();

  final EnhancedDenominationDetector _denomDetector =
  EnhancedDenominationDetector();
  final EdgeDetectionService _edgeService = EdgeDetectionService();

  // ══════════════════════════════════════════════════════════════════
  //  MÉTODO PRINCIPAL
  // ══════════════════════════════════════════════════════════════════

  /// Pipeline completo:
  ///   1. Detección de bordes (Sobel) → imagen realzada
  ///   2. Detectar moneda por color
  ///   3. Denominación  [EnhancedDenominationDetector]
  ///   4. Autenticidad  [AuthenticityDetectorV2]
  Future<BillAnalysis> analyzeBill(String imagePath) async {
    try {
      print('\n🏦 ═══════════════════════════════════════');
      print('🏦  ANÁLISIS DE BILLETE');
      print('🏦 ═══════════════════════════════════════\n');

      // ── PASO 1: Detección de bordes ───────────────────────────
      print('🔲 PASO 1/3 — Aplicando filtro de bordes...');
      // compute() corre _runEdgeDetection en un Isolate separado,
      // liberando el hilo de UI durante los ~1800ms del pipeline de bordes.
      final edgeResult = await compute(_runEdgeDetection, imagePath);

      // Si hay imagen procesada la usamos; si el servicio falló,
      // continuamos con la original para no bloquear el flujo.
      final analysisPath = edgeResult.success
          ? edgeResult.enhancedPath
          : imagePath;

      if (edgeResult.success) {
        print('   ${edgeResult.imageQuality}  '
            '(fuerza=${(edgeResult.edgeStrength * 100).toStringAsFixed(1)}%)');
      } else {
        print('   ⚠️ Edge detection falló, usando imagen original');
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
      print('🔢 PASO 2/3 — Detectando denominación...');
      final denomResult = await _denomDetector.detectDenomination(
        analysisPath,
        currency,
      );

      // ── PASO 4: Autenticidad ──────────────────────────────────
      print('🔐 PASO 3/3 — Verificando autenticidad...');
      final authResult = await AuthenticityDetectorV2.detectPhotocopy(image);

      return _buildResult(
        currency:    currency,
        denomResult: denomResult,
        authResult:  authResult,
        edgeResult:  edgeResult,
      );
    } catch (e) {
      print('❌ Error en analyzeBill: $e');
      return _errorResult('Error al procesar la imagen: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  DETECCIÓN DE MONEDA POR COLOR
  // ══════════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════
  //  DETECCIÓN DE MONEDA POR COLOR
  //
  //  Problema anterior: muestreaba 5 puntos fijos que podían caer
  //  en la mano o el fondo (RGB 152,103,98 → color piel/madera).
  //
  //  Solución: muestrear una cuadrícula 5×5 en el 60% central
  //  de la imagen (recorta 20% en cada borde).
  //  Filtrar pixels demasiado oscuros (<30) o saturados (>240)
  //  que probablemente son fondo, no billete.
  // ══════════════════════════════════════════════════════════════════

  String _detectCurrency(img.Image image) {
    try {
      final w = image.width;
      final h = image.height;

      // Zona central: 20%–80% en cada eje
      final x0 = (w * 0.20).round();
      final x1 = (w * 0.80).round();
      final y0 = (h * 0.20).round();
      final y1 = (h * 0.80).round();

      final xStep = (x1 - x0) ~/ 4; // 5 puntos
      final yStep = (y1 - y0) ~/ 4;

      int tR = 0, tG = 0, tB = 0, n = 0;

      for (int yi = 0; yi <= 4; yi++) {
        for (int xi = 0; xi <= 4; xi++) {
          final x = x0 + xi * xStep;
          final y = y0 + yi * yStep;
          if (x >= w || y >= h) continue;
          final px = image.getPixel(x, y);
          final r = px.r.toInt();
          final g = px.g.toInt();
          final b = px.b.toInt();
          // Ignorar pixels muy oscuros o sobreexpuestos (fondo/reflejos)
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

      // ECU: dominancia roja fuerte (billetes naranja/rojo)
      if (aR > 160 && aR > aG + 40 && aR > aB + 40) return 'ECU';
      // USD: verde o verde-azulado
      if (aG > aR + 10 || aB > aR + 10) return 'USD';
      // Billete grisáceo/neutro (nuevos USD de alta seguridad) → USD
      return 'USD';
    } catch (_) {
      return 'USD';
    }
  }
  // ══════════════════════════════════════════════════════════════════
  //  CONSTRUCCIÓN DEL RESULTADO
  // ══════════════════════════════════════════════════════════════════

  BillAnalysis _buildResult({
    required String                      currency,
    required DenominationDetectionResult denomResult,
    required AuthenticityScore           authResult,
    required EdgeDetectionResult         edgeResult,
  }) {
    double finalConfidence = denomResult.confidence;

    if (authResult.isLikelyPhotocopy) {
      finalConfidence *= 0.50;
      print('\n⚠️  Fotocopia detectada — confianza reducida al 50%');
    }

    // Penalización adicional si la imagen tenía bordes muy débiles
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
      denomination:  denomResult.denomination,
      confidence:    finalConfidence,
      authResult:    authResult,
      isAuthentic:   isAuthentic,
      allCandidates: denomResult.allCandidates,
      edgeResult:    edgeResult,
    );

    print('\n════════════════════════════════════════════');
    print('✅ Denominación : \$${denomResult.denomination}');
    print('🔐 Autenticidad : ${isAuthentic ? "AUTÉNTICO ✅" : "SOSPECHOSO ⚠️"}');
    print('📊 Confianza    : ${(finalConfidence * 100).toStringAsFixed(1)}%');
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
    );
  }

  String _buildDetails({
    required String denomination,
    required double confidence,
    required AuthenticityScore authResult,
    required bool isAuthentic,
    required Map<String, double> allCandidates,
    required EdgeDetectionResult edgeResult,
  }) {
    final buf = StringBuffer();
    buf.writeln('RESULTADO DEL ANÁLISIS');
    buf.writeln('═' * 40);

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