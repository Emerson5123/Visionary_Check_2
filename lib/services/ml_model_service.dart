import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// Resultado completo del análisis de billete
class BillDetectionResult {
  final bool isBill;
  final bool isAuthentic;
  final String confidence;
  final String denomination;
  final String currency;
  final String details;
  final List<String> detectedKeywords;

  BillDetectionResult({
    required this.isBill,
    required this.isAuthentic,
    required this.confidence,
    required this.denomination,
    required this.currency,
    required this.details,
    this.detectedKeywords = const [],
  });
}

typedef ColorHistogram = List<double>;

/// Servicio de detección de 3 capas:
///   1. OCR de palabras clave (denominación + banco)
///   2. OCR de números impresos en el billete (las cifras "20", "100", etc.)
///   3. Comparación de histograma con dataset de referencia
class MLModelService {
  static final MLModelService _instance = MLModelService._internal();
  late TextRecognizer _textRecognizer;
  bool _isInitialized = false;

  final Map<String, List<ColorHistogram>> _referenceHistograms = {};
  bool _datasetLoaded = false;

  factory MLModelService() => _instance;
  MLModelService._internal();

  // ── Dataset paths ────────────────────────────────────────────────────────
  static const Map<String, String> _datasetPaths = {
    '1':   'assets/datasets/billetes/usa_currency/1_dollar',
    '2':   'assets/datasets/billetes/usa_currency/2_dollar',
    '5':   'assets/datasets/billetes/usa_currency/5_dollar',
    '10':  'assets/datasets/billetes/usa_currency/10_dollar',
    '20':  'assets/datasets/billetes/usa_currency/20_dollar',
    '50':  'assets/datasets/billetes/usa_currency/50 Dollar',
    '100': 'assets/datasets/billetes/usa_currency/100 Dollar',
  };
  static const int _samplesPerDenomination = 20;

  // ── CAPA 1: Palabras clave USD ───────────────────────────────────────────
  static const Map<String, List<String>> _usdKeywords = {
    '1':   ['ONE DOLLAR', 'ONE', 'WASHINGTON', 'IN GOD WE TRUST',
      'THE UNITED STATES OF AMERICA', 'FEDERAL RESERVE NOTE'],
    '2':   ['TWO DOLLARS', 'TWO', 'JEFFERSON', 'MONTICELLO',
      'THE UNITED STATES OF AMERICA'],
    '5':   ['FIVE DOLLARS', 'FIVE', 'LINCOLN', 'MEMORIAL',
      'THE UNITED STATES OF AMERICA'],
    '10':  ['TEN DOLLARS', 'TEN', 'HAMILTON', 'TREASURY',
      'THE UNITED STATES OF AMERICA'],
    '20':  ['TWENTY DOLLARS', 'TWENTY', 'JACKSON', 'WHITE HOUSE',
      'THE UNITED STATES OF AMERICA'],
    '50':  ['FIFTY DOLLARS', 'FIFTY', 'GRANT', 'CAPITOL',
      'THE UNITED STATES OF AMERICA'],
    '100': ['ONE HUNDRED', 'HUNDRED DOLLARS', 'FRANKLIN', 'INDEPENDENCE HALL',
      'THE UNITED STATES OF AMERICA', '100'],
  };

  // ── CAPA 1: Palabras clave Ecuador ───────────────────────────────────────
  static const Map<String, List<String>> _ecuadorKeywords = {
    '1':   ['UN DÓLAR', 'UN DOLLAR', 'BANCO CENTRAL DEL ECUADOR',
      'REPÚBLICA DEL ECUADOR'],
    '5':   ['CINCO DÓLARES', 'CINCO DOLARES', 'BANCO CENTRAL DEL ECUADOR'],
    '10':  ['DIEZ DÓLARES', 'DIEZ DOLARES', 'BANCO CENTRAL DEL ECUADOR'],
    '20':  ['VEINTE DÓLARES', 'VEINTE DOLARES', 'BANCO CENTRAL DEL ECUADOR'],
    '50':  ['CINCUENTA DÓLARES', 'CINCUENTA DOLARES',
      'BANCO CENTRAL DEL ECUADOR'],
    '100': ['CIEN DÓLARES', 'CIEN DOLARES', 'BANCO CENTRAL DEL ECUADOR'],
    '5000':  ['CINCO MIL SUCRES', 'BANCO CENTRAL DEL ECUADOR'],
    '10000': ['DIEZ MIL SUCRES', 'BANCO CENTRAL DEL ECUADOR'],
    '50000': ['CINCUENTA MIL SUCRES', 'BANCO CENTRAL DEL ECUADOR'],
  };

