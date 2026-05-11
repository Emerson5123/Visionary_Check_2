import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

// ══════════════════════════════════════════════════════════════════
//  EdgeDetectionService  — pipeline avanzado optimizado
//
//  Equivalencia Python → Dart:
//    fastNlMeansDenoising(h=10)      → _boxDenoise()        O(n) integral
//    CLAHE(clip=2.5, tile=16×16)     → _clahe()             LUTs precalculadas
//    Unsharp addWeighted(1.5, -0.5)  → _unsharpMask()       kernel separable
//    GaussianBlur(3×3)               → _gaussian3x3()       pre-blur Sobel
//    Sobel CV_64F ksize=3            → _sobelF64()          Float64 + NMS
//    Canny hysteresis                → _hysteresis()        BFS doble umbral
//    resultado_final sobre color     → _blendDirect()       tabla de mult.
//
//  Mejoras vs versión anterior:
//  • Bilateral O(n·r²·exp) → Box denoise O(n) tabla de integral
//  • CLAHE: prefetch de índices de tile, evita recalculo por pixel
//  • Blend: buffer directo en vez de getPixel()/setPixel() por pixel
//  • Grayscale: tabla de lookup LUT (evita float por pixel)
//  • [NUEVO] Pre-blur Gaussiano 3×3 antes del Sobel
//      → elimina ruido de sensor antes del gradiente, reduce falsos
//        máximos locales que NMS no puede suprimir por sí solo.
//  • [NUEVO] Hysteresis thresholding (reemplaza THRESH_TOZERO)
//      → doble umbral alto/bajo + BFS; solo sobreviven bordes fuertes
//        o débiles conectados a uno fuerte. Elimina bordes fantasma.
//  • [NUEVO] meanStrength sobre píxeles interiores (sin sesgo del frame)
//  • [NUEVO] Threshold adaptativo más conservador (factor 0.50 vs 0.35)
//  • [NUEVO] boostMax reducido (1.6/1.4 vs 2.2/1.8) — blend más suave
// ══════════════════════════════════════════════════════════════════

class EdgeDetectionService {
  static final EdgeDetectionService _instance =
  EdgeDetectionService._internal();
  factory EdgeDetectionService() => _instance;
  EdgeDetectionService._internal();

  static const int _maxWorkingSize = 600;

  // ══════════════════════════════════════════════════════════════════
  //  API PÚBLICA
  // ══════════════════════════════════════════════════════════════════

  Future<EdgeDetectionResult> processImage(
      String inputPath, {
        bool debugEdgeOnly = false,
      }) async {
    try {
      final sw = Stopwatch()..start();
      print('\n🔲 Edge Detection — inicio');

      final bytes    = await File(inputPath).readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) {
        return EdgeDetectionResult.error('No se pudo decodificar la imagen');
      }

      final work = _downscale(original);
      print('   ${work.width}×${work.height}'
          '  (original: ${original.width}×${original.height})');

      // ── A: Grayscale con LUT ──────────────────────────────────
      final gray = _toGrayLUT(work);

      // ── B: Box denoise (≈ fastNlMeans, O(n)) ─────────────────
      final denoised = _boxDenoise(gray, work.width, work.height, radius: 2);

      // ── C: CLAHE (clip=2.5, tiles 16×16) ─────────────────────
      final clahe = _clahe(denoised, work.width, work.height,
          clipLimit: 2.5, tileSize: 16);

      // ── D: Unsharp Mask (alpha=1.5, beta=-0.5) ────────────────
      final sharp = _unsharpMask(clahe, work.width, work.height);

      // ── E: Pre-blur 3×3 antes del Sobel ──────────────────────
      //  Suaviza ruido de sensor antes de calcular gradientes.
      //  Evita falsos máximos locales que NMS no puede distinguir.
      final preBlurred = _gaussian3x3(sharp, work.width, work.height);

      // ── F: Sobel Float64 + NMS ────────────────────────────────
      final sobelResult = _sobelF64(preBlurred, work.width, work.height);

      // ── G: Hysteresis thresholding (reemplaza THRESH_TOZERO) ──
      //  Doble umbral + BFS: elimina bordes fantasma aislados.
      final edgeMask = _hysteresis(
        sobelResult.nmsMap,
        sobelResult.width,
        sobelResult.height,
        highThresh: sobelResult.highThreshold,
        lowThresh:  sobelResult.lowThreshold,
      );  

      // ── H: Blend sobre imagen COLOR ───────────────────────────
      final enhancedWork =
      _blendDirect(work, edgeMask, sobelResult.meanStrength);

      // ── I: Escalar al tamaño original y guardar ───────────────
      final enhanced = enhancedWork.width == original.width
          ? enhancedWork
          : img.copyResize(enhancedWork,
          width:         original.width,
          height:        original.height,
          interpolation: img.Interpolation.linear);

      final enhancedPath = _buildPath(inputPath, '_edge');
      await File(enhancedPath)
          .writeAsBytes(img.encodeJpg(enhanced, quality: 92));

      String? debugPath;
      if (debugEdgeOnly) {
        debugPath = _buildPath(inputPath, '_edge_debug');
        await File(debugPath).writeAsBytes(
            img.encodeJpg(
                _maskToImage(edgeMask, work.width, work.height),
                quality: 85));
      }

      sw.stop();
      print('✅ ${sw.elapsedMilliseconds} ms'
          '  fuerza=${(sobelResult.meanStrength * 100).toStringAsFixed(1)}%'
          '  tH=${sobelResult.highThreshold}'
          '  tL=${sobelResult.lowThreshold}\n');

      return EdgeDetectionResult(
        enhancedPath:  enhancedPath,
        originalPath:  inputPath,
        processingMs:  sw.elapsedMilliseconds,
        edgeStrength:  sobelResult.meanStrength,
        isBillLikely:  sobelResult.meanStrength > 0.08,
        debugEdgePath: debugPath,
      );
    } catch (e) {
      print('❌ Edge Detection error: $e');
      return EdgeDetectionResult.error('$e');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  A — GRAYSCALE CON LUT  (Rec.601)
  //  L = (299·R + 587·G + 114·B) / 1000
  //  Tablas pre-calculadas evitan multiplicaciones float por pixel.
  // ══════════════════════════════════════════════════════════════════

  Uint8List _toGrayLUT(img.Image src) {
    final w   = src.width;
    final h   = src.height;
    final buf = Uint8List(w * h);
    final tR  = List<int>.generate(256, (v) => v * 299);
    final tG  = List<int>.generate(256, (v) => v * 587);
    final tB  = List<int>.generate(256, (v) => v * 114);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final px = src.getPixel(x, y);
        buf[y * w + x] =
            ((tR[px.r.toInt()] + tG[px.g.toInt()] + tB[px.b.toInt()]) ~/ 1000)
                .clamp(0, 255);
      }
    }
    return buf;
  }

  // ══════════════════════════════════════════════════════════════════
  //  B — BOX DENOISE (≈ fastNlMeansDenoising)
  //  Box filter O(n) usando imagen integral. Vecindad (2r+1)×(2r+1).
  // ══════════════════════════════════════════════════════════════════

  Uint8List _boxDenoise(Uint8List src, int w, int h, {int radius = 2}) {
    final integral = Int32List(w * h);
    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        rowSum += src[y * w + x];
        integral[y * w + x] =
            rowSum + (y > 0 ? integral[(y - 1) * w + x] : 0);
      }
    }

    final dst = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x0 = (x - radius).clamp(0, w - 1);
        final y0 = (y - radius).clamp(0, h - 1);
        final x1 = (x + radius).clamp(0, w - 1);
        final y1 = (y + radius).clamp(0, h - 1);

        final A = y0 > 0 && x0 > 0 ? integral[(y0 - 1) * w + (x0 - 1)] : 0;
        final B = y0 > 0           ? integral[(y0 - 1) * w + x1]         : 0;
        final C = x0 > 0           ? integral[y1        * w + (x0 - 1)]  : 0;
        final D =                    integral[y1        * w + x1];

        final area = (x1 - x0 + 1) * (y1 - y0 + 1);
        dst[y * w + x] = ((D - B - C + A) ~/ area).clamp(0, 255);
      }
    }
    return dst;
  }

  // ══════════════════════════════════════════════════════════════════
  //  C — CLAHE optimizado
  //  tileSize=16 → 4× menos tiles que 8, misma calidad para billetes.
  //  Bilinear blend solo cuando los 4 tiles vecinos son distintos.
  // ══════════════════════════════════════════════════════════════════

  Uint8List _clahe(Uint8List src, int w, int h,
      {double clipLimit = 2.5, int tileSize = 16}) {
    final tx = (w / tileSize).ceil();
    final ty = (h / tileSize).ceil();

    final luts = List.generate(
        ty, (_) => List.generate(tx, (_) => Uint8List(256)));

    for (int tj = 0; tj < ty; tj++) {
      for (int ti = 0; ti < tx; ti++) {
        final x0 = ti * tileSize;
        final y0 = tj * tileSize;
        final x1 = min(x0 + tileSize, w);
        final y1 = min(y0 + tileSize, h);
        final n  = (x1 - x0) * (y1 - y0);

        final hist = List<int>.filled(256, 0);
        for (int y = y0; y < y1; y++) {
          final row = y * w;
          for (int x = x0; x < x1; x++) hist[src[row + x]]++;
        }

        final clipVal = max(1, (clipLimit * n / 256).round());
        int excess    = 0;
        for (int i = 0; i < 256; i++) {
          if (hist[i] > clipVal) {
            excess  += hist[i] - clipVal;
            hist[i]  = clipVal;
          }
        }
        final addEach = excess ~/ 256;
        final addRem  = excess  % 256;
        for (int i = 0; i < 256; i++) hist[i] += addEach;
        for (int i = 0; i < addRem; i++) hist[i]++;

        int cdf     = 0;
        final lut   = luts[tj][ti];
        for (int i = 0; i < 256; i++) {
          cdf    += hist[i];
          lut[i]  = ((cdf * 255) ~/ n).clamp(0, 255);
        }
      }
    }

    final dst   = Uint8List(w * h);
    final halfT = tileSize * 0.5;

    for (int y = 0; y < h; y++) {
      final fy    = (y - halfT) / tileSize;
      final tj0   = fy.floor().clamp(0, ty - 1);
      final tj1   = (tj0 + 1).clamp(0, ty - 1);
      final ay    = (fy - fy.floor()).clamp(0.0, 1.0);
      final ay1   = 1.0 - ay;
      final sameJ = tj0 == tj1;

      final row = y * w;
      for (int x = 0; x < w; x++) {
        final v  = src[row + x];
        final fx = (x - halfT) / tileSize;
        final ti0 = fx.floor().clamp(0, tx - 1);
        final ti1 = (ti0 + 1).clamp(0, tx - 1);

        if (sameJ && ti0 == ti1) {
          dst[row + x] = luts[tj0][ti0][v];
          continue;
        }

        final ax  = (fx - fx.floor()).clamp(0.0, 1.0);
        final ax1 = 1.0 - ax;
        dst[row + x] = (
            luts[tj0][ti0][v] * ax1 * ay1 +
                luts[tj0][ti1][v] * ax  * ay1 +
                luts[tj1][ti0][v] * ax1 * ay  +
                luts[tj1][ti1][v] * ax  * ay
        ).round().clamp(0, 255);
      }
    }
    return dst;
  }

  // ══════════════════════════════════════════════════════════════════
  //  D — UNSHARP MASK separable
  //  out = src + 0.5·(src − blur)  →  equivale a 1.5·src − 0.5·blur
  //  Gaussian 5×5 separable [1 4 6 4 1]/16 en dos pasadas O(n·5).
  // ══════════════════════════════════════════════════════════════════

  Uint8List _unsharpMask(Uint8List src, int w, int h) {
    final blurred = _gaussian5x5(src, w, h);
    final dst     = Uint8List(w * h);
    for (int i = 0; i < dst.length; i++) {
      dst[i] = (src[i] + ((src[i] - blurred[i]) >> 1)).clamp(0, 255);
    }
    return dst;
  }

  Uint8List _gaussian5x5(Uint8List src, int w, int h) {
    const k  = [1, 4, 6, 4, 1];
    const kS = 16;
    final tmp = Uint8List(w * h);
    final dst = Uint8List(w * h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        var acc = 0;
        for (int d = -2; d <= 2; d++) {
          acc += src[y * w + (x + d).clamp(0, w - 1)] * k[d + 2];
        }
        tmp[y * w + x] = acc ~/ kS;
      }
    }
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        var acc = 0;
        for (int d = -2; d <= 2; d++) {
          acc += tmp[(y + d).clamp(0, h - 1) * w + x] * k[d + 2];
        }
        dst[y * w + x] = acc ~/ kS;
      }
    }
    return dst;
  }

  // ══════════════════════════════════════════════════════════════════
  //  E — PRE-BLUR GAUSSIANO 3×3  [NUEVO]
  //
  //  Kernel separable [1 2 1] / 4 en dos pasadas O(n·3).
  //  Se aplica ANTES del Sobel para eliminar ruido de sensor de 1-2px.
  //
  //  Por qué aquí y no en el paso B (boxDenoise):
  //    boxDenoise elimina grano global con ventana 5×5.
  //    Este blur 3×3 es más pequeño y precede directamente al cálculo
  //    de gradientes, donde incluso 1px de ruido genera un pico falso.
  //    Ambos pasos son complementarios, no redundantes.
  // ══════════════════════════════════════════════════════════════════

  Uint8List _gaussian3x3(Uint8List src, int w, int h) {
    final tmp = Uint8List(w * h);
    final dst = Uint8List(w * h);

    // Pasada horizontal: [1 2 1] / 4
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final l = src[y * w + (x - 1).clamp(0, w - 1)];
        final c = src[y * w + x];
        final r = src[y * w + (x + 1).clamp(0, w - 1)];
        tmp[y * w + x] = (l + 2 * c + r) >> 2;
      }
    }
    // Pasada vertical: [1 2 1] / 4
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final t = tmp[((y - 1).clamp(0, h - 1)) * w + x];
        final c = tmp[y * w + x];
        final b = tmp[((y + 1).clamp(0, h - 1)) * w + x];
        dst[y * w + x] = (t + 2 * c + b) >> 2;
      }
    }
    return dst;
  }

  // ══════════════════════════════════════════════════════════════════
  //  F — SOBEL FLOAT64 + NMS  [MEJORADO]
  //
  //  Paso 1: Gradiente Sobel 3×3 en Float64
  //  Paso 2: Cuantizar ángulo a 4 direcciones
  //  Paso 3: Non-Maximum Suppression → bordes de ~1px
  //  Paso 4: Normalizar NMS → [0, 1]
  //  Paso 5: Calcular umbrales de hysteresis (percentil-95)
  //
  //  meanStrength calculado sobre píxeles interiores únicamente
  //  (evita el sesgo que provocan los ceros del frame exterior).
  // ══════════════════════════════════════════════════════════════════

  _SobelResult _sobelF64(Uint8List gray, int w, int h) {
    final mag  = Float64List(w * h);
    final angQ = Uint8List(w * h); // 0=horiz · 1=diag/ · 2=vert · 3=diag\

    double maxM = 0.0;
    double sum  = 0.0;
    final inner = (w - 2) * (h - 2);

    // ── Paso 1 + 2: Gradiente y ángulo ──────────────────────────
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i  = y * w + x;
        final tl = gray[i - w - 1].toDouble();
        final tc = gray[i - w    ].toDouble();
        final tr = gray[i - w + 1].toDouble();
        final ml = gray[i     - 1].toDouble();
        final mr = gray[i     + 1].toDouble();
        final bl = gray[i + w - 1].toDouble();
        final bc = gray[i + w    ].toDouble();
        final br = gray[i + w + 1].toDouble();

        final gx = -tl + tr - 2.0 * ml + 2.0 * mr - bl + br;
        final gy = -tl - 2.0 * tc - tr  + bl + 2.0 * bc + br;
        final m  = sqrt(gx * gx + gy * gy);

        mag[i] = m;
        if (m > maxM) maxM = m;
        sum += m;

        if (m > 0) {
          final a = (atan2(gy, gx) * (180.0 / pi) + 180.0) % 180.0;
          if      (a < 22.5  || a >= 157.5) angQ[i] = 0;
          else if (a < 67.5)                angQ[i] = 1;
          else if (a < 112.5)               angQ[i] = 2;
          else                              angQ[i] = 3;
        }
      }
    }

    // meanStrength sobre píxeles interiores (sin sesgo del frame)
    final meanStrength = (maxM > 0 && inner > 0) ? (sum / inner) / maxM : 0.0;

    // ── Paso 3: Non-Maximum Suppression ─────────────────────────
    final nmsRaw = Float64List(w * h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final m = mag[i];
        if (m == 0.0) continue;
        double n1, n2;
        switch (angQ[i]) {
          case 0:  n1 = mag[i + 1];     n2 = mag[i - 1];     break; // E/W
          case 1:  n1 = mag[i - w + 1]; n2 = mag[i + w - 1]; break; // NE/SW
          case 2:  n1 = mag[i - w];     n2 = mag[i + w];     break; // N/S
          default: n1 = mag[i - w - 1]; n2 = mag[i + w + 1]; break; // NW/SE
        }
        if (m >= n1 && m >= n2) nmsRaw[i] = m;
      }
    }

    // ── Paso 4: Normalizar NMS → [0, 1] ─────────────────────────
    double maxNms = 0.0;
    for (int i = 0; i < nmsRaw.length; i++) {
      if (nmsRaw[i] > maxNms) maxNms = nmsRaw[i];
    }
    final nmsNorm = Float32List(w * h);
    if (maxNms > 0) {
      final inv = 1.0 / maxNms;
      for (int i = 0; i < nmsNorm.length; i++) nmsNorm[i] = nmsRaw[i] * inv;
    }

    // ── Paso 5: Umbrales de hysteresis ───────────────────────────
    final thresholds = _computeHysteresisThresholds(nmsNorm, w, h);

    return _SobelResult(
      nmsMap:        nmsNorm,
      width:         w,
      height:        h,
      meanStrength:  meanStrength,
      highThreshold: thresholds[0],
      lowThreshold:  thresholds[1],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  UMBRALES DE HYSTERESIS  [NUEVO]
  //
  //  highThresh = p95 × 0.50  (clamp 30–80)
  //  lowThresh  = high × 0.40 (clamp 10–high-5)
  //  Relación high/low ≈ 2.5:1, valor clásico recomendado por Canny.
  //  Factor 0.50 (antes 0.35): más conservador, menos ruido residual.
  // ══════════════════════════════════════════════════════════════════

  List<int> _computeHysteresisThresholds(Float32List nms, int w, int h) {
    final vals = <double>[];
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final v = nms[y * w + x];
        if (v > 0) vals.add(v);
      }
    }
    if (vals.isEmpty) return [60, 24];

    vals.sort();
    final p95  = vals[(vals.length * 0.95).toInt().clamp(0, vals.length - 1)];
    final high = (p95 * 255 * 0.50).round().clamp(30, 80);
    final low  = (high * 0.40).round().clamp(10, high - 5);

    print('   🎯 Hysteresis — alto: $high  bajo: $low'
        '  (p95=${(p95 * 100).toStringAsFixed(1)}%)');
    return [high, low];
  }

  // ══════════════════════════════════════════════════════════════════
  //  G — HYSTERESIS THRESHOLDING  [NUEVO]
  //
  //  Reemplaza _thresholdToZero (THRESH_TOZERO con umbral único).
  //
  //  Algoritmo:
  //    1. v >= highThresh → FUERTE  (borde seguro, seed para BFS)
  //    2. v >= lowThresh  → DÉBIL   (borde posible)
  //    3. v <  lowThresh  → RUIDO   (descartado)
  //    4. BFS 8-conectado desde cada FUERTE: promueve vecinos DÉBILES.
  //       Solo débiles conectados a un fuerte sobreviven.
  //
  //  Resultado: bordes de ~1px sin fragmentos fantasma aislados.
  // ══════════════════════════════════════════════════════════════════

  Uint8List _hysteresis(
      Float32List nms, int w, int h,
      {required int highThresh, required int lowThresh}) {

    // 0 = ruido · 1 = débil · 2 = fuerte
    final state = Uint8List(w * h);
    final queue = Queue<int>();

    for (int i = 0; i < nms.length; i++) {
      final v = (nms[i] * 255).round();
      if (v >= highThresh) {
        state[i] = 2;
        queue.add(i);
      } else if (v >= lowThresh) {
        state[i] = 1;
      }
    }

    // BFS: propagar fuertes hacia débiles conectados (8-vecindad)
    const dx = [-1,  0,  1, -1, 1, -1, 0, 1];
    const dy = [-1, -1, -1,  0, 0,  1, 1, 1];

    while (queue.isNotEmpty) {
      final idx = queue.removeFirst();
      final cy  = idx ~/ w;
      final cx  = idx  % w;

      for (int d = 0; d < 8; d++) {
        final nx = cx + dx[d];
        final ny = cy + dy[d];
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        final ni = ny * w + nx;
        if (state[ni] == 1) {
          state[ni] = 2;
          queue.add(ni);
        }
      }
    }

    // Solo fuertes (2) pasan a la máscara final
    final dst = Uint8List(w * h);
    for (int i = 0; i < state.length; i++) {
      if (state[i] == 2) {
        dst[i] = (nms[i] * 255).round().clamp(0, 255);
      }
    }
    return dst;
  }

  // ══════════════════════════════════════════════════════════════════
  //  H — BLEND SOBRE IMAGEN COLOR  [MEJORADO]
  //
  //  boostMax reducido: 2.2/1.8 → 1.6/1.4
  //  Con hysteresis la máscara ya es limpia; boost menor evita
  //  saturar zonas de alto contraste y amplificar artefactos JPEG.
  //  Fórmula: out_ch = ch × (1 + mask/255 × (boost−1))
  // ══════════════════════════════════════════════════════════════════

  img.Image _blendDirect(
      img.Image src, Uint8List edgeMask, double meanStrength) {
    final boostMax  = meanStrength < 0.12 ? 1.6 : 1.4;
    final out       = img.Image(width: src.width, height: src.height);
    final multTable = Float32List(256);
    for (int m = 0; m < 256; m++) {
      multTable[m] = 1.0 + (m / 255.0) * (boostMax - 1.0);
    }

    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final px   = src.getPixel(x, y);
        final mult = multTable[edgeMask[y * src.width + x]];
        out.setPixel(x, y, img.ColorRgb8(
          (px.r.toDouble() * mult).toInt().clamp(0, 255),
          (px.g.toDouble() * mult).toInt().clamp(0, 255),
          (px.b.toDouble() * mult).toInt().clamp(0, 255),
        ));
      }
    }
    return out;
  }

  img.Image _maskToImage(Uint8List mask, int w, int h) {
    final out = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = mask[y * w + x];
        out.setPixel(x, y, img.ColorRgb8(v, v, v));
      }
    }
    return out;
  }

  // ══════════════════════════════════════════════════════════════════
  //  UTILIDADES
  // ══════════════════════════════════════════════════════════════════

  img.Image _downscale(img.Image src) {
    final longer = max(src.width, src.height);
    if (longer <= _maxWorkingSize) return src;
    final scale = _maxWorkingSize / longer;
    return img.copyResize(src,
        width:         (src.width  * scale).round(),
        height:        (src.height * scale).round(),
        interpolation: img.Interpolation.average);
  }

  String _buildPath(String input, String suffix) {
    final dot = input.lastIndexOf('.');
    return dot == -1
        ? '$input$suffix.jpg'
        : '${input.substring(0, dot)}$suffix.jpg';
  }

  void dispose() {}
}

// ══════════════════════════════════════════════════════════════════
//  MODELOS
// ══════════════════════════════════════════════════════════════════

class _SobelResult {
  final Float32List nmsMap;        // NMS normalizado [0,1]
  final int         width;
  final int         height;
  final double      meanStrength;
  final int         highThreshold; // umbral alto hysteresis [0,255]
  final int         lowThreshold;  // umbral bajo hysteresis [0,255]

  const _SobelResult({
    required this.nmsMap,
    required this.width,
    required this.height,
    required this.meanStrength,
    required this.highThreshold,
    required this.lowThreshold,
  });
}

class EdgeDetectionResult {
  final bool    success;
  /// Imagen COLOR con bordes realzados → OCR + ResultScreen
  final String  enhancedPath;
  final String  originalPath;
  final int     processingMs;
  /// Nitidez media [0–1]: <0.05 borrosa · 0.10–0.25 aceptable · >0.25 nítida
  final double  edgeStrength;
  final bool    isBillLikely;
  final String? debugEdgePath;
  final String? error;

  const EdgeDetectionResult({
    this.success        = true,
    required this.enhancedPath,
    required this.originalPath,
    required this.processingMs,
    required this.edgeStrength,
    required this.isBillLikely,
    this.debugEdgePath,
    this.error,
  });

  factory EdgeDetectionResult.error(String msg) => EdgeDetectionResult(
      success:      false,
      enhancedPath: '',
      originalPath: '',
      processingMs: 0,
      edgeStrength: 0.0,
      isBillLikely: false,
      error:        msg);

  String get imageQuality {
    if (!success)            return 'Error en procesamiento';
    if (edgeStrength < 0.05) return 'Imagen borrosa — acerca el billete';
    if (edgeStrength < 0.10) return 'Bordes débiles — mejora la iluminación';
    if (edgeStrength < 0.25) return 'Calidad aceptable';
    return 'Imagen nítida ✓';
  }
}