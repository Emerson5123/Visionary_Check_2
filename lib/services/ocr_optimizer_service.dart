import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';

class OCROptimizerService {
  static Future<OptimizedOCRResult> optimizeAndRecognize(String imagePath) async {
    try {
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      var image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('No se pudo decodificar imagen');
      }

      print('\n📸 OPTIMIZANDO IMAGEN PARA OCR...');

      // 1. Mejorar contraste
      print('  1️⃣ Mejorando contraste...');
      image = _enhanceContrast(image);

      // 2. Ajustar brillo
      print('  2️⃣ Ajustando brillo...');
      image = _adjustBrightness(image);

      // 3. Reducir ruido
      print('  3️⃣ Reduciendo ruido...');
      image = _reduceNoise(image);

      // 4. Intentar con orientaciones diferentes
      print('  4️⃣ Probando orientaciones...');
      final results = <String, double>{};

      // Original
      var text = await _recognizeText(image);
      results['0°'] = _calculateTextQuality(text);
      print('     0°: ${text.length} caracteres');

      // Rotación 90°
      var rotated90 = img.copyRotate(image, angle: 90);
      text = await _recognizeText(rotated90);
      results['90°'] = _calculateTextQuality(text);
      print('     90°: ${text.length} caracteres');

      // Rotación 180°
      var rotated180 = img.copyRotate(image, angle: 180);
      text = await _recognizeText(rotated180);
      results['180°'] = _calculateTextQuality(text);
      print('     180°: ${text.length} caracteres');

      // Rotación 270°
      var rotated270 = img.copyRotate(image, angle: 270);
      text = await _recognizeText(rotated270);
      results['270°'] = _calculateTextQuality(text);
      print('     270°: ${text.length} caracteres');

      // Encontrar mejor orientación
      String bestAngle = '0°';
      double bestScore = results['0°']!;

      results.forEach((angle, score) {
        if (score > bestScore) {
          bestScore = score;
          bestAngle = angle;
        }
      });

      print('  ✅ Mejor orientación: $bestAngle (score: ${bestScore.toStringAsFixed(2)})');

      // 5. Reconocer con mejor orientación
      print('  5️⃣ Reconociendo con orientación óptima...');
      img.Image finalImage = image;
      if (bestAngle == '90°') finalImage = img.copyRotate(image, angle: 90);
      if (bestAngle == '180°') finalImage = img.copyRotate(image, angle: 180);
      if (bestAngle == '270°') finalImage = img.copyRotate(image, angle: 270);

      final finalText = await _recognizeText(finalImage);

      print('  ✅ OCR completado: ${finalText.length} caracteres\n');

      return OptimizedOCRResult(
        text: finalText,
        bestAngle: bestAngle,
        quality: bestScore,
        allResults: results,
      );
    } catch (e) {
      print('  ❌ Error: $e\n');
      return OptimizedOCRResult(
        text: '',
        bestAngle: '0°',
        quality: 0.0,
        allResults: {},
      );
    }
  }

  static img.Image _enhanceContrast(img.Image image) {
    final result = img.Image(
      width: image.width,
      height: image.height,
      numChannels: image.numChannels,
    );

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        final r = _adjustPixel(px.r.toInt(), 1.5, 0);
        final g = _adjustPixel(px.g.toInt(), 1.5, 0);
        final b = _adjustPixel(px.b.toInt(), 1.5, 0);

        result.setPixelRgba(x, y, r, g, b, px.a.toInt());
      }
    }

    return result;
  }

  static img.Image _adjustBrightness(img.Image image) {
    final result = img.Image(
      width: image.width,
      height: image.height,
      numChannels: image.numChannels,
    );

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        final r = _adjustPixel(px.r.toInt(), 1.0, 15);
        final g = _adjustPixel(px.g.toInt(), 1.0, 15);
        final b = _adjustPixel(px.b.toInt(), 1.0, 15);

        result.setPixelRgba(x, y, r, g, b, px.a.toInt());
      }
    }

    return result;
  }

  static img.Image _reduceNoise(img.Image image) {
    // Blur ligero (3x3 kernel)
    return img.gaussianBlur(image, radius: 1);
  }

  static int _adjustPixel(int pixel, double contrast, int brightness) {
    int adjusted = ((pixel - 128) * contrast + 128 + brightness).toInt();
    return adjusted.clamp(0, 255);
  }

  static Future<String> _recognizeText(img.Image image) async {
    try {
      // Guardar imagen temporalmente
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/ocr_temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(img.encodeJpg(image));

      // Reconocer
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognized = await textRecognizer.processImage(inputImage);
      final text = recognized.text.toUpperCase();

      // Limpiar
      textRecognizer.close();
      await tempFile.delete();

      return text;
    } catch (e) {
      return '';
    }
  }

  static double _calculateTextQuality(String text) {
    if (text.isEmpty) return 0.0;

    // Criterios de calidad:
    double score = 0.0;

    // 1. Longitud (esperar al menos 50 caracteres en un billete)
    if (text.length > 50) score += 0.3;
    else if (text.length > 30) score += 0.15;

    // 2. Palabras clave esperadas
    int keywordCount = 0;
    final keywords = [
      'FEDERAL RESERVE',
      'LEGAL TENDER',
      'UNITED STATES',
      'NOTE',
      'TREASURY',
      'SECRETARY'
    ];

    for (final kw in keywords) {
      if (text.contains(kw)) keywordCount++;
    }

    score += (keywordCount / keywords.length) * 0.4;

    // 3. Números legibles
    final numbers = RegExp(r'\d+').allMatches(text);
    if (numbers.isNotEmpty) score += 0.3;

    return score.clamp(0.0, 1.0);
  }
}

class OptimizedOCRResult {
  final String text;
  final String bestAngle;
  final double quality;
  final Map<String, double> allResults;

  OptimizedOCRResult({
    required this.text,
    required this.bestAngle,
    required this.quality,
    required this.allResults,
  });
}