import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class SerialNumberValidator {
  /// Valida que el número de serie sea auténtico
  Future<SerialValidationResult> validateSerialNumber(
      String imagePath,
      String ocrText,
      String currency,
      ) async {
    try {
      // 1. Extraer número de serie
      final serialNumber = _extractSerialNumber(ocrText);
      if (serialNumber == null) {
        return SerialValidationResult(
          isValid: false,
          serialNumber: null,
          issues: ['No se encontró número de serie legible'],
          confidence: 0.0,
        );
      }

      // 2. Validar formato
      final formatValid = _validateFormat(serialNumber, currency);
      if (!formatValid.isValid) {
        return SerialValidationResult(
          isValid: false,
          serialNumber: serialNumber,
          issues: formatValid.issues,
          confidence: 0.3,
        );
      }

      // 3. Validar checksum (si aplica)
      final checksumValid = _validateChecksum(serialNumber);

      // 4. Validar que aparece 2 veces (frente y reverso típicamente)
      final appearanceCount = _countAppearances(ocrText, serialNumber);

      // 5. Detectar patrones de falsificación común
      final notForged = _detectCommonForgedPatterns(serialNumber);

      final issues = <String>[];
      if (!checksumValid) issues.add('Checksum inválido');
      if (appearanceCount < 2) issues.add('Número de serie aparece solo una vez');
      if (!notForged.isValid) issues.addAll(notForged.issues);

      final score = _calculateSerialScore(
        appearanceCount,
        checksumValid,
        notForged.isValid,
      );

      return SerialValidationResult(
        isValid: issues.isEmpty && score > 0.8,
        serialNumber: serialNumber,
        issues: issues,
        confidence: score,
      );
    } catch (e) {
      print('❌ Error validando número de serie: $e');
      return SerialValidationResult(
        isValid: false,
        serialNumber: null,
        issues: ['Error: $e'],
        confidence: 0.0,
      );
    }
  }

  /// Extrae número de serie del OCR
  String? _extractSerialNumber(String text) {
    // Patrones USD: A12345678B, AB123456789, etc.
    // Patrones ECU: Similar

    final patterns = [
      RegExp(r'[A-Z]{1,2}\d{8}[A-Z]?'),    // Estándar
      RegExp(r'[A-Z]\d{9}[A-Z]'),          // Alternativo
      RegExp(r'([A-Z]{1,2})(\d{6,9})([A-Z]?)'), // Flexible
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return match.group(0);
      }
    }

    return null;
  }

  /// Valida formato del número de serie
  FormatValidationResult _validateFormat(String serial, String currency) {
    final issues = <String>[];

    if (currency == 'USD') {
      // USD: típicamente 2 letras + 8 dígitos + 1 letra
      if (!RegExp(r'^[A-Z]{1,2}\d{8}[A-Z]?$').hasMatch(serial)) {
        issues.add('Formato USD inválido: esperado 2 letras + 8 dígitos');
      }

      // Validar que no sea repetitivo (00000000 es sospechoso)
      if (RegExp(r'\d{6,}').firstMatch(serial)?.group(0) ==
          '0' * RegExp(r'\d{6,}').firstMatch(serial)!.group(0)!.length) {
        issues.add('Dígitos repetitivos detectados (posible falsificación)');
      }
    } else if (currency == 'ECU') {
      if (!RegExp(r'^[A-Z]{1,2}\d{6,9}[A-Z]?$').hasMatch(serial)) {
        issues.add('Formato Ecuador inválido');
      }
    }

    return FormatValidationResult(
      isValid: issues.isEmpty,
      issues: issues,
    );
  }

  /// Valida checksum (si la serie incluye dígito de control)
  bool _validateChecksum(String serial) {
    // Implementar algoritmo de checksum según estándar de billete
    // Ejemplo: Luhn algorithm

    final digits = serial.replaceAll(RegExp(r'[A-Z]'), '');
    if (digits.isEmpty) return false;

    int sum = 0;
    int multiplier = 2;

    for (int i = digits.length - 1; i >= 0; i--) {
      int digit = int.parse(digits[i]);
      int product = digit * multiplier;

      if (product > 9) {
        product = (product ~/ 10) + (product % 10);
      }

      sum += product;
      multiplier = multiplier == 2 ? 1 : 2;
    }

    return sum % 10 == 0;
  }

  /// Cuenta cuántas veces aparece el número de serie
  int _countAppearances(String text, String serial) {
    return RegExp(serial).allMatches(text).length;
  }

  /// Detecta patrones comunes de falsificación
  ForgeDetectionResult _detectCommonForgedPatterns(String serial) {
    final issues = <String>[];

    // 1. Números demasiado bonitos (secuencial)
    if (RegExp(r'01234|12345|23456|34567|45678|56789').hasMatch(serial)) {
      issues.add('Secuencia numérica sospechosa');
    }

    // 2. Todas las mismas letras
    final letras = serial.replaceAll(RegExp(r'\d'), '');
    if (letras.isNotEmpty && letras.split('').toSet().length == 1) {
      issues.add('Letras repetitivas (patrón típico de falsificación)');
    }

    // 3. Dígitos muy simples
    final digits = serial.replaceAll(RegExp(r'[A-Z]'), '');
    if (RegExp(r'^00+|11+|22+|33+').hasMatch(digits)) {
      issues.add('Dígitos altamente repetitivos');
    }

    return ForgeDetectionResult(
      isValid: issues.isEmpty,
      issues: issues,
    );
  }

  double _calculateSerialScore(
      int appearanceCount,
      bool checksumValid,
      bool notForged,
      ) {
    double score = 0.0;

    if (checksumValid) score += 0.4;
    if (appearanceCount >= 2) score += 0.4;
    if (notForged) score += 0.2;

    return score.clamp(0.0, 1.0);
  }
}

class SerialValidationResult {
  final bool isValid;
  final String? serialNumber;
  final List<String> issues;
  final double confidence;

  SerialValidationResult({
    required this.isValid,
    required this.serialNumber,
    required this.issues,
    required this.confidence,
  });
}

class FormatValidationResult {
  final bool isValid;
  final List<String> issues;

  FormatValidationResult({
    required this.isValid,
    required this.issues,
  });
}

class ForgeDetectionResult {
  final bool isValid;
  final List<String> issues;

  ForgeDetectionResult({
    required this.isValid,
    required this.issues,
  });
}