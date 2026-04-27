import 'dart:math';

/// Servicio de coincidencia difusa — versión optimizada
///
/// Mejoras vs versión anterior:
///   • Levenshtein con fila única (O(n) memoria en lugar de O(n²))
///   • Early-exit si la distancia ya supera el umbral
///   • RegExp precompilados en caché — no se recrean en cada llamada
///   • Eliminada la fase de "fragmentos progresivos" (O(n³)) redundante
///     con las fases exacta + Levenshtein
class FuzzyMatcherService {
  // ── Caché de RegExp compilados ──────────────────────────────────
  static final Map<String, RegExp> _regexCache = {};

  static RegExp _wordRegex(String word) =>
      _regexCache.putIfAbsent(word, () => RegExp(r'\b' + word + r'\b'));

  // ══════════════════════════════════════════════════════════════════
  //  LEVENSHTEIN — fila única (O(m) memoria, early-exit)
  // ══════════════════════════════════════════════════════════════════

  /// Distancia de Levenshtein optimizada.
  /// Retorna [maxAllowed + 1] en cuanto supera ese umbral (early-exit).
  static int levenshteinDistance(String s1, String s2,
      {int maxAllowed = 999}) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    // Asegurar que s1 sea la cadena más corta (menor memoria)
    if (s1.length > s2.length) {
      final tmp = s1;
      s1 = s2;
      s2 = tmp;
    }

    final len1 = s1.length;
    final len2 = s2.length;

    // Si la diferencia de longitud ya supera el umbral → imposible
    if ((len2 - len1) > maxAllowed) return maxAllowed + 1;

    // Una sola fila de tamaño len1+1
    var row = List<int>.generate(len1 + 1, (i) => i);

    for (int j = 1; j <= len2; j++) {
      int prev = row[0];
      row[0] = j;
      int rowMin = j; // para early-exit

      for (int i = 1; i <= len1; i++) {
        final temp = row[i];
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        row[i] = [row[i] + 1, row[i - 1] + 1, prev + cost]
            .reduce((a, b) => a < b ? a : b);
        prev = temp;
        if (row[i] < rowMin) rowMin = row[i];
      }

      // Si ningún valor de la fila puede mejorar → cortar
      if (rowMin > maxAllowed) return maxAllowed + 1;
    }

    return row[len1];
  }

  /// Similitud normalizada [0.0 – 1.0]
  static double similarity(String s1, String s2) {
    final maxLen = max(s1.length, s2.length);
    if (maxLen == 0) return 1.0;
    final maxDist = (maxLen * 0.5).ceil(); // early-exit al 50%
    final dist = levenshteinDistance(s1, s2, maxAllowed: maxDist);
    return 1.0 - (dist / maxLen).clamp(0.0, 1.0);
  }

  // ══════════════════════════════════════════════════════════════════
  //  FUZZY CONTAINS — pipeline de 3 fases ordenadas por costo
  // ══════════════════════════════════════════════════════════════════

  /// Busca [keyword] en [text] con tolerancia a errores OCR.
  ///
  /// Fases (de menor a mayor costo):
  ///   1. Exacta    — O(n)
  ///   2. Prefijo   — O(n), cubre OCR truncado desde el inicio
  ///   3. Levenshtein por palabra — O(k·m·n) solo si las anteriores fallan
  static bool fuzzyContains(String text, String keyword,
      {double threshold = 0.75}) {
    if (text.isEmpty || keyword.isEmpty) return false;

    final t = text.toLowerCase();
    final k = keyword.toLowerCase();

    // FASE 1: coincidencia exacta
    if (t.contains(k)) return true;

    // FASE 2: prefijo mínimo (≥4 chars) — cubre "HAMILTO", "REASURY", etc.
    if (k.length >= 4) {
      final prefix = k.substring(0, min(6, k.length));
      if (t.contains(prefix)) return true;
    }

    // FASE 3: Levenshtein sobre palabras individuales
    final tWords =
    t.split(RegExp(r'[\s\W]+')).where((w) => w.length > 2).toList();
    final kWords =
    k.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();

    for (final tw in tWords) {
      for (final kw in kWords) {
        if (similarity(tw, kw) >= threshold) return true;
      }
    }

    return false;
  }

  // ══════════════════════════════════════════════════════════════════
  //  UTILIDADES
  // ══════════════════════════════════════════════════════════════════

  static final RegExp _numbersRegex = RegExp(r'\d+');

  /// Extrae todos los números del texto
  static List<String> extractNumbers(String text) =>
      _numbersRegex.allMatches(text).map((m) => m.group(0)!).toList();

  /// Devuelve la primera denominación reconocida en los números del texto.
  /// Orden de búsqueda: mayor a menor para evitar que "1" matchee "10","100".
  static String? findDenominationNumber(String text) {
    const denoms = ['100', '50', '20', '10', '5', '2', '1'];
    final numbers = extractNumbers(text);
    // Búsqueda exacta primero
    for (final d in denoms) {
      if (numbers.contains(d)) return d;
    }
    // Búsqueda de contención (p.ej. "010" contiene "10")
    for (final num in numbers) {
      for (final d in denoms) {
        if (num.contains(d)) return d;
      }
    }
    return null;
  }

  /// Divide el texto en líneas no vacías
  static List<String> extractLines(String text) =>
      text.split('\n').where((l) => l.trim().isNotEmpty).toList();
}