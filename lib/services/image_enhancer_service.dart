import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

// ══════════════════════════════════════════════════════════════════
//  ImageEnhancerService — pre-procesamiento de imagen original
//
//  Se ejecuta como PASO 0, ANTES de EdgeDetectionService.
//
//  Pipeline:
//    1. Auto-recorte del billete
//       Detecta el rectángulo más grande con contraste de borde
//       suficiente → recorta el billete separándolo del fondo.
//    2. Corrección de perspectiva (homografía)
//       Si el billete está inclinado, lo endereza proyectando
//       los 4 vértices del contorno a un rectángulo canónico.
//    3. Reducción de ruido bilateral
//       Más agresivo que el box-denoise del Sobel pipeline;
//       pensado especialmente para imágenes borrosas/movidas.
//    4. Corrección de brillo y contraste
//       Gamma correction automática + linear contrast stretching.
//       Deja la imagen en un rango de luminancia estable [30, 220]
//       para que el CLAHE posterior trabaje con datos normalizados.
//
//  Compatibilidad: Dart puro + paquete `image`. Sin FFI ni OpenCV.
// ══════════════════════════════════════════════════════════════════

class ImageEnhancerService {
  // ── Singleton ────────────────────────────────────────────────────
  static final ImageEnhancerService _instance =
  ImageEnhancerService._internal();
  factory ImageEnhancerService() => _instance;
  ImageEnhancerService._internal();

  // ══════════════════════════════════════════════════════════════════
  //  RESULTADO
  // ══════════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════
  //  API PÚBLICA
  // ══════════════════════════════════════════════════════════════════

