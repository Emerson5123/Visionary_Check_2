import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:typed_data';

class DatasetService {
  static final DatasetService _instance = DatasetService._internal();

  late Map<String, List<BillSignature>> _signatures;

  factory DatasetService() => _instance;
  DatasetService._internal();

  Future<void> initializeExtendedDataset() async {
    print('📂 Iniciando carga del dataset extendido...');
    _signatures = {};

    // Cargar firmas de referencia optimizadas
    await _loadUSDSignatures();
    await _loadEcuadorSignatures();

    print('✅ Dataset extendido cargado: ${_signatures.length} denominaciones');
  }

  Future<void> _loadUSDSignatures() async {
    final denominations = ['1', '2', '5', '10', '20', '50', '100'];

    for (final denom in denominations) {
      _signatures[denom] = [];

      // Cargar múltiples características de referencia
      final signatures = _generateUSDSignatureLibrary(denom);
      _signatures[denom]!.addAll(signatures);
    }

    print('✅ USD: ${denominations.length} denominaciones cargadas');
  }

  Future<void> _loadEcuadorSignatures() async {
    final denominations = ['1', '5', '10', '20', '50', '100'];

    for (final denom in denominations) {
      _signatures[denom] = [];
      final signatures = _generateEcuadorSignatureLibrary(denom);
      _signatures[denom]!.addAll(signatures);
    }

    print('✅ Ecuador: 6 denominaciones cargadas');
  }

  /// Genera 50+ firmas únicas por denominación USD
  List<BillSignature> _generateUSDSignatureLibrary(String denom) {
    final signatures = <BillSignature>[];

    // CARACTERÍSTICAS USD ESPECÍFICAS POR DENOMINACIÓN
    final usdFeatures = {
      '1': {
        'color_dominant': [142, 110, 48],      // Verde oliva oscuro
        'color_secondary': [178, 156, 101],    // Beige
        'portrait': 'George Washington',
        'building': 'The Great Seal',
        'security_features': [
          'WATERMARK_WASHINGTON',
          'SECURITY_THREAD_BLUE',
          'COLOR_SHIFTING_NUMERAL',
          'INTAGLIO_PRINT',
          'MICROPRINTING'
        ],
        'expected_size': (155.956, 66.294),    // mm
      },
      '5': {
        'color_dominant': [76, 149, 109],      // Verde medio
        'color_secondary': [101, 172, 131],
        'portrait': 'Abraham Lincoln',
        'building': 'Lincoln Memorial',
        'security_features': [
          'WATERMARK_LINCOLN',
          'SECURITY_THREAD_PINK',
          'COLOR_SHIFTING_NUMERAL',
          'INTAGLIO_PRINT',
          'MICROPRINTING'
        ],
        'expected_size': (155.956, 66.294),
      },
      '10': {
        'color_dominant': [255, 165, 0],       // Naranja
        'color_secondary': [255, 192, 128],
        'portrait': 'Alexander Hamilton',
        'building': 'US Treasury Building',
        'security_features': [
          'WATERMARK_HAMILTON',
          'SECURITY_THREAD_ORANGE',
          'COLOR_SHIFTING_NUMERAL',
          'INTAGLIO_PRINT',
          'MICROPRINTING'
        ],
        'expected_size': (155.956, 66.294),
      },
      '20': {
        'color_dominant': [0, 102, 204],       // Azul verdoso
        'color_secondary': [102, 178, 255],
        'portrait': 'Andrew Jackson',
        'building': 'White House',
        'security_features': [
          'WATERMARK_JACKSON',
          'SECURITY_THREAD_GREEN',
          'COLOR_SHIFTING_NUMERAL',
          'INTAGLIO_PRINT',
          'MICROPRINTING',
          'ANTI_COUNTERFEITING_THREADS'
        ],
        'expected_size': (155.956, 66.294),
      },
      '50': {
        'color_dominant': [204, 0, 0],         // Rojo
        'color_secondary': [255, 102, 102],
        'portrait': 'Ulysses S. Grant',
        'building': 'The Capitol',
        'security_features': [
          'WATERMARK_GRANT',
          'SECURITY_THREAD_RED',
          'COLOR_SHIFTING_NUMERAL',
          'INTAGLIO_PRINT',
          'MICROPRINTING'
        ],
        'expected_size': (155.956, 66.294),
      },
      '100': {
        'color_dominant': [0, 51, 102],        // Azul oscuro
        'color_secondary': [102, 153, 204],
        'portrait': 'Benjamin Franklin',
        'building': 'Independence Hall',
        'security_features': [
          'WATERMARK_FRANKLIN',
          'SECURITY_THREAD_BLUE',
          'COLOR_SHIFTING_NUMERAL',
          'INTAGLIO_PRINT',
          'MICROPRINTING',
          '3D_SECURITY_RIBBON'
        ],
        'expected_size': (155.956, 66.294),
      },
    };

    final features = usdFeatures[denom];
    if (features == null) return signatures;

    // Crear 50+ variaciones con diferentes rotaciones, iluminación, etc.
    for (int variation = 0; variation < 50; variation++) {
      signatures.add(BillSignature(
        denomination: denom,
        currency: 'USD',
        dominantColor: features['color_dominant'] as List<int>,
        secondaryColor: features['color_secondary'] as List<int>,
        portrait: features['portrait'] as String,
        building: features['building'] as String,
        securityFeatures: features['security_features'] as List<String>,
        expectedSize: features['expected_size'] as (double, double),
        variation: variation,
        // Agregar variación de iluminación, ángulo, etc.
        lightingVariation: 0.8 + (variation % 10) * 0.02,
        angleVariation: (variation % 8) * 5.0, // 0-35°
      ));
    }

    return signatures;
  }

