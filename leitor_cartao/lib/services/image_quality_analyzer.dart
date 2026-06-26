// image_quality_analyzer.dart
// Serviço para análise de qualidade de imagem em tempo real durante captura
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

// ── Geometria da grade v3 (espelha questions/pdf_generator.py e
// frame_guide_painter.dart — MANTER SINCRONIZADO entre os 3 arquivos). ──────────
// Duplicada aqui (e não importada do painter) porque este arquivo roda em
// isolate e o painter depende de Flutter Material (não disponível em isolate).
const double _kLarguraNecessariaMm = 36.2;
const double _kLarguraIndiceMm = 8.0;
const double _kEspacoColunasMm = 18.0;
const double _kEspacoQuestoesMm = 7.0;
const double _kMargemInternaMm = 4.0;
const double _kFiducialPaddingMm = 8.0;

/// Divisão de questões por coluna (espelha split_colunas do backend).
List<int> _questoesPorColuna(int n) {
  final ncol = n <= 23 ? 1 : 2;
  if (ncol == 1) return [n];
  if (n % 2 == 0) return [n ~/ 2, n ~/ 2];
  return [n ~/ 2 + 1, n ~/ 2];
}

/// Razão (≤1) esperada do retângulo dos 4 fiduciais para um cartão com
/// [numQuestoes] e versão de layout [cartaoVersao].
/// v3 (cartaoVersao==3): fiduciais ao redor da grade → razão da grade.
/// v2/legado (null): fiduciais nos cantos da folha A4 → 186/273 = 0.681.
/// Retorna null quando não há razão específica (usa fallback 0.681 com
/// tolerância larga para aceitar tanto v2 quanto v3 com 1 coluna).
double _razaoFiduciaisEsperada(int numQuestoes, int? cartaoVersao) {
  if (cartaoVersao != 3) return 0.681; // v2 legado
  final qpc = _questoesPorColuna(numQuestoes);
  final ncol = qpc.length;
  final larguraTotal = _kLarguraNecessariaMm * ncol +
      _kEspacoColunasMm * (ncol - 1) +
      _kLarguraIndiceMm * ncol;
  final alturaBloco =
      qpc.reduce(max) * _kEspacoQuestoesMm + 2 * _kMargemInternaMm;
  final wMm = larguraTotal + 2 * _kFiducialPaddingMm;
  final hMm = alturaBloco + 2 * _kFiducialPaddingMm;
  return min(wMm, hMm) / max(wMm, hMm);
}

/// Resultado da detecção dos 4 fiduciais (círculos pretos da borda do cartão).
/// É o gatilho ideal do auto-disparo: só captura quando o cartão está bem
/// enquadrado (4 fiduciais formando o retângulo A4 na distância certa).
class FiducialResult {
  final bool ok;          // 4 fiduciais formando um retângulo A4 válido (pré-filtro)
  final int blobs;        // nº de blobs escuros candidatos (para calibração via log)
  // 4 centros dos fiduciais NORMALIZADOS no buffer (0-1), na ordem TL,TR,BL,BR:
  // [TLx,TLy, TRx,TRy, BLx,BLy, BRx,BRy]. Vazio se ok=false.
  final List<double> pontos;

  const FiducialResult({
    required this.ok,
    required this.blobs,
    required this.pontos,
  });
}

/// Estado de qualidade ao vivo para feedback em tempo real
enum LiveQualityState { analyzing, excellent, good, warning, bad }

/// Métricas brutas da análise ao vivo da moldura (para logs/ajuste fino).
/// Permite ver POR QUE a moldura ficou verde/amarela/vermelha.
class LiveFrameMetrics {
  final LiveQualityState state;
  final double brightness;     // 0-255 (canal Y), ideal 150-220
  final double illumination;   // 0-1, uniformidade entre quadrantes (>0.75 ideal)
  final bool hasPaper;         // papel branco detectado na região central da moldura
  final int cornersFound;      // 0-4 fiduciais escuros detectados nos cantos do cartão
  final double coberturaPapel; // 0-1, fração do frame ocupada por papel (proxy de distância)
  final bool fiduciaisOk;      // 4 fiduciais formando um retângulo A4 válido (pré-filtro)
  final int blobsEscuros;      // nº de blobs escuros candidatos (para calibração via log)
  final List<double> fiduciaisPontos; // 4 centros normalizados no buffer (TL,TR,BL,BR), vazio se !ok

  const LiveFrameMetrics({
    required this.state,
    required this.brightness,
    required this.illumination,
    required this.hasPaper,
    required this.cornersFound,
    required this.coberturaPapel,
    required this.fiduciaisOk,
    required this.blobsEscuros,
    this.fiduciaisPontos = const [],
  });

  @override
  String toString() =>
      'brilho=${brightness.toStringAsFixed(0)} '
      'luz_uniforme=${illumination.toStringAsFixed(2)} '
      'papel=${hasPaper ? "sim" : "nao"} '
      'cobertura=${coberturaPapel.toStringAsFixed(2)} '
      'fiduciais=${fiduciaisOk ? "OK" : "nao"}(blobs=$blobsEscuros) '
      '=> ${state.name}';
}

/// Resultado da análise de qualidade
class ImageQualityResult {
  final double brightness;      // 0-255, ideal: 150-220
  final double contrast;        // 0-255, ideal: > 40
  final double sharpness;       // 0-1, ideal: > 0.7
  final double illuminationUniformity; // 0-1, ideal: > 0.7
  final double cornerVisibility; // 0-1, ideal: 1.0
  final double overallScore;    // 0-100, ideal: > 60
  final String recommendation;  // Dica do que melhorar

  // Flags de qualidade
  bool get isBrightnessBad => brightness < 100 || brightness > 240;
  bool get isContrastBad => contrast < 30;
  bool get isSharpnessBad => sharpness < 0.5;
  bool get isIlluminationBad => illuminationUniformity < 0.6;
  bool get isCornersNotVisible => cornerVisibility < 0.5;

  // Score simples para feedback rápido
  bool get isAcceptable => overallScore >= 60;
  bool get isGood => overallScore >= 75;
  bool get isExcellent => overallScore >= 85;

  ImageQualityResult({
    required this.brightness,
    required this.contrast,
    required this.sharpness,
    required this.illuminationUniformity,
    required this.cornerVisibility,
    required this.overallScore,
    required this.recommendation,
  });
}

/// Analisador de qualidade de imagem
/// Funciona de forma assíncrona para não bloquear a UI
class ImageQualityAnalyzer {
  /// Analisar qualidade de uma imagem capturada
  static Future<ImageQualityResult> analyzeImage(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        return _createFailedResult();
      }

      return analyzeImageData(image);
    } catch (e) {
      print('❌ Erro ao analisar qualidade: $e');
      return _createFailedResult();
    }
  }

  /// Analisar dados de imagem já decodificados
  static ImageQualityResult analyzeImageData(img.Image image) {
    final brightness = _calculateBrightness(image);
    final contrast = _calculateContrast(image);
    final sharpness = _calculateSharpness(image);
    final illumination = _calculateIlluminationUniformity(image);
    final corners = _estimateCornerVisibility(image);

    // Calcular score overall (0-100)
    double overallScore = 50; // baseline

    // Brightness: -20 se ruim, +20 se bom
    if (brightness >= 120 && brightness <= 230) {
      overallScore += 20;
    } else if (brightness < 80 || brightness > 250) {
      overallScore -= 20;
    } else {
      overallScore += 10;
    }

    // Contrast: -15 se ruim, +25 se bom
    if (contrast > 40) {
      overallScore += 25;
    } else if (contrast < 25) {
      overallScore -= 15;
    } else {
      overallScore += 10;
    }

    // Sharpness: -15 se ruim, +20 se bom
    if (sharpness > 0.7) {
      overallScore += 20;
    } else if (sharpness < 0.4) {
      overallScore -= 15;
    } else {
      overallScore += 10;
    }

    // Illumination: -15 se ruim, +15 se bom
    if (illumination > 0.75) {
      overallScore += 15;
    } else if (illumination < 0.55) {
      overallScore -= 15;
    } else {
      overallScore += 5;
    }

    // Corners: -10 se não visível
    if (corners < 0.5) {
      overallScore -= 10;
    } else if (corners > 0.8) {
      overallScore += 5;
    }

    overallScore = overallScore.clamp(0, 100);

    // Gerar recomendação
    final recommendation = _generateRecommendation(
      brightness: brightness,
      contrast: contrast,
      sharpness: sharpness,
      illumination: illumination,
      corners: corners,
    );

    return ImageQualityResult(
      brightness: brightness,
      contrast: contrast,
      sharpness: sharpness,
      illuminationUniformity: illumination,
      cornerVisibility: corners,
      overallScore: overallScore,
      recommendation: recommendation,
    );
  }

  /// Análise rápida para feedback ao vivo (apenas brightness + illumination)
  /// Recebe bytes brutos (canal Y de YUV420) para análise rápida sem decodificação
  static Future<LiveQualityState> analyzeLiveFrameFast(
    List<int> lumaBytes,
    int width,
    int height,
  ) async {
    return analyzeLiveFrameFastMetrics(lumaBytes, width, height).state;
  }

  /// Versão detalhada: retorna as métricas brutas além do estado, para logs/ajuste.
  /// É a fonte única da decisão da moldura (analyzeLiveFrameFast delega aqui).
  ///
  /// [numQuestoes]/[cartaoVersao]: definem a razão esperada do retângulo dos
  /// fiduciais (v3 = grade apertada; v2/legado = A4-corner 0.681). Se omitted,
  /// usa o fallback v2 (compatível com cartões antigos).
  static LiveFrameMetrics analyzeLiveFrameFastMetrics(
    List<int> lumaBytes,
    int width,
    int height, {
    int numQuestoes = 0,
    int? cartaoVersao,
  }) {
    try {
      if (lumaBytes.isEmpty) {
        return const LiveFrameMetrics(
          state: LiveQualityState.analyzing,
          brightness: 0,
          illumination: 0,
          hasPaper: false,
          cornersFound: 0,
          coberturaPapel: 0,
          fiduciaisOk: false,
          blobsEscuros: 0,
        );
      }

      // Calcular brilho médio (amostragem rápida)
      final double brightness =
          _calculateBrightnessFromBytes(lumaBytes, width, height);

      // Calcular uniformidade de iluminação (amostragem rápida)
      final double illumination =
          _calculateIlluminationFromBytes(lumaBytes, width, height);

      // Verificar se há papel branco na área central da moldura
      final bool hasPaper = _hasPaperInFrameRegion(lumaBytes, width, height);

      // Contagem dos 4 fiduciais — APENAS diagnóstico/log.
      // A detecção ao vivo no buffer da câmera mostrou-se pouco confiável para
      // travar a captura (buffer em paisagem + cartão em retrato), e o leitor
      // geométrico do servidor reancora pelos fiduciais mesmo com enquadramento
      // "warning". Por isso NÃO entra na decisão de readiness.
      final int corners = _detectCornerFiducials(lumaBytes, width, height);

      // Cobertura de papel no frame inteiro = proxy de DISTÂNCIA.
      final double cobertura = _brightFraction(lumaBytes, 150);

      // Detecção dos 4 fiduciais (círculos pretos da borda) — gatilho ideal.
      // A razão esperada do retângulo depende da versão do cartão (v3 = grade
      // apertada; v2 = A4-corner). Sem isso, a v3 com 1 coluna (razão ~0.77)
      // é rejeitada pelo filtro que esperava 0.681.
      final FiducialResult fid = _detectarFiduciais(
        lumaBytes, width, height,
        numQuestoes: numQuestoes,
        cartaoVersao: cartaoVersao,
      );

      LiveQualityState state;
      if (brightness < 100) {
        state = LiveQualityState.bad; // Muito escuro
      } else if (brightness > 240) {
        state = LiveQualityState.bad; // Muito claro
      } else if (illumination < 0.55) {
        state = LiveQualityState.warning; // Sombra detectada
      } else if (fid.ok) {
        // Cartão bem enquadrado (4 fiduciais na posição certa) + luz boa = ideal.
        state = LiveQualityState.excellent;
      } else if (hasPaper) {
        state = LiveQualityState.good; // tem papel, mas fiduciais ainda não alinhados
      } else {
        state = LiveQualityState.warning; // sem cartão na moldura
      }

      return LiveFrameMetrics(
        state: state,
        brightness: brightness,
        illumination: illumination,
        hasPaper: hasPaper,
        cornersFound: corners,
        coberturaPapel: cobertura,
        fiduciaisOk: fid.ok,
        blobsEscuros: fid.blobs,
        fiduciaisPontos: fid.pontos,
      );
    } catch (e) {
      print('❌ Erro na análise rápida: $e');
      return const LiveFrameMetrics(
        state: LiveQualityState.analyzing,
        brightness: 0,
        illumination: 0,
        hasPaper: false,
        cornersFound: 0,
        coberturaPapel: 0,
        fiduciaisOk: false,
        blobsEscuros: 0,
      );
    }
  }

  /// Detecta os 4 fiduciais (círculos pretos sólidos da borda) no frame ao vivo.
  ///
  /// É ORIENTAÇÃO-AGNÓSTICO: acha todos os blobs escuros sólidos e verifica se 4
  /// deles formam um retângulo com a proporção esperada do cartão (v3 = razão da
  /// grade por numQuestoes; v2 = 186x273mm → 0.681), grande o bastante (distância
  /// certa). Assim o auto-disparo só acontece quando o cartão está realmente bem
  /// enquadrado.
  static FiducialResult _detectarFiduciais(
    List<int> luma, int w, int h, {
    int numQuestoes = 0,
    int? cartaoVersao,
  }) {
    const int sc = 4; // downsample p/ velocidade
    final int sw = w ~/ sc;
    final int sh = h ~/ sc;
    if (sw < 40 || sh < 40) {
      return const FiducialResult(ok: false, blobs: 0, pontos: []);
    }

    // Limiar adaptativo: fiduciais são bem mais escuros que o resto.
    int sum = 0, cnt = 0;
    for (int i = 0; i < luma.length; i += 17) {
      sum += luma[i];
      cnt++;
    }
    final double mean = cnt > 0 ? sum / cnt : 128;
    final int thr = (mean * 0.45).clamp(40, 110).toInt();

    // Máscara de pixels escuros (downsampled)
    final dark = Uint8List(sw * sh);
    for (int y = 0; y < sh; y++) {
      final int rowBase = (y * sc) * w;
      final int outBase = y * sw;
      for (int x = 0; x < sw; x++) {
        final int idx = rowBase + x * sc;
        if (idx < luma.length && luma[idx] < thr) dark[outBase + x] = 1;
      }
    }

    // Componentes conexas (4-conn) por flood fill; coleta centróides de blobs sólidos.
    final Uint8List seen = Uint8List(sw * sh);
    final List<double> cx = [];
    final List<double> cy = [];
    final List<int> stack = [];
    final double frameArea = (sw * sh).toDouble();
    final double minArea = frameArea * 0.0004;
    final double maxArea = frameArea * 0.03;

    for (int start = 0; start < sw * sh; start++) {
      if (dark[start] == 0 || seen[start] != 0) continue;
      stack
        ..clear()
        ..add(start);
      seen[start] = 1;
      int area = 0, sx = 0, sy = 0;
      int minx = sw, maxx = 0, miny = sh, maxy = 0;
      while (stack.isNotEmpty) {
        final int p = stack.removeLast();
        final int px = p % sw;
        final int py = p ~/ sw;
        area++;
        sx += px;
        sy += py;
        if (px < minx) minx = px;
        if (px > maxx) maxx = px;
        if (py < miny) miny = py;
        if (py > maxy) maxy = py;
        if (px > 0) {
          final q = p - 1;
          if (dark[q] == 1 && seen[q] == 0) { seen[q] = 1; stack.add(q); }
        }
        if (px < sw - 1) {
          final q = p + 1;
          if (dark[q] == 1 && seen[q] == 0) { seen[q] = 1; stack.add(q); }
        }
        if (py > 0) {
          final q = p - sw;
          if (dark[q] == 1 && seen[q] == 0) { seen[q] = 1; stack.add(q); }
        }
        if (py < sh - 1) {
          final q = p + sw;
          if (dark[q] == 1 && seen[q] == 0) { seen[q] = 1; stack.add(q); }
        }
      }
      if (area < minArea || area > maxArea) continue;
      final double bw = (maxx - minx + 1).toDouble();
      final double bh = (maxy - miny + 1).toDouble();
      final double aspect = bw / bh;
      if (aspect < 0.55 || aspect > 1.8) continue;   // ~ redondo
      if (area / (bw * bh) < 0.55) continue;          // sólido (disco cheio)
      cx.add(sx / area);
      cy.add(sy / area);
    }

    final int blobs = cx.length;
    if (blobs < 4) return FiducialResult(ok: false, blobs: blobs, pontos: const []);

    // 4 cantos pelos extremos das diagonais (robusto a rotação moderada)
    int iTL = 0, iBR = 0, iTR = 0, iBL = 0;
    double sMin = 1e9, sMax = -1e9, dMin = 1e9, dMax = -1e9;
    for (int i = 0; i < blobs; i++) {
      final double s = cx[i] + cy[i];
      final double d = cx[i] - cy[i];
      if (s < sMin) { sMin = s; iTL = i; }
      if (s > sMax) { sMax = s; iBR = i; }
      if (d > dMax) { dMax = d; iTR = i; }
      if (d < dMin) { dMin = d; iBL = i; }
    }
    if ({iTL, iTR, iBR, iBL}.length < 4) {
      return FiducialResult(ok: false, blobs: blobs, pontos: const []);
    }

    double dist(int a, int b) => sqrt((cx[a] - cx[b]) * (cx[a] - cx[b]) +
        (cy[a] - cy[b]) * (cy[a] - cy[b]));
    final double top = dist(iTL, iTR);
    final double bottom = dist(iBL, iBR);
    final double left = dist(iTL, iBL);
    final double right = dist(iTR, iBR);

    // Lados opostos quase iguais (retângulo de verdade, NÃO trapézio/inclinado).
    // Apertado de propósito: cartão inclinado vira cisalhamento na leitura.
    if ((top - bottom).abs() > 0.12 * max(top, bottom)) {
      return FiducialResult(ok: false, blobs: blobs, pontos: const []);
    }
    if ((left - right).abs() > 0.12 * max(left, right)) {
      return FiducialResult(ok: false, blobs: blobs, pontos: const []);
    }

    final double wAvg = (top + bottom) / 2;
    final double hAvg = (left + right) / 2;
    if (wAvg < 5 || hAvg < 5) {
      return FiducialResult(ok: false, blobs: blobs, pontos: const []);
    }

    // Proporção esperada do retângulo dos fiduciais:
    //   v3 → razão da grade (depende de numQuestoes: 1 col estreita, 2 cols larga)
    //   v2 → 186x273mm = 0.681 (A4-corner, legado)
    // Tolerância: ±0.12 (cobre variação de enquadramento + 1 col vs 2 cols).
    final double ratioEsperado = _razaoFiduciaisEsperada(numQuestoes, cartaoVersao);
    final double ratio = min(wAvg, hAvg) / max(wAvg, hAvg);
    if ((ratio - ratioEsperado).abs() > 0.12) {
      return FiducialResult(ok: false, blobs: blobs, pontos: const []);
    }

    // Pré-filtro OK: 4 fiduciais formando um retângulo A4 válido (reto, proporção).
    // A REGISTRAÇÃO (estar em cima dos círculos da moldura) é decidida na TELA,
    // que compara estes pontos com os alvos desenhados. Aqui só devolvemos os 4
    // centros NORMALIZADOS (0-1) no buffer, na ordem TL,TR,BL,BR.
    final List<double> pontos = [
      cx[iTL] / sw, cy[iTL] / sh,
      cx[iTR] / sw, cy[iTR] / sh,
      cx[iBL] / sw, cy[iBL] / sh,
      cx[iBR] / sw, cy[iBR] / sh,
    ];
    return FiducialResult(ok: true, blobs: blobs, pontos: pontos);
  }

  /// Fração do frame inteiro com brilho acima de [threshold] (papel claro).
  /// Proxy de distância: quanto mais o cartão preenche o quadro, maior o valor.
  static double _brightFraction(List<int> luma, int threshold) {
    int bright = 0;
    int total = 0;
    for (int i = 0; i < luma.length; i += 7) {
      total++;
      if (luma[i] > threshold) bright++;
    }
    return total > 0 ? bright / total : 0.0;
  }

  /// Detecta os 4 marcadores de canto (fiduciais) do cartão no frame ao vivo.
  ///
  /// Os fiduciais são círculos sólidos escuros próximos aos 4 cantos do cartão.
  /// Quando o cartão preenche a moldura, eles caem perto dos 4 cantos da região
  /// central do buffer. A checagem é INVARIANTE à rotação (um canto continua
  /// sendo um canto sob giro de 90°/180°), então funciona mesmo com o buffer da
  /// câmera em paisagem e o cartão em retrato.
  ///
  /// Retorna quantos cantos (0-4) têm um aglomerado escuro = fiducial.
  static int _detectCornerFiducials(List<int> luma, int w, int h) {
    // Região central onde o cartão deve estar (alinhada com _hasPaperInFrameRegion)
    final cl = (w * 0.12).round();
    final cr = (w * 0.88).round();
    final ct = (h * 0.15).round();
    final cb = (h * 0.85).round();
    final cw = cr - cl;
    final ch = cb - ct;
    if (cw < 60 || ch < 60) return 0;

    // Caixa de cada canto: ~20% da região central (tolera variação de distância)
    final bw = (cw * 0.20).round();
    final bh = (ch * 0.20).round();

    // Brilho do papel = média do miolo central (longe das bordas e dos cantos)
    final paper = _meanRegion(
      luma, w, h,
      cl + (cw / 3).round(), ct + (ch / 3).round(),
      cr - (cw / 3).round(), cb - (ch / 3).round(),
    );
    // Fiducial = bem mais escuro que o papel
    final darkThresh = paper * 0.55;

    final boxes = <List<int>>[
      [cl, ct, cl + bw, ct + bh],   // canto 1
      [cr - bw, ct, cr, ct + bh],   // canto 2
      [cl, cb - bh, cl + bw, cb],   // canto 3
      [cr - bw, cb - bh, cr, cb],   // canto 4
    ];

    int found = 0;
    for (final b in boxes) {
      int dark = 0;
      int total = 0;
      for (int y = b[1]; y < b[3]; y += 3) {
        for (int x = b[0]; x < b[2]; x += 3) {
          final idx = y * w + x;
          if (idx >= 0 && idx < luma.length) {
            total++;
            if (luma[idx] < darkThresh) dark++;
          }
        }
      }
      // Um fiducial sólido ocupa uma fração perceptível da caixa do canto.
      if (total > 0 && dark / total > 0.03) found++;
    }
    return found;
  }

  /// Média de brilho de uma região retangular do buffer luma (amostrada).
  static double _meanRegion(
    List<int> luma, int w, int h, int x0, int y0, int x1, int y1) {
    int sum = 0;
    int count = 0;
    for (int y = y0; y < y1 && y < h; y += 4) {
      for (int x = x0; x < x1 && x < w; x += 4) {
        final idx = y * w + x;
        if (idx >= 0 && idx < luma.length) {
          sum += luma[idx];
          count++;
        }
      }
    }
    return count > 0 ? sum / count : 128.0;
  }

  /// ✨ NOVO: Verificar se há papel branco na área central da moldura
  /// Amostra a região central (15-85% largura, 20-80% altura) e checa brilho > 170
  static bool _hasPaperInFrameRegion(List<int> luma, int w, int h) {
    final left = (w * 0.15).round();
    final right = (w * 0.85).round();
    final top = (h * 0.20).round();
    final bottom = (h * 0.80).round();
    int sum = 0;
    int count = 0;
    for (int y = top; y < bottom; y += 4) {
      for (int x = left; x < right; x += 4) {
        final idx = y * w + x;
        if (idx < luma.length) {
          sum += luma[idx];
          count++;
        }
      }
    }
    // Papel branco tem brilho tipicamente > 170 no canal Y
    return count > 0 && (sum / count) > 170;
  }

  /// Extrair dica textual baseada no estado ao vivo
  static String getTipForLiveQualityState(LiveQualityState state) {
    switch (state) {
      case LiveQualityState.analyzing:
        return 'Encaixe o cartão na moldura';
      case LiveQualityState.excellent:
        return '✅ Excelente! Pode fotografar';
      case LiveQualityState.good:
        return '✅ Boa iluminação • Pode fotografar';
      case LiveQualityState.warning:
        return '⚠️ Encaixe o cartão na moldura ou mude o ângulo';
      case LiveQualityState.bad:
        return '🔦 Muito escuro • Acenda o flash';
    }
  }

  /// Calcular brilho a partir de bytes brutos (canal Y/luma)
  static double _calculateBrightnessFromBytes(
    List<int> bytes,
    int width,
    int height,
  ) {
    int sum = 0;
    int count = 0;

    // Amostragem cada 10 pixels para performance
    final step = 10;
    for (int i = 0; i < bytes.length; i += step) {
      sum += bytes[i];
      count++;
    }

    return count > 0 ? sum / count : 128;
  }

  /// Calcular uniformidade de iluminação a partir de bytes brutos
  static double _calculateIlluminationFromBytes(
    List<int> bytes,
    int width,
    int height,
  ) {
    if (bytes.isEmpty) return 0.5;

    // Dividir em 4 quadrantes
    List<double> quadrants = [];
    int qx = width ~/ 2;
    int qy = height ~/ 2;

    // Amostra cada quadrante
    for (int qIdx = 0; qIdx < 4; qIdx++) {
      int startRow = (qIdx ~/ 2) * qy;
      int endRow = startRow + qy;
      int startCol = (qIdx % 2) * qx;
      int endCol = startCol + qx;

      int sum = 0;
      int count = 0;

      // Amostragem cada 5 pixels
      for (int row = startRow; row < endRow && row < height; row += 5) {
        for (int col = startCol; col < endCol && col < width; col += 5) {
          int idx = row * width + col;
          if (idx < bytes.length) {
            sum += bytes[idx];
            count++;
          }
        }
      }

      if (count > 0) {
        quadrants.add(sum / count);
      }
    }

    if (quadrants.isEmpty) return 0.5;

    final mean = quadrants.reduce((a, b) => a + b) / quadrants.length;
    final maxDiff = quadrants.fold<double>(
      0,
      (max, q) => max > (q - mean).abs() ? max : (q - mean).abs(),
    );

    // Normalizar: se maxDiff > 100, uniformidade é ruim
    return (1 - (maxDiff / 200)).clamp(0.0, 1.0);
  }

  /// Calcular brilho médio da imagem (0-255)
  static double _calculateBrightness(img.Image image) {
    int sum = 0;
    int count = 0;

    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixelSafe(x, y);
        final brightness = _pixelBrightness(pixel);
        sum += brightness;
        count++;
      }
    }

    return count > 0 ? sum / count : 128;
  }

  /// Calcular contraste usando desvio padrão (0-255)
  static double _calculateContrast(img.Image image) {
    List<int> values = [];

    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixelSafe(x, y);
        final brightness = _pixelBrightness(pixel);
        values.add(brightness);
      }
    }

    if (values.isEmpty) return 0;

    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    final stdDev = variance.isNaN ? 0.0 : sqrt(variance);

    return stdDev.toDouble();
  }

  /// Estimar nitidez usando detecção de bordas (Sobel)
  /// Retorna 0-1 (1 = muito nítido)
  static double _calculateSharpness(img.Image image) {
    try {
      // Redimensionar para performance
      final small = img.copyResize(image, width: 320, height: 240);

      int edgeCount = 0;
      int totalCount = 0;

      for (int y = 1; y < small.height - 1; y++) {
        for (int x = 1; x < small.width - 1; x++) {
          // Sobel horizontal
          final tl = small.getPixelSafe(x - 1, y - 1);
          final tr = small.getPixelSafe(x + 1, y - 1);
          final bl = small.getPixelSafe(x - 1, y + 1);
          final br = small.getPixelSafe(x + 1, y + 1);
          final l = small.getPixelSafe(x - 1, y);
          final r = small.getPixelSafe(x + 1, y);

          final gx = _pixelBrightness(tl) + 2 * _pixelBrightness(l) + _pixelBrightness(bl) -
              _pixelBrightness(tr) - 2 * _pixelBrightness(r) - _pixelBrightness(br);

          // Sobel vertical
          final t = small.getPixelSafe(x, y - 1);
          final b = small.getPixelSafe(x, y + 1);

          final gy = _pixelBrightness(tl) + 2 * _pixelBrightness(t) + _pixelBrightness(tr) -
              _pixelBrightness(bl) - 2 * _pixelBrightness(b) - _pixelBrightness(br);

          final magnitude = sqrt((gx * gx + gy * gy).toDouble());
          if (magnitude > 100) {
            edgeCount++;
          }

          totalCount++;
        }
      }

      if (totalCount == 0) return 0;
      return (edgeCount / totalCount).clamp(0.0, 1.0);
    } catch (e) {
      return 0.5; // Fallback
    }
  }

  /// Estimar uniformidade de iluminação (0-1)
  /// Divide imagem em quadrantes e compara intensidades
  static double _calculateIlluminationUniformity(img.Image image) {
    final qx = image.width ~/ 4;
    final qy = image.height ~/ 4;

    List<double> quadrants = [];

    // Amostra 4 quadrantes
    for (int qIdx = 0; qIdx < 4; qIdx++) {
      int startX = (qIdx % 2) * qx * 2 + qx;
      int startY = (qIdx ~/ 2) * qy * 2 + qy;
      int endX = startX + qx;
      int endY = startY + qy;

      int sum = 0;
      int count = 0;

      for (int y = startY; y < endY && y < image.height; y += 5) {
        for (int x = startX; x < endX && x < image.width; x += 5) {
          final pixel = image.getPixelSafe(x, y);
          sum += _pixelBrightness(pixel);
          count++;
        }
      }

      if (count > 0) {
        quadrants.add(sum / count);
      }
    }

    if (quadrants.isEmpty) return 0.5;

    final mean = quadrants.reduce((a, b) => a + b) / quadrants.length;
    final maxDiff = quadrants.fold<double>(0, (max, q) => maxof(max, (q - mean).abs()));

    // Normalizar: se maxDiff > 100, uniformidade é ruim
    return (1 - (maxDiff / 200)).clamp(0.0, 1.0);
  }

  /// Estimar visibilidade dos cantos
  /// Verifica bordas escuras nos cantos (marcadores de canto do cartão)
  static double _estimateCornerVisibility(img.Image image) {
    const cornerSize = 50; // Tamanho da região de canto a verificar
    int darkCornersDetected = 0;

    // Verificar cada um dos 4 cantos
    List<List<int>> corners = [
      [0, 0], // top-left
      [image.width - cornerSize, 0], // top-right
      [0, image.height - cornerSize], // bottom-left
      [image.width - cornerSize, image.height - cornerSize], // bottom-right
    ];

    for (final corner in corners) {
      int x = corner[0].clamp(0, image.width - 1);
      int y = corner[1].clamp(0, image.height - 1);

      // Amostra 5x5 no canto
      int darkCount = 0;
      int totalCount = 0;

      for (int dy = 0; dy < 5; dy++) {
        for (int dx = 0; dx < 5; dx++) {
          final sy = (y + dy * (cornerSize ~/ 5)).clamp(0, image.height - 1);
          final sx = (x + dx * (cornerSize ~/ 5)).clamp(0, image.width - 1);
          final pixel = image.getPixelSafe(sx, sy);
          if (_pixelBrightness(pixel) < 100) {
            darkCount++;
          }
          totalCount++;
        }
      }

      if (darkCount > totalCount * 0.3) {
        darkCornersDetected++;
      }
    }

    return darkCornersDetected / 4;
  }

  /// Extrair brilho de um pixel (0-255)
  static int _pixelBrightness(dynamic pixel) {
    // Pixel pode ser um objeto Pixel ou um int (ARGB)
    if (pixel is int) {
      // Format ARGB: extrair componentes
      final r = (pixel >> 16) & 0xFF;
      final g = (pixel >> 8) & 0xFF;
      final b = pixel & 0xFF;
      return (0.299 * r + 0.587 * g + 0.114 * b).toInt();
    } else {
      // Assumir que é um objeto Pixel com propriedades r, g, b
      final r = pixel.r ?? 0;
      final g = pixel.g ?? 0;
      final b = pixel.b ?? 0;
      return (0.299 * r + 0.587 * g + 0.114 * b).toInt();
    }
  }

  /// Gerar recomendação textual baseada na análise
  static String _generateRecommendation({
    required double brightness,
    required double contrast,
    required double sharpness,
    required double illumination,
    required double corners,
  }) {
    final issues = <String>[];

    if (brightness < 100) {
      issues.add('Imagem muito escura');
    } else if (brightness > 240) {
      issues.add('Imagem muito clara');
    }

    if (contrast < 30) {
      issues.add('Contraste baixo');
    }

    if (sharpness < 0.5) {
      issues.add('Imagem desfocada');
    }

    if (illumination < 0.6) {
      issues.add('Sombras detectadas');
    }

    if (corners < 0.5) {
      issues.add('Cantos não visíveis');
    }

    if (issues.isEmpty) {
      return '✅ Qualidade excelente!';
    }

    return '⚠️ ' + issues.join(' • ');
  }

  static double maxof(double a, double b) => a > b ? a : b;

  /// Resultado padrão para falhas
  static ImageQualityResult _createFailedResult() {
    return ImageQualityResult(
      brightness: 0,
      contrast: 0,
      sharpness: 0,
      illuminationUniformity: 0,
      cornerVisibility: 0,
      overallScore: 0,
      recommendation: '❌ Erro ao analisar imagem',
    );
  }
}