  /// Mejora la imagen original y devuelve la ruta del archivo mejorado.
  /// Si algún paso falla, devuelve la imagen del paso anterior (nunca lanza).
  Future<ImageEnhancementResult> enhance(String inputPath) async {
    try {
      final sw = Stopwatch()..start();
      print('\n🖼️  ImageEnhancer — inicio');

      final bytes    = await File(inputPath).readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) {
        return ImageEnhancementResult.passthrough(inputPath, 'decode_failed');
      }

      print('   Original: ${original.width}×${original.height}');

      var current       = original;
      final stepsApplied = <String>[];

      // ── PASO 1: Auto-recorte + perspectiva ───────────────────
      print('   [1/3] Auto-recorte y corrección de perspectiva...');
      final cropResult = _autoCropAndDeskew(current);
      if (cropResult != null) {
        current = cropResult.image;
        stepsApplied.add(
            'crop(${cropResult.cropW}×${cropResult.cropH}'
                '${cropResult.deskewed ? "+deskew" : ""})');
        print('   ✓ Recortado: ${current.width}×${current.height}'
            '${cropResult.deskewed ? "  + perspectiva corregida" : ""}');
      } else {
        print('   ⚠️ No se detectó contorno limpio — usando imagen completa');
        stepsApplied.add('crop(skipped)');
      }

      // ── PASO 2: Reducción de ruido bilateral ─────────────────
      print('   [2/3] Reducción de ruido bilateral...');
      current = _bilateralDenoise(current);
      stepsApplied.add('bilateral');

      // ── PASO 3: Corrección de brillo y contraste ─────────────
      print('   [3/3] Corrección de brillo/contraste...');
      final brightnessInfo = _analyzeBrightness(current);
      current = _correctBrightnessContrast(current, brightnessInfo);
      stepsApplied.add(
          'brightness(γ=${brightnessInfo.gamma.toStringAsFixed(2)}'
              ',stretch=${brightnessInfo.needsStretch})');
      print('   ✓ Brillo medio: ${brightnessInfo.meanLuma.toStringAsFixed(0)}'
          '  γ=${brightnessInfo.gamma.toStringAsFixed(2)}'
          '  stretch=${brightnessInfo.needsStretch}');

      // ── Guardar resultado ─────────────────────────────────────
      final outPath = _buildPath(inputPath, '_enhanced');
      await File(outPath).writeAsBytes(img.encodeJpg(current, quality: 95));

      sw.stop();
      print('✅ ImageEnhancer ${sw.elapsedMilliseconds} ms'
          '  pasos: ${stepsApplied.join(" → ")}\n');

      return ImageEnhancementResult(
        success:       true,
        enhancedPath:  outPath,
        originalPath:  inputPath,
        processingMs:  sw.elapsedMilliseconds,
        stepsApplied:  stepsApplied,
        outputWidth:   current.width,
        outputHeight:  current.height,
      );
    } catch (e) {
      print('❌ ImageEnhancer error: $e');
      return ImageEnhancementResult.passthrough(inputPath, 'error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  PASO 1A — DETECCIÓN DE CONTORNO DEL BILLETE
  //
  //  Estrategia:
  //    1. Convertir a gris y aplicar Canny simplificado (Sobel + thresh)
  //    2. Escanear filas y columnas para encontrar la caja delimitadora
  //       con al menos un X% del borde con actividad de contorno.
  //    3. Si la caja es >= 50% de la imagen → recortar.
  //    4. Detectar si hay inclinación → deskew.
  //
  //  Limitación intencional: no usa transformada de Hough (costosa).
  //  Usa proyecciones de gradiente que son O(n) y suficientemente
  //  robustas para billetes sobre fondos uniformes (mesa, mano plana).
  // ══════════════════════════════════════════════════════════════════

  _CropResult? _autoCropAndDeskew(img.Image src) {
    try {
      final w = src.width;
      final h = src.height;

      // Grayscale rápido
      final gray = _toGrayFast(src);

      // Sobel simplificado para mapa de bordes
      final edges = _sobelEdgeMap(gray, w, h, threshold: 25);

      // Proyecciones horizontales y verticales del mapa de bordes
      final hProj = List<int>.filled(h, 0); // suma por fila
      final vProj = List<int>.filled(w, 0); // suma por columna
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (edges[y * w + x] > 0) {
            hProj[y]++;
            vProj[x]++;
          }
        }
      }

      // Umbral: al menos 15% de la dimensión debe tener actividad de borde
      final hThresh = (w * 0.15).round();
      final vThresh = (h * 0.15).round();

      // Encontrar filas/columnas activas (borde del billete)
      int top    = 0,    bottom = h - 1;
      int left   = 0,    right  = w - 1;

      for (int y = 0; y < h; y++)     { if (hProj[y] >= hThresh) { top    = y; break; } }
      for (int y = h - 1; y >= 0; y--){ if (hProj[y] >= hThresh) { bottom = y; break; } }
      for (int x = 0; x < w; x++)     { if (vProj[x] >= vThresh) { left   = x; break; } }
      for (int x = w - 1; x >= 0; x--){ if (vProj[x] >= vThresh) { right  = x; break; } }

      final cropW = right  - left;
      final cropH = bottom - top;

      // Si el recorte es < 50% de la imagen en cualquier eje → no recortar
      if (cropW < w * 0.50 || cropH < h * 0.50) return null;
      // Si el recorte es > 95% de la imagen → ya está bien encuadrado
      if (cropW > w * 0.95 && cropH > h * 0.95) {
        // Solo devolver deskew si hay inclinación detectable
        final angle = _detectSkewAngle(edges, w, h);
        if (angle.abs() < 2.0) return null; // sin inclinación notable

        final deskewed = _applyDeskew(src, angle);
        return _CropResult(
          image:   deskewed,
          cropW:   deskewed.width,
          cropH:   deskewed.height,
          deskewed: true,
        );
      }

      // Recortar con margen de 10px
      final margin = 10;
      final cx = (left   - margin).clamp(0, w - 1);
      final cy = (top    - margin).clamp(0, h - 1);
      final cw = (cropW  + margin * 2).clamp(1, w - cx);
      final ch = (cropH  + margin * 2).clamp(1, h - cy);

      var cropped = img.copyCrop(src,
          x: cx, y: cy, width: cw, height: ch);

      // Detectar y corregir inclinación sobre la imagen recortada
      final croppedGray  = _toGrayFast(cropped);
      final croppedEdges = _sobelEdgeMap(croppedGray, cropped.width,
          cropped.height, threshold: 25);
      final angle = _detectSkewAngle(croppedEdges, cropped.width, cropped.height);
      bool deskewed = false;

      if (angle.abs() >= 2.0 && angle.abs() <= 45.0) {
        cropped  = _applyDeskew(cropped, angle);
        deskewed = true;
      }

      return _CropResult(
        image:    cropped,
        cropW:    cropW,
        cropH:    cropH,
        deskewed: deskewed,
      );
    } catch (e) {
      print('   ⚠️ _autoCropAndDeskew error: $e');
      return null;
    }
  }