  // ── CAPA 2: Patrones numéricos directos ──────────────────────────────────
  // Los billetes imprimen su valor numéricamente en varias esquinas.
  // Patrones ordenados de más específico a menos específico.
  static const List<Map<String, dynamic>> _numericPatterns = [
    {'pattern': r'\b100\b',   'denom': '100', 'score': 4},
    {'pattern': r'\b50\b',    'denom': '50',  'score': 4},
    {'pattern': r'\b20\b',    'denom': '20',  'score': 4},
    {'pattern': r'\b10\b',    'denom': '10',  'score': 4},
    {'pattern': r'\b5\b',     'denom': '5',   'score': 3},
    {'pattern': r'\b2\b',     'denom': '2',   'score': 3},
    {'pattern': r'\b1\b',     'denom': '1',   'score': 2},
    // Con símbolo de dólar
    {'pattern': r'\$100',     'denom': '100', 'score': 5},
    {'pattern': r'\$50',      'denom': '50',  'score': 5},
    {'pattern': r'\$20',      'denom': '20',  'score': 5},
    {'pattern': r'\$10',      'denom': '10',  'score': 5},
    {'pattern': r'\$5',       'denom': '5',   'score': 4},
    {'pattern': r'\$2',       'denom': '2',   'score': 4},
    {'pattern': r'\$1',       'denom': '1',   'score': 3},
  ];

  // ── Indicadores genéricos de billete ────────────────────────────────────
  static const List<String> _genericBillKeywords = [
    'FEDERAL RESERVE', 'LEGAL TENDER', 'THIS NOTE IS LEGAL',
    'THE UNITED STATES', 'SECRETARY OF THE TREASURY', 'TREASURER',
    'BANCO CENTRAL', 'REPÚBLICA DEL ECUADOR', 'ECUADOR',
    'DOLLARS', 'DÓLARES', 'DOLARES', 'SERIES', 'NOTE',
  ];