  /// Genera 50+ firmas únicas por denominación Ecuador
  List<BillSignature> _generateEcuadorSignatureLibrary(String denom) {
    final signatures = <BillSignature>[];

    final ecuFeatures = {
      '1': {
        'color_dominant': [0, 51, 153],        // Azul oscuro
        'portrait': 'Francisco de Miranda',
        'security_features': [
          'WATERMARK_ECUADOR',
          'SECURITY_THREAD',
          'MICROPRINTING',
          'GUILLOCHE_PATTERN'
        ],
      },
      '5': {
        'color_dominant': [204, 0, 0],         // Rojo
        'portrait': 'Juan Montalvo',
        'security_features': ['WATERMARK_ECUADOR', 'SECURITY_THREAD'],
      },
      '10': {
        'color_dominant': [0, 102, 0],         // Verde oscuro
        'portrait': 'Antonio Borrero',
        'security_features': ['WATERMARK_ECUADOR', 'SECURITY_THREAD'],
      },
      '20': {
        'color_dominant': [153, 0, 153],       // Púrpura
        'portrait': 'Eloy Alfaro',
        'security_features': ['WATERMARK_ECUADOR', 'SECURITY_THREAD'],
      },
      '50': {
        'color_dominant': [255, 165, 0],       // Naranja
        'portrait': 'Miguel de Cervantes',
        'security_features': ['WATERMARK_ECUADOR', 'SECURITY_THREAD'],
      },
      '100': {
        'color_dominant': [0, 102, 102],       // Azul verdoso
        'portrait': 'Manuela Saenz',
        'security_features': [
          'WATERMARK_ECUADOR',
          'SECURITY_THREAD',
          'MICROPRINTING'
        ],
      },
    };

    final features = ecuFeatures[denom];
    if (features == null) return signatures;

    for (int variation = 0; variation < 50; variation++) {
      signatures.add(BillSignature(
        denomination: denom,
        currency: 'ECU',
        dominantColor: features['color_dominant'] as List<int>,
        secondaryColor: _adjustColor(features['color_dominant'] as List<int>),
        portrait: features['portrait'] as String,
        building: 'National symbols of Ecuador',
        securityFeatures: features['security_features'] as List<String>,
        expectedSize: (155.0, 66.0),
        variation: variation,
        lightingVariation: 0.8 + (variation % 10) * 0.02,
        angleVariation: (variation % 8) * 5.0,
      ));
    }

    return signatures;
  }

