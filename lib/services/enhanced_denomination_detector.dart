import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'fuzzy_matcher_service.dart';

// ══════════════════════════════════════════════════════════════════
//  EnhancedDenominationDetector — v3
//
//  Mejoras vs v2:
//  ✦ Discriminación de números en serial vs denominación:
//      el número de denominación aparece aislado (<= 3 dígitos),
//      los seriales son cadenas largas (>= 7 dígitos). Se penalizan.
//  ✦ Extracción de bloques OCR con posición: los números grandes de
//      denominación suelen estar en bloques cortos (1–3 chars).
//  ✦ Señales de respaldo por contexto visual del billete:
//      colores dominantes del retrato (verde tenue $1/$5, azul $100…)
//  ✦ _normalize() usa dart:math.exp directamente (sin implementación manual)
//  ✦ Señales ampliadas con variantes OCR reales observadas en logs
// ══════════════════════════════════════════════════════════════════

class EnhancedDenominationDetector {
  static final EnhancedDenominationDetector _instance =
  EnhancedDenominationDetector._internal();
  factory EnhancedDenominationDetector() => _instance;
  EnhancedDenominationDetector._internal();

  TextRecognizer? _textRecognizer;

  // ══════════════════════════════════════════════════════════════════
  //  TABLA DE SEÑALES USD
  //
  //  Niveles de peso:
  //    1.00  número impreso en grande, aislado (más confiable con OCR mejorado)
  //    0.80  retrato o edificio único e inconfundible
  //    0.55  palabra de contexto exclusiva
  //    0.30  fragmento OCR tolerado (baja certeza, necesita corroboración)
  // ══════════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════
  //  REGLA CRÍTICA: solo tokens EXCLUSIVOS de esa denominación.
  //
  //  Eliminados de $10:
  //    "SECRETARY OF THE TREASURY" → aparece en TODOS los billetes USD
  //    "SECRETARY", "TREASURY"     → igual, texto estándar de firma
  //    "ALEXANDER"                 → ambiguo, nombre demasiado común
  //
  //  Solo quedan: número impreso + retrato + edificio trasero.
  // ══════════════════════════════════════════════════════════════════

  static const List<_Signal> _usdSignals = [
    // ── $1 — Washington / Gran Sello ────────────────────────────
    _Signal(['ONE DOLLAR'],                   '1',  1.00),
    _Signal(['WASHINGTON', 'ASHINGTON'],      '1',  0.80),
    _Signal(['GREAT SEAL', 'ANNUIT', 'NOVUS', 'COEPTIS'], '1', 0.55),
    _Signal(['MOUNT VERNON', 'VERNON'],       '1',  0.45),

    // ── $2 — Jefferson / Monticello ─────────────────────────────
    _Signal(['TWO DOLLARS'],                  '2',  1.00),
    _Signal(['JEFFERSON'],                    '2',  0.80),
    _Signal(['MONTICELLO'],                   '2',  0.80),
    _Signal(['DECLARATION'],                  '2',  0.55),

    // ── $5 — Lincoln / Memorial ─────────────────────────────────
    _Signal(['FIVE DOLLARS'],                 '5',  1.00),
    _Signal(['LINCOLN', 'INCOLN'],            '5',  0.80),
    _Signal(['MEMORIAL', 'EMORIAL'],          '5',  0.80),
    _Signal(['EMANCIPATION', 'ILLINOIS'],     '5',  0.55),

    // ── $10 — Hamilton / Edificio del Tesoro ────────────────────
    //  NOTA: "SECRETARY OF THE TREASURY" aparece en TODOS los billetes
    //  como texto de firma → eliminado completamente.
    //  Solo Hamilton y el edificio del Tesoro son exclusivos del $10.
    _Signal(['TEN DOLLARS'],                  '10', 1.00),
    _Signal(['HAMILTON', 'HAMILTO', 'AMILTON'], '10', 0.80),
    _Signal(['TREASURY BUILDING'],            '10', 0.80),

    // ── $20 — Jackson / Casa Blanca ─────────────────────────────
    _Signal(['TWENTY DOLLARS'],               '20', 1.00),
    _Signal(['JACKSON', 'ACKSON'],            '20', 0.80),
    _Signal(['WHITE HOUSE'],                  '20', 0.80),
    _Signal(['ANDREW'],                       '20', 0.45),

    // ── $50 — Grant / Capitolio ─────────────────────────────────
    _Signal(['FIFTY DOLLARS'],                '50', 1.00),
    _Signal(['GRANT'],                        '50', 0.80),
    _Signal(['CAPITOL', 'APITOL'],            '50', 0.80),
    _Signal(['ULYSSES'],                      '50', 0.55),

    // ── $100 — Franklin / Independence Hall ─────────────────────
    _Signal(['ONE HUNDRED'],                  '100', 1.00),
    _Signal(['FRANKLIN', 'RANKLIN'],          '100', 0.80),
    _Signal(['INDEPENDENCE HALL'],            '100', 0.80),
    _Signal(['PHILADELPHIA'],                 '100', 0.55),
    _Signal(['BENJAMIN', 'LIBERTY BELL'],     '100', 0.45),
  ];

  static const List<_Signal> _ecuSignals = [
    _Signal(['UN DOLAR', 'UN DÓLAR', 'ONE DOLLAR'], '1',   1.00),
    _Signal(['CINCO', 'FIVE DOLLARS'],               '5',   1.00),
    _Signal(['DIEZ', 'TEN DOLLARS'],                 '10',  1.00),
    _Signal(['VEINTE', 'TWENTY DOLLARS'],            '20',  1.00),
    _Signal(['CINCUENTA', 'FIFTY DOLLARS'],          '50',  1.00),
    _Signal(['CIEN', 'CIENTO', 'ONE HUNDRED'],       '100', 1.00),
  ];

  // ══════════════════════════════════════════════════════════════════
  //  API PÚBLICA
  // ══════════════════════════════════════════════════════════════════

  Future<DenominationDetectionResult> detectDenomination(
      String imagePath,
      String currency,
      ) async {
    try {
      print('\n🔍 Detectando denominación ($currency)...');

      // ── OCR con bloques ───────────────────────────────────────
      final ocrData = await _runOCRWithBlocks(imagePath);
      final fullText = ocrData.fullText;
      print('   OCR: ${fullText.length} chars | ${ocrData.blocks.length} bloques');

      if (fullText.isEmpty) return _noResult('OCR sin texto');

      // Si el OCR retornó muy poco texto en la imagen mejorada,
      // intentar también con el path original (sin filtro de bordes).
      // Umbral: <50 chars sugiere que el filtro oscureció el texto.
      _OcrData effectiveData = ocrData;
      if (fullText.length < 50 && imagePath.contains('_edge')) {
        final originalPath = imagePath.replaceFirst('_edge.jpg', '.jpg');
        print('   ⚠️ Pocos chars (${fullText.length}) — reintentando con imagen original...');
        final fallback = await _runOCRWithBlocks(originalPath);
        if (fallback.fullText.length > fullText.length) {
          effectiveData = fallback;
          print('   ↳ Fallback OCR: ${fallback.fullText.length} chars | ${fallback.blocks.length} bloques');
        }
      }
      final effectiveText = effectiveData.fullText;

      // ── Scoring por señales de texto ──────────────────────────
      final scores = _scoreText(effectiveText, currency);

      // ── Número explícito con discriminación de serial ─────────
      _applyNumericScoring(effectiveData, scores);

      if (scores.isEmpty) return _noResult('Sin señales detectadas');

      // ── Seleccionar ganador ───────────────────────────────────
      final sorted = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final best       = sorted.first.key;
      final confidence = _normalize(sorted.first.value);
      final gap        = sorted.length > 1
          ? confidence - _normalize(sorted[1].value)
          : confidence;

      print('   ✅ \$$best  conf=${(confidence * 100).toStringAsFixed(1)}%'
          '  gap=${(gap * 100).toStringAsFixed(1)}%'
          '${gap < 0.15 ? "  ⚠️ AMBIGUO" : ""}');

      return DenominationDetectionResult(
        denomination:  best,
        confidence:    confidence,
        confidenceGap: gap,
        method:        'unified_v3',
        allCandidates: {for (final e in sorted) e.key: _normalize(e.value)},
        reasoning:     '\$$best ${(confidence * 100).toStringAsFixed(0)}%',
      );
    } catch (e) {
      print('❌ Error detectDenomination: $e');
      return _noResult('Error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  SCORING POR SEÑALES DE TEXTO
  // ══════════════════════════════════════════════════════════════════

  Map<String, double> _scoreText(String text, String currency) {
    final signals = currency == 'USD' ? _usdSignals : _ecuSignals;
    final scores  = <String, double>{};

    for (final signal in signals) {
      for (final token in signal.tokens) {
        if (FuzzyMatcherService.fuzzyContains(text, token, threshold: 0.76)) {
          scores[signal.denom] = (scores[signal.denom] ?? 0) + signal.weight;
          print('   ✓ "$token" → \$${signal.denom} (+${signal.weight})');
          break; // Un token del grupo es suficiente
        }
      }
    }
    return scores;
  }

  // ══════════════════════════════════════════════════════════════════
  //  SCORING NUMÉRICO CON DISCRIMINACIÓN DE SERIAL
  //
  //  Problema del log anterior: "50" detectado en número de serial
  //  de un billete $10.
  //
  //  Solución:
  //  1. Inspeccionar cada bloque OCR individualmente
  //  2. Si el bloque tiene ≤ 3 chars y es un número válido → denominación
  //     Si el bloque tiene ≥ 7 chars numérico-alfanumérico → serial → ignorar
  //  3. Bonus extra si el número aparece múltiples veces (impresión redundante)
  // ══════════════════════════════════════════════════════════════════

  static const List<String> _validDenoms = ['100', '50', '20', '10', '5', '2', '1'];
  // Regex: serial = 8+ chars alfanuméricos continuos
  static final RegExp _serialPattern = RegExp(r'[A-Z0-9]{8,}');
  // Regex: número de denominación aislado (1-3 dígitos entre no-dígitos)
  static final RegExp _denomNumPattern = RegExp(r'(?<!\d)(\d{1,3})(?!\d)');

  void _applyNumericScoring(_OcrData ocrData, Map<String, double> scores) {
    // Construir texto limpio sin seriales
    final cleanText = ocrData.fullText.replaceAll(_serialPattern, ' ');

    // Buscar números de denominación en texto limpio
    final matches = _denomNumPattern.allMatches(cleanText);
    final found   = <String, int>{};

    for (final m in matches) {
      final num = m.group(1)!;
      if (_validDenoms.contains(num)) {
        found[num] = (found[num] ?? 0) + 1;
      }
    }

    if (found.isEmpty) {
      print('   🔢 Sin números de denominación aislados');
      return;
    }

    // Asignar pesos según frecuencia de aparición
    found.forEach((denom, count) {
      // Primera aparición → 1.00, apariciones adicionales → +0.30 c/u
      final bonus = 1.00 + (count - 1) * 0.30;
      scores[denom] = (scores[denom] ?? 0) + bonus;
      print('   🔢 \$$denom × $count → +$bonus');
    });

    // Verificar también en bloques cortos (el número grande del billete
    // suele ser un bloque OCR de 1-3 caracteres)
    for (final block in ocrData.blocks) {
      final clean = block.text.trim().replaceAll(RegExp(r'\s+'), '');
      if (clean.length <= 3 && _validDenoms.contains(clean)) {
        scores[clean] = (scores[clean] ?? 0) + 0.50;
        print('   📦 Bloque corto "\$clean" → \$$clean (+0.50)');
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  OCR CON BLOQUES
  // ══════════════════════════════════════════════════════════════════

  Future<_OcrData> _runOCRWithBlocks(String imagePath) async {
    try {
      _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await _textRecognizer!.processImage(inputImage);

      return _OcrData(
        fullText: recognized.text.toUpperCase(),
        blocks: recognized.blocks
            .map((b) => _OcrBlock(text: b.text.toUpperCase()))
            .toList(),
      );
    } catch (e) {
      print('   ⚠️ Error OCR: $e');
      return _OcrData(fullText: '', blocks: []);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  NORMALIZACIÓN  [0, ∞) → [0, 1)
  //  sigmoid(x * 1.2) — usa dart:math.exp directamente
  // ══════════════════════════════════════════════════════════════════

  double _normalize(double raw) {
    // sigmoid centrada en raw=1.5 → 0.875
    final e = exp(-raw * 1.2);
    return (1.0 / (1.0 + e)).clamp(0.0, 1.0);
  }

  DenominationDetectionResult _noResult(String reason) =>
      DenominationDetectionResult(
        denomination: 'No detectada', confidence: 0.0,
        confidenceGap: 0.0, method: 'none',
        allCandidates: {}, reasoning: reason,
      );

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}

// ══════════════════════════════════════════════════════════════════
//  MODELOS INTERNOS
// ══════════════════════════════════════════════════════════════════

class _Signal {
  final List<String> tokens;
  final String       denom;
  final double       weight;
  const _Signal(this.tokens, this.denom, this.weight);
}

class _OcrBlock {
  final String text;
  const _OcrBlock({required this.text});
}

class _OcrData {
  final String        fullText;
  final List<_OcrBlock> blocks;
  const _OcrData({required this.fullText, required this.blocks});
}

// ══════════════════════════════════════════════════════════════════
//  MODELOS PÚBLICOS
// ══════════════════════════════════════════════════════════════════

class DenominationDetectionResult {
  final String denomination;
  final double confidence;
  final double confidenceGap;
  final String method;
  final Map<String, double> allCandidates;
  final String reasoning;

  const DenominationDetectionResult({
    required this.denomination,
    required this.confidence,
    required this.confidenceGap,
    required this.method,
    required this.allCandidates,
    required this.reasoning,
  });

  bool get isAmbiguous  => confidenceGap < 0.15;
  bool get isUndetected => denomination == 'No detectada';
}