  // ════════════════════════════════════════════════════════════════════════
  // INICIALIZACIÓN
  // ════════════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    if (_isInitialized) return;
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _isInitialized = true;
    print('✅ ML Kit OCR inicializado');
    _loadDatasetHistograms();
  }

  Future<void> _loadDatasetHistograms() async {
    if (_datasetLoaded) return;
    print('📂 Cargando histogramas del dataset...');
    int totalLoaded = 0;

    for (final entry in _datasetPaths.entries) {
      final denom   = entry.key;
      final dirPath = entry.value;
      _referenceHistograms[denom] = [];

      try {
        final manifestContent = await rootBundle.loadString('AssetManifest.json');
        final allAssets = _parseAssetManifest(manifestContent);

        final denomAssets = allAssets
            .where((a) => a.startsWith(dirPath) && _isImageFile(a))
            .toList();

        if (denomAssets.isEmpty) {
          print('  ⚠️ \$$denom: sin imágenes en $dirPath');
          continue;
        }

        denomAssets.shuffle(Random(42));
        final sample = denomAssets.take(_samplesPerDenomination).toList();

        for (final assetPath in sample) {
          try {
            final bytes   = await rootBundle.load(assetPath);
            final imgData = img.decodeImage(bytes.buffer.asUint8List());
            if (imgData == null) continue;
            _referenceHistograms[denom]!.add(_computeHistogram(imgData));
            totalLoaded++;
          } catch (_) {}
        }

        print('  ✅ \$$denom: ${_referenceHistograms[denom]!.length} referencias');
      } catch (e) {
        print('  ⚠️ Error cargando \$$denom: $e');
      }
    }

    _datasetLoaded = true;
    print('📊 Dataset listo: $totalLoaded histogramas');
  }

  List<String> _parseAssetManifest(String manifestJson) {
    try {
      final decoded = json.decode(manifestJson) as Map<String, dynamic>;
      return decoded.keys.toList();
    } catch (_) { return []; }
  }

  bool _isImageFile(String path) {
    final l = path.toLowerCase();
    return l.endsWith('.jpg') || l.endsWith('.jpeg') ||
        l.endsWith('.png') || l.endsWith('.webp');
  }

  // ════════════════════════════════════════════════════════════════════════
  // DETECCIÓN PRINCIPAL (3 capas)
  // ════════════════════════════════════════════════════════════════════════

  Future<BillDetectionResult> detectBill(String imagePath) async {
    try {
      await initialize();

      // OCR
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await _textRecognizer.processImage(inputImage);
      final fullText   = recognized.text.toUpperCase().trim();

      print('📝 OCR:\n$fullText');
      if (fullText.isEmpty) return _noTextResult();

      // ── CAPA 1: Palabras clave ───────────────────────────────────────
      final List<String> foundKeywords = [];
      final usdMatch = _matchCurrency(fullText, _usdKeywords, foundKeywords);
      final ecuMatch = _matchCurrency(fullText, _ecuadorKeywords, foundKeywords);
      final genericScore = _scoreGenericKeywords(fullText, foundKeywords);

      // ── CAPA 2: Números impresos ─────────────────────────────────────
      final numericResult = _detectByNumericPattern(fullText);
      print('🔢 Detección numérica: ${numericResult?['denom']} (score ${numericResult?['score']})');

      // ── Fusión de capas 1 y 2 ────────────────────────────────────────
      String? bestDenom;
      int    bestScore = 0;
      String bestCurrency = 'USD';

      // Candidatos con sus scores combinados
      final Map<String, int> candidates = {};

      if (usdMatch != null) {
        final d = usdMatch['denomination'] as String;
        candidates[d] = (candidates[d] ?? 0) + (usdMatch['score'] as int) * 3;
      }
      if (ecuMatch != null) {
        final d = ecuMatch['denomination'] as String;
        candidates[d] = (candidates[d] ?? 0) + (ecuMatch['score'] as int) * 3;
      }
      if (numericResult != null) {
        final d = numericResult['denom'] as String;
        candidates[d] = (candidates[d] ?? 0) + (numericResult['score'] as int);
      }

      candidates.forEach((denom, score) {
        if (score > bestScore) {
          bestScore = score;
          bestDenom = denom;
          // Determinar moneda
          if (ecuMatch != null && ecuMatch['denomination'] == denom &&
              (usdMatch == null || ecuMatch['score']! > usdMatch['score']!)) {
            bestCurrency = 'ECU';
          } else {
            bestCurrency = 'USD';
          }
        }
      });

      if (bestDenom != null && bestScore > 0) {
        final symbol = (bestCurrency == 'ECU' && _isHistoricalSucre(bestDenom!))
            ? 'S/.' : '\$';

        final authResult = await _verifyAuthenticity(
          imagePath: imagePath,
          ocrText:   fullText,
          denomKey:  bestDenom!,
        );

        // Confianza: capa 1+2 + bonus dataset, cap 98%
        final confidence = min(45 + bestScore * 5 + authResult.datasetBonus, 98);

        return BillDetectionResult(
          isBill:           true,
          isAuthentic:      authResult.isAuthentic,
          confidence:       '$confidence%',
          denomination:     '$symbol$bestDenom',
          currency:         bestCurrency,
          details:          authResult.details,
          detectedKeywords: foundKeywords,
        );
      }

      // Sin denominación pero con señales de billete
      if (genericScore > 0) {
        return BillDetectionResult(
          isBill:      true,
          isAuthentic: _quickOCRAuthenticity(fullText, imagePath),
          confidence:  '${min(40 + genericScore * 8, 68).toInt()}%',
          denomination: 'No identificada',
          currency:    _guessCurrencyByColor(imagePath),
          details:     'Billete detectado. No se pudo leer la denominación. '
              'Intenta con mejor iluminación.',
          detectedKeywords: foundKeywords,
        );
      }

      return _notABillResult();

    } catch (e) {
      print('❌ Error: $e');
      return BillDetectionResult(
        isBill: false, isAuthentic: false, confidence: '0%',
        denomination: 'Error', currency: 'UNKNOWN',
        details: 'Error al procesar la imagen: $e',
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // CAPA 2: Detección por patrones numéricos
  // ════════════════════════════════════════════════════════════════════════

  Map<String, dynamic>? _detectByNumericPattern(String text) {
    // Contar cuántas veces aparece cada denominación y con qué score
    final Map<String, int> scores = {};

    for (final p in _numericPatterns) {
      final pattern = p['pattern'] as String;
      final denom   = p['denom']   as String;
      final score   = p['score']   as int;

      final regex   = RegExp(pattern);
      final matches = regex.allMatches(text);

      if (matches.isNotEmpty) {
        // Bonus por múltiples apariciones (los billetes repiten su valor)
        final bonus = min(matches.length, 4);
        scores[denom] = (scores[denom] ?? 0) + score * bonus;
      }
    }

    if (scores.isEmpty) return null;

    // Devolver la denominación con mayor score
    String bestDenom = scores.keys.first;
    int    bestScore = scores.values.first;

    scores.forEach((d, s) {
      if (s > bestScore) { bestScore = s; bestDenom = d; }
    });

    return {'denom': bestDenom, 'score': bestScore};
  }

  // ════════════════════════════════════════════════════════════════════════
  // CAPA 3: Verificación de autenticidad (OCR + dataset)
  // ════════════════════════════════════════════════════════════════════════

  Future<_AuthResult> _verifyAuthenticity({
    required String imagePath,
    required String ocrText,
    required String denomKey,
  }) async {
    final ocrScore = _scoreOCRAuthenticity(ocrText, imagePath);
    int datasetBonus = 0;
    String datasetDetail = '';

    final refs = _referenceHistograms[denomKey];

    if (refs != null && refs.isNotEmpty) {
      final capturedImage = img.decodeImage(File(imagePath).readAsBytesSync());

      if (capturedImage != null) {
        // ✨ NUEVO: Evaluar calidad de imagen
        final imageQuality = _assessImageQuality(capturedImage);
        print('📸 Calidad de imagen: ${(imageQuality * 100).toStringAsFixed(1)}%');

        final capturedHist = _computeHistogram(capturedImage);

        double maxSimilarity = 0.0;
        for (final refHist in refs) {
          final sim = _histogramSimilarity(capturedHist, refHist);
          if (sim > maxSimilarity) maxSimilarity = sim;
        }

        final simPct = (maxSimilarity * 100).toStringAsFixed(1);
        print('📊 Similitud dataset \$$denomKey: $simPct%');

        // ✨ NUEVO: Umbrales dinámicos según calidad
        if (imageQuality > 0.8) {
          // Imagen de buena calidad: umbrales estrictos
          if (maxSimilarity >= 0.80) {
            datasetBonus = 8;
            datasetDetail = 'Alta similitud con billetes auténticos ($simPct%).';
          } else if (maxSimilarity >= 0.65) {
            datasetBonus = 5;
            datasetDetail = 'Similitud moderada con el dataset ($simPct%).';
          } else if (maxSimilarity >= 0.50) {
            datasetBonus = 2;
            datasetDetail = 'Similitud baja ($simPct%). Verifica manualmente.';
          }
        } else if (imageQuality > 0.5) {
          // Imagen de calidad media: umbrales permisivos
          if (maxSimilarity >= 0.65) {
            datasetBonus = 7;
            datasetDetail = 'Similitud buena a pesar de calidad de imagen moderada ($simPct%).';
          } else if (maxSimilarity >= 0.50) {
            datasetBonus = 4;
            datasetDetail = 'Similitud aceptable ($simPct%).';
          } else if (maxSimilarity >= 0.40) {
            datasetBonus = 1;
            datasetDetail = 'Similitud limitada ($simPct%). Mejora iluminación.';
          }
        } else {
          // Imagen de baja calidad: solo bonus si hay similitud clara
          if (maxSimilarity >= 0.50) {
            datasetBonus = 3;
            datasetDetail = 'Similitud detectada ($simPct%) en imagen de baja calidad.';
          } else {
            datasetDetail = 'Poca similitud ($simPct%). Foto de muy baja calidad.';
          }
        }
      }
    } else {
      datasetDetail = 'Sin referencias de dataset para \$$denomKey.';
    }

    final total = ocrScore + datasetBonus;
    final isAuth = total >= 7;

    print('🔒 OCR: $ocrScore | Dataset: $datasetBonus | Total: $total | Auth: $isAuth');

    return _AuthResult(
      isAuthentic: isAuth,
      datasetBonus: datasetBonus,
      details: isAuth
          ? '✅ Billete auténtico. $datasetDetail'
          : '⚠️ Billete sospechoso. $datasetDetail',
    );
  }

// ✨ NUEVO: Evaluar calidad de imagen
  double _assessImageQuality(img.Image image) {
    final gray = _toGrayscale(image);

    // Factor 1: Brillo (30% peso)
    final mean = gray.reduce((a, b) => a + b) ~/ gray.length;
    final brightScore =
    (mean >= 80 && mean <= 180) ? 1.0 :
    (mean < 40 || mean > 220 ? 0.2 : 0.6);

    // Factor 2: Contraste (30% peso)
    gray.sort();
    final contrast = gray.last - gray.first;
    final contrastScore =
    (contrast > 100) ? 1.0 :
    (contrast < 40 ? 0.3 : 0.7);

    // Factor 3: Nitidez (40% peso)
    final sharpnessScore = _computeSharpness(image);

    final quality = brightScore * 0.3 + contrastScore * 0.3 + sharpnessScore * 0.4;
    print('  - Brillo: ${(brightScore * 100).toStringAsFixed(0)}%');
    print('  - Contraste: ${(contrastScore * 100).toStringAsFixed(0)}%');
    print('  - Nitidez: ${(sharpnessScore * 100).toStringAsFixed(0)}%');

    return quality;
  }

// ✨ NUEVO: Calcular nitidez usando Laplaciano
  double _computeSharpness(img.Image image) {
    const kernel = [[0, -1, 0], [-1, 4, -1], [0, -1, 0]];
    final gray = _toGrayscale(image);

    int sharpPixels = 0;
    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        double sum = 0;
        for (int ky = 0; ky < 3; ky++) {
          for (int kx = 0; kx < 3; kx++) {
            final idx = (y - 1 + ky) * image.width + (x - 1 + kx);
            if (idx >= 0 && idx < gray.length) {
              sum += kernel[ky][kx] * gray[idx];
            }
          }
        }
        if (sum.abs() > 100) sharpPixels++;
      }
    }

    return (sharpPixels / (image.width * image.height)).clamp(0.0, 1.0);
  }

// ✨ NUEVO: Helper para escala de grises
  List<int> _toGrayscale(img.Image image) {
    final result = <int>[];
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        final gray = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b).toInt();
        result.add(gray.clamp(0, 255));
      }
    }
    return result;
  }

  // ════════════════════════════════════════════════════════════════════════
  // HISTOGRAMA
  // ════════════════════════════════════════════════════════════════════════

  ColorHistogram _computeHistogram(img.Image image) {
    const bins = 16, size = 64;
    final resized = img.copyResize(image, width: size, height: size);

    final rBins = List<double>.filled(bins, 0);
    final gBins = List<double>.filled(bins, 0);
    final bBins = List<double>.filled(bins, 0);

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final px = resized.getPixel(x, y);
        rBins[(px.r.toInt() * bins ~/ 256)]++;
        gBins[(px.g.toInt() * bins ~/ 256)]++;
        bBins[(px.b.toInt() * bins ~/ 256)]++;
      }
    }

    const total = size * size;
    return [
      ...rBins.map((v) => v / total),
      ...gBins.map((v) => v / total),
      ...bBins.map((v) => v / total),
    ];
  }

  double _histogramSimilarity(ColorHistogram h1, ColorHistogram h2) {
    if (h1.length != h2.length) return 0.0;
    double intersection = 0.0, sumH1 = 0.0;
    for (int i = 0; i < h1.length; i++) {
      intersection += min(h1[i], h2[i]);
      sumH1 += h1[i];
    }
    return sumH1 > 0 ? intersection / sumH1 : 0.0;
  }

  // ════════════════════════════════════════════════════════════════════════
  // AUTENTICIDAD POR OCR
  // ════════════════════════════════════════════════════════════════════════

  int _scoreOCRAuthenticity(String ocrText, String imagePath) {
    int score = 0;

    // Número de serie (AB12345678C)
    if (RegExp(r'[A-Z]{1,2}\d{6,9}[A-Z]?').hasMatch(ocrText)) score += 3;

    // Cantidad de texto
    final chars = ocrText.replaceAll(RegExp(r'\s'), '').length;
    if (chars > 40)      score += 3;
    else if (chars > 20) score += 1;

    // Palabras de seguridad
    const secWords = [
      'LEGAL TENDER', 'THIS NOTE IS LEGAL', 'IN GOD WE TRUST',
      'FEDERAL RESERVE', 'SECRETARY', 'TREASURER',
      'BANCO CENTRAL', 'REPÚBLICA',
    ];
    for (final w in secWords) {
      if (ocrText.contains(w)) score += 2;
    }

    // Calidad de imagen
    final file = File(imagePath);
    if (file.existsSync()) {
      final kb = file.lengthSync() / 1024;
      if (kb > 200)     score += 2;
      else if (kb > 80) score += 1;
    }

    return score;
  }

  bool _quickOCRAuthenticity(String ocrText, String imagePath) =>
      _scoreOCRAuthenticity(ocrText, imagePath) >= 5;

  // ════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════════════

  Map<String, dynamic>? _matchCurrency(
      String text,
      Map<String, List<String>> keywordsMap,
      List<String> foundKeywords,
      ) {
    String? bestDenom; int bestScore = 0;
    for (final entry in keywordsMap.entries) {
      int score = 0;
      for (final kw in entry.value) {
        if (text.contains(kw)) {
          score++;
          if (!foundKeywords.contains(kw)) foundKeywords.add(kw);
        }
      }
      if (score > bestScore) { bestScore = score; bestDenom = entry.key; }
    }
    if (bestScore == 0 || bestDenom == null) return null;
    return {'denomination': bestDenom, 'score': bestScore};
  }

  int _scoreGenericKeywords(String text, List<String> foundKeywords) {
    int score = 0;
    for (final kw in _genericBillKeywords) {
      if (text.contains(kw)) {
        score++;
        if (!foundKeywords.contains(kw)) foundKeywords.add(kw);
      }
    }
    return score;
  }

  String _guessCurrencyByColor(String imagePath) {
    try {
      final image = img.decodeImage(File(imagePath).readAsBytesSync());
      if (image == null) return 'UNKNOWN';
      final cx = image.width ~/ 2, cy = image.height ~/ 2;
      int tR = 0, tG = 0, tB = 0, n = 0;
      for (int dy = -30; dy <= 30; dy += 5) {
        for (int dx = -30; dx <= 30; dx += 5) {
          final px = image.getPixel(cx + dx, cy + dy);
          tR += px.r.toInt(); tG += px.g.toInt(); tB += px.b.toInt(); n++;
        }
      }
      if (n == 0) return 'UNKNOWN';
      final aR = tR ~/ n, aG = tG ~/ n;
      if (aG > aR + 15) return 'USD';
      if (aR >= aG - 10) return 'ECU';
      return 'UNKNOWN';
    } catch (_) { return 'UNKNOWN'; }
  }

  BillDetectionResult _noTextResult() => BillDetectionResult(
    isBill: false, isAuthentic: false, confidence: '0%',
    denomination: 'No detectada', currency: 'UNKNOWN',
    details: 'No se pudo leer texto. Asegúrate de que el billete esté '
        'bien iluminado, plano y completamente visible.',
  );

  BillDetectionResult _notABillResult() => BillDetectionResult(
    isBill: false, isAuthentic: false, confidence: '0%',
    denomination: 'No es un billete', currency: 'UNKNOWN',
    details: 'La imagen no parece ser un billete. Enfoca directamente sobre él.',
  );

  bool _isHistoricalSucre(String denom) =>
      ['5000', '10000', '50000'].contains(denom);

  void dispose() {
    if (_isInitialized) {
      _textRecognizer.close();
      _isInitialized = false;
    }
  }
}

class _AuthResult {
  final bool   isAuthentic;
  final int    datasetBonus;
  final String details;
  const _AuthResult({
    required this.isAuthentic,
    required this.datasetBonus,
    required this.details,
  });
}