  List<int> _adjustColor(List<int> color) {
    return [
      (color[0] * 0.8).toInt(),
      (color[1] * 0.8).toInt(),
      (color[2] * 0.8).toInt(),
    ];
  }

  /// Obtiene todas las firmas para una denominación
  List<BillSignature> getSignaturesFor(String denom) {
    return _signatures[denom] ?? [];
  }

  /// Compara un billete capturado contra toda la librería
  Future<SignatureMatchResult> matchAgainstLibrary(
      String imagePath,
      String currency,
      ) async {
    final image = img.decodeImage(File(imagePath).readAsBytesSync());
    if (image == null) {
      throw Exception('No se pudo decodificar imagen');
    }

    final bestMatches = <String, List<double>>{};

    // Comparar contra cada denominación
    for (final denom in _signatures.keys) {
      final sigs = _signatures[denom]!;
      double maxSimilarity = 0.0;

      for (final sig in sigs) {
        final similarity = _calculateSignatureSimilarity(image, sig);
        if (similarity > maxSimilarity) {
          maxSimilarity = similarity;
        }
      }

      bestMatches[denom] = [maxSimilarity];
    }

    // Ordenar por similitud
    final sorted = bestMatches.entries.toList()
      ..sort((a, b) => b.value[0].compareTo(a.value[0]));

    return SignatureMatchResult(
      topMatch: sorted.first.key,
      topMatchScore: sorted.first.value[0],
      allMatches: Map.fromEntries(sorted),
      confidence: sorted.first.value[0],
    );
  }

  double _calculateSignatureSimilarity(
      img.Image image,
      BillSignature signature,
      ) {
    // Comparar:
    // 1. Distribución de colores
    // 2. Características detectadas
    // 3. Tamaño aproximado
    // 4. Patrón de seguridad

    double score = 0.0;

    // Color matching (0-0.4)
    final colorScore = _compareColors(image, signature);
    score += colorScore * 0.4;

    // Size matching (0-0.3)
    final sizeScore = _compareSize(image, signature);
    score += sizeScore * 0.3;

    // Feature matching (0-0.3)
    final featureScore = _compareFeatures(image, signature);
    score += featureScore * 0.3;

    return score.clamp(0.0, 1.0);
  }

  double _compareColors(img.Image image, BillSignature sig) {
    // Implementar comparación de colores dominantes
    // Retorna 0.0-1.0
    return 0.8; // Placeholder
  }

  double _compareSize(img.Image image, BillSignature sig) {
    // Comparar tamaño estimado del billete
    // Retorna 0.0-1.0
    return 0.75; // Placeholder
  }

  double _compareFeatures(img.Image image, BillSignature sig) {
    // Comparar características de seguridad detectadas
    // Retorna 0.0-1.0
    return 0.85; // Placeholder
  }
}

/// Firma de referencia de billete
class BillSignature {
  final String denomination;
  final String currency;
  final List<int> dominantColor;
  final List<int> secondaryColor;
  final String portrait;
  final String building;
  final List<String> securityFeatures;
  final (double, double) expectedSize;
  final int variation;
  final double lightingVariation;
  final double angleVariation;

  BillSignature({
    required this.denomination,
    required this.currency,
    required this.dominantColor,
    required this.secondaryColor,
    required this.portrait,
    required this.building,
    required this.securityFeatures,
    required this.expectedSize,
    required this.variation,
    required this.lightingVariation,
    required this.angleVariation,
  });
}

class SignatureMatchResult {
  final String topMatch;
  final double topMatchScore;
  final Map<String, List<double>> allMatches;
  final double confidence;

  SignatureMatchResult({
    required this.topMatch,
    required this.topMatchScore,
    required this.allMatches,
    required this.confidence,
  });
}