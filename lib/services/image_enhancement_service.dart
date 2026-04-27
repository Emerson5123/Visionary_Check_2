import 'package:image/image.dart' as img;

/// Servicio de mejora de imagen para optimizar el OCR.
/// Aplica una cadena de procesamiento: normalización → CLAHE → denoising → sharpening.
class ImageEnhancementService {
  /// Punto de entrada principal — mejora una imagen para análisis OCR.
  /// Devuelve una nueva imagen procesada sin modificar la original.
  static img.Image enhanceForAnalysis(img.Image image) {
    try {
      img.Image result = image;

      // 1. Redimensionar si es muy grande (acelera el procesamiento)
      if (result.width > 2000 || result.height > 2000) {
        result = img.copyResize(result, width: 1600);
      }

      // 2. Normalización de brillo/contraste
      result = _normalizeContrast(result);

      // 3. CLAHE simplificado (mejora contraste local por zonas)
      result = _applyCLAHE(result);

      // 4. Reducción de ruido (blur suave)
      result = img.gaussianBlur(result, radius: 1);

      // 5. Sharpening (realzar bordes para OCR)
      result = _sharpen(result);

      return result;
    } catch (e) {
      print('⚠️ ImageEnhancementService error: $e');
      return image; // Devolver original si falla
    }
  }

  // ── Normalización de contraste ────────────────────────────────────────────
  /// Estira el histograma al rango completo 0-255 usando percentiles 5-95.
  static img.Image _normalizeContrast(img.Image image) {
    // Calcular histograma de luminancia
    final hist = List<int>.filled(256, 0);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final px  = image.getPixel(x, y);
        final lum = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b).toInt().clamp(0, 255);
        hist[lum]++;
      }
    }

    // Percentil 5 y 95
    final total   = image.width * image.height;
    final p5count = (total * 0.05).toInt();
    final p95count = (total * 0.95).toInt();

    int p5 = 0, p95 = 255, cumulative = 0;
    for (int i = 0; i < 256; i++) {
      cumulative += hist[i];
      if (cumulative < p5count)  p5  = i;
      if (cumulative < p95count) p95 = i;
    }

    if (p95 <= p5) return image; // Imagen plana — no procesar

    final range = (p95 - p5).toDouble();

    // Aplicar estiramiento
    final result = img.Image(
        width: image.width, height: image.height,
        numChannels: image.numChannels);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        final r = _stretch(px.r.toInt(), p5, range);
        final g = _stretch(px.g.toInt(), p5, range);
        final b = _stretch(px.b.toInt(), p5, range);
        result.setPixelRgba(x, y, r, g, b, px.a.toInt());
      }
    }

    return result;
  }

  static int _stretch(int val, int low, double range) =>
      ((val - low) / range * 255).round().clamp(0, 255);

  // ── CLAHE simplificado ───────────────────────────────────────────────────
  /// Divide la imagen en zonas y normaliza cada una por separado.
  /// Esto mejora el contraste local sin quemar zonas muy brillantes.
  static img.Image _applyCLAHE(img.Image image) {
    const tiles = 4; // 4×4 = 16 zonas
    final tileW  = image.width  ~/ tiles;
    final tileH  = image.height ~/ tiles;

    final result = img.Image(
        width: image.width, height: image.height,
        numChannels: image.numChannels);

    // Copiar imagen original al resultado primero
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        result.setPixel(x, y, image.getPixel(x, y));
      }
    }

    for (int ty = 0; ty < tiles; ty++) {
      for (int tx = 0; tx < tiles; tx++) {
        final x0 = tx * tileW;
        final y0 = ty * tileH;
        final x1 = (tx == tiles - 1) ? image.width  : x0 + tileW;
        final y1 = (ty == tiles - 1) ? image.height : y0 + tileH;

        // Histograma de la zona
        final hist  = List<int>.filled(256, 0);
        int tileTotal = 0;

        for (int y = y0; y < y1; y++) {
          for (int x = x0; x < x1; x++) {
            final px  = image.getPixel(x, y);
            final lum = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b).toInt().clamp(0, 255);
            hist[lum]++;
            tileTotal++;
          }
        }

        if (tileTotal == 0) continue;

        // CDF normalizado para equalización
        final cdf  = List<int>.filled(256, 0);
        cdf[0] = hist[0];
        for (int i = 1; i < 256; i++) cdf[i] = cdf[i - 1] + hist[i];

        final cdfMin = cdf.firstWhere((v) => v > 0, orElse: () => 0);
        final scale  = 255.0 / (tileTotal - cdfMin + 1);

        // Aplicar a la zona con factor de mezcla (blend 50% para suavizar)
        for (int y = y0; y < y1; y++) {
          for (int x = x0; x < x1; x++) {
            final px  = image.getPixel(x, y);
            final lum = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b).toInt().clamp(0, 255);
            final eq  = ((cdf[lum] - cdfMin) * scale).round().clamp(0, 255);

            // Blend 60% equalizado + 40% original
            final blend = (eq * 0.6 + lum * 0.4).round();
            final ratio = lum > 0 ? blend / lum : 1.0;

            final r = (px.r.toInt() * ratio).round().clamp(0, 255);
            final g = (px.g.toInt() * ratio).round().clamp(0, 255);
            final b = (px.b.toInt() * ratio).round().clamp(0, 255);
            result.setPixelRgba(x, y, r, g, b, px.a.toInt());
          }
        }
      }
    }

    return result;
  }

  // ── Sharpening ───────────────────────────────────────────────────────────
  /// Kernel de sharpening 3×3 para realzar bordes y mejorar legibilidad OCR.
  static img.Image _sharpen(img.Image image) {
    // Kernel: unsharp mask suave para no exagerar ruido
    const kernel = [
      [ 0.0, -0.5,  0.0],
      [-0.5,  3.0, -0.5],
      [ 0.0, -0.5,  0.0],
    ];

    final result = img.Image(
        width: image.width, height: image.height,
        numChannels: image.numChannels);

    // Copiar bordes sin cambios
    for (int y = 0; y < image.height; y++) {
      result.setPixel(0, y, image.getPixel(0, y));
      result.setPixel(image.width - 1, y, image.getPixel(image.width - 1, y));
    }
    for (int x = 0; x < image.width; x++) {
      result.setPixel(x, 0, image.getPixel(x, 0));
      result.setPixel(x, image.height - 1, image.getPixel(x, image.height - 1));
    }

    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        double sumR = 0, sumG = 0, sumB = 0;

        for (int ky = 0; ky < 3; ky++) {
          for (int kx = 0; kx < 3; kx++) {
            final px = image.getPixel(x - 1 + kx, y - 1 + ky);
            sumR += px.r * kernel[ky][kx];
            sumG += px.g * kernel[ky][kx];
            sumB += px.b * kernel[ky][kx];
          }
        }

        final origPx = image.getPixel(x, y);
        result.setPixelRgba(
          x, y,
          sumR.round().clamp(0, 255),
          sumG.round().clamp(0, 255),
          sumB.round().clamp(0, 255),
          origPx.a.toInt(),
        );
      }
    }

    return result;
  }
}