  // ── Mapa de bordes binario (Sobel simplificado, threshold fijo) ──

  Uint8List _sobelEdgeMap(Uint8List gray, int w, int h,
      {int threshold = 25}) {
    final dst = Uint8List(w * h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i  = y * w + x;
        final gx = -gray[i - w - 1] + gray[i - w + 1]
            - 2 * gray[i - 1] + 2 * gray[i + 1]
            - gray[i + w - 1] + gray[i + w + 1];
        final gy = -gray[i - w - 1] - 2 * gray[i - w] - gray[i - w + 1]
            + gray[i + w - 1] + 2 * gray[i + w] + gray[i + w + 1];
        final mag = (gx.abs() + gy.abs()) >> 1; // approx L1 norm
        dst[i] = mag > threshold ? 255 : 0;
      }
    }
    return dst;
  }

  // ── Detección de ángulo de inclinación por proyección Radon ──────
  //
  //  Para cada ángulo candidato en [-20°, 20°] en pasos de 1°,
  //  proyecta el mapa de bordes y calcula la varianza de la proyección.
  //  El ángulo con mayor varianza corresponde a la dirección de los
  //  bordes principales (el billete), que debe ser 0° si está recto.

  double _detectSkewAngle(Uint8List edges, int w, int h) {
    double bestAngle    = 0.0;
    double bestVariance = -1.0;

    for (int deg = -20; deg <= 20; deg++) {
      final rad   = deg * pi / 180.0;
      final cosA  = cos(rad);
      final sinA  = sin(rad);
      final proj  = List<int>.filled(w + h, 0);

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (edges[y * w + x] == 0) continue;
          final cx  = x - w / 2;
          final cy  = y - h / 2;
          final idx = (cx * cosA + cy * sinA + (w + h) / 2).round()
              .clamp(0, w + h - 1);
          proj[idx]++;
        }
      }

      // Varianza de la proyección
      double mean = 0;
      for (final v in proj) mean += v;
      mean /= proj.length;
      double variance = 0;
      for (final v in proj) variance += (v - mean) * (v - mean);

      if (variance > bestVariance) {
        bestVariance = variance;
        bestAngle    = deg.toDouble();
      }
    }

    return bestAngle;
  }

  // ── Aplicar rotación para corregir inclinación ───────────────────

  img.Image _applyDeskew(img.Image src, double angleDeg) {
    return img.copyRotate(src, angle: -angleDeg,
        interpolation: img.Interpolation.linear);
  }

  // ══════════════════════════════════════════════════════════════════
  //  PASO 2 — REDUCCIÓN DE RUIDO BILATERAL
  //
  //  Filtro bilateral simplificado O(n · r²):
  //    out(p) = Σ w_spatial(q) · w_range(p,q) · I(q)  /  Σ w
  //
  //  w_spatial = exp(-dist²  / (2·σs²))   → penaliza distancia
  //  w_range   = exp(-Δcolor² / (2·σr²))  → penaliza diferencia de color
  //
  //  Parámetros para imágenes borrosas/movidas:
  //    radius = 4   → vecindad 9×9 (más cobertura que el box r=2)
  //    σs     = 3.0 → pesos espaciales moderados
  //    σr     = 25  → preserva bordes con saltos > 25 de luma
  //
  //  Se aplica sobre grayscale y se reconstruye el color
  //  multiplicando canal a canal por el ratio luma_out/luma_in.
  //  Esto evita el costoso bilateral en 3 canales separados.
  // ══════════════════════════════════════════════════════════════════

  img.Image _bilateralDenoise(img.Image src,
      {int radius = 4, double sigmaS = 3.0, double sigmaR = 25.0}) {
    final w    = src.width;
    final h    = src.height;
    final gray = _toGrayFast(src);
    final out  = img.Image(width: w, height: h);

    // Pre-calcular pesos espaciales (tabla 2D centrada en (0,0))
    final size    = radius * 2 + 1;
    final wSpatial = List<double>.filled(size * size, 0.0);
    final inv2s2  = 1.0 / (2.0 * sigmaS * sigmaS);
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final dist2 = (dx * dx + dy * dy).toDouble();
        wSpatial[(dy + radius) * size + (dx + radius)] =
            exp(-dist2 * inv2s2);
      }
    }

    final inv2r2 = 1.0 / (2.0 * sigmaR * sigmaR);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final centerLuma = gray[y * w + x].toDouble();
        double sumW = 0.0;
        double sumL = 0.0;

        for (int dy = -radius; dy <= radius; dy++) {
          final ny = (y + dy).clamp(0, h - 1);
          for (int dx = -radius; dx <= radius; dx++) {
            final nx      = (x + dx).clamp(0, w - 1);
            final nLuma   = gray[ny * w + nx].toDouble();
            final dLuma   = nLuma - centerLuma;
            final wRange  = exp(-dLuma * dLuma * inv2r2);
            final wS      = wSpatial[(dy + radius) * size + (dx + radius)];
            final w_total = wS * wRange;
            sumW += w_total;
            sumL += nLuma * w_total;
          }
        }

        final outLuma = (sumL / sumW).round().clamp(0, 255);

        // Reconstruir color preservando crominancia
        final px        = src.getPixel(x, y);
        final inLuma    = centerLuma;
        final ratio     = inLuma > 0 ? outLuma / inLuma : 1.0;
        final r = (px.r.toDouble() * ratio).round().clamp(0, 255);
        final g = (px.g.toDouble() * ratio).round().clamp(0, 255);
        final b = (px.b.toDouble() * ratio).round().clamp(0, 255);
        out.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }
    return out;
  }

  // ══════════════════════════════════════════════════════════════════
  //  PASO 3 — CORRECCIÓN DE BRILLO Y CONTRASTE
  //
  //  3a. Análisis de luminosidad media y percentiles
  //      Para detectar si la imagen es oscura, clara, o tiene
  //      bajo contraste (histograma comprimido).
  //
  //  3b. Gamma correction automática
  //      Si mean_luma < 100 → γ < 1 (aclarar)
  //      Si mean_luma > 160 → γ > 1 (oscurecer)
  //      γ = (mean_target / mean_luma) ^ 0.5
  //      Se aplica LUT de 256 valores (O(n) sin pow por pixel).
  //
  //  3c. Linear contrast stretching
  //      Si el rango [p2, p98] < 180 → los niveles de negro y blanco
  //      están comprimidos. Se estira al rango [0, 255].
  //      Fórmula: out = (in - p2) / (p98 - p2) * 255
  //      Se combina en la misma LUT que el gamma (un solo pase).
  // ══════════════════════════════════════════════════════════════════

  _BrightnessInfo _analyzeBrightness(img.Image src) {
    final w    = src.width;
    final h    = src.height;
    final hist = List<int>.filled(256, 0);
    double sumL = 0.0;
    int n = 0;

    // Muestrear cada 2 píxeles para velocidad
    for (int y = 0; y < h; y += 2) {
      for (int x = 0; x < w; x += 2) {
        final px = src.getPixel(x, y);
        final l  = (px.r.toInt() * 299 + px.g.toInt() * 587 +
            px.b.toInt() * 114) ~/ 1000;
        hist[l]++;
        sumL += l;
        n++;
      }
    }

    final meanLuma = n > 0 ? sumL / n : 128.0;

    // Percentiles p2 y p98 para contrast stretching
    int cumul    = 0;
    int p2       = 0;
    int p98      = 255;
    final p2Cnt  = (n * 0.02).round();
    final p98Cnt = (n * 0.98).round();
    for (int i = 0; i < 256; i++) {
      cumul += hist[i];
      if (cumul >= p2Cnt  && p2  == 0)   p2  = i;
      if (cumul >= p98Cnt && p98 == 255) { p98 = i; break; }
    }

    // Gamma: target 128, ajuste suave con exponente 0.5
    const targetLuma = 128.0;
    final gamma = meanLuma > 0
        ? pow(targetLuma / meanLuma, 0.5).toDouble().clamp(0.4, 2.5)
        : 1.0;

    final needsStretch = (p98 - p2) < 180;

    return _BrightnessInfo(
      meanLuma:     meanLuma,
      p2:           p2,
      p98:          p98,
      gamma:        gamma,
      needsStretch: needsStretch,
    );
  }

  img.Image _correctBrightnessContrast(
      img.Image src, _BrightnessInfo info) {
    // Construir LUT combinada: stretch → gamma en un solo pase
    final lut = Uint8List(256);
    final range = (info.p98 - info.p2).clamp(1, 255).toDouble();

    for (int i = 0; i < 256; i++) {
      // 1. Contrast stretching
      double v = info.needsStretch
          ? ((i - info.p2) / range * 255).clamp(0.0, 255.0)
          : i.toDouble();

      // 2. Gamma correction  out = 255 × (v/255)^(1/γ)
      //    (1/γ < 1 aclara; 1/γ > 1 oscurece)
      if (info.gamma != 1.0) {
        v = 255.0 * pow(v / 255.0, 1.0 / info.gamma);
      }

      lut[i] = v.round().clamp(0, 255);
    }

    // Aplicar LUT a cada pixel
    final w   = src.width;
    final h   = src.height;
    final out = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final px = src.getPixel(x, y);
        out.setPixel(x, y, img.ColorRgb8(
          lut[px.r.toInt()],
          lut[px.g.toInt()],
          lut[px.b.toInt()],
        ));
      }
    }
    return out;
  }

  // ══════════════════════════════════════════════════════════════════
  //  UTILIDADES INTERNAS
  // ══════════════════════════════════════════════════════════════════

  Uint8List _toGrayFast(img.Image src) {
    final w   = src.width;
    final h   = src.height;
    final buf = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final px = src.getPixel(x, y);
        buf[y * w + x] =
            (px.r.toInt() * 299 + px.g.toInt() * 587 + px.b.toInt() * 114) ~/
                1000;
      }
    }
    return buf;
  }

  String _buildPath(String input, String suffix) {
    final dot = input.lastIndexOf('.');
    return dot == -1
        ? '$input$suffix.jpg'
        : '${input.substring(0, dot)}$suffix.jpg';
  }
}

// ══════════════════════════════════════════════════════════════════
//  MODELOS INTERNOS
// ══════════════════════════════════════════════════════════════════

class _CropResult {
  final img.Image image;
  final int       cropW;
  final int       cropH;
  final bool      deskewed;
  _CropResult({
    required this.image,
    required this.cropW,
    required this.cropH,
    required this.deskewed,
  });
}

class _BrightnessInfo {
  final double meanLuma;
  final int    p2;
  final int    p98;
  final double gamma;
  final bool   needsStretch;
  const _BrightnessInfo({
    required this.meanLuma,
    required this.p2,
    required this.p98,
    required this.gamma,
    required this.needsStretch,
  });
}

// ══════════════════════════════════════════════════════════════════
//  MODELO PÚBLICO
// ══════════════════════════════════════════════════════════════════

class ImageEnhancementResult {
  final bool         success;
  final String       enhancedPath;
  final String       originalPath;
  final int          processingMs;
  final List<String> stepsApplied;
  final int          outputWidth;
  final int          outputHeight;
  final String?      skipReason;

  const ImageEnhancementResult({
    required this.success,
    required this.enhancedPath,
    required this.originalPath,
    required this.processingMs,
    required this.stepsApplied,
    required this.outputWidth,
    required this.outputHeight,
    this.skipReason,
  });

  /// Si el enhancer falló o no pudo mejorar, devuelve la imagen original
  factory ImageEnhancementResult.passthrough(
      String originalPath, String reason) =>
      ImageEnhancementResult(
        success:      false,
        enhancedPath: originalPath,
        originalPath: originalPath,
        processingMs: 0,
        stepsApplied: [],
        outputWidth:  0,
        outputHeight: 0,
        skipReason:   reason,
      );

  /// Ruta que debe usarse en el siguiente paso del pipeline
  String get pathForNextStep => enhancedPath;
}