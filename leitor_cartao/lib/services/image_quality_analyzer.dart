// image_quality_analyzer.dart
// Serviço para análise de qualidade de imagem em tempo real durante captura
import 'dart:math';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Estado de qualidade ao vivo para feedback em tempo real
enum LiveQualityState { analyzing, excellent, good, warning, bad }

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
    try {
      if (lumaBytes.isEmpty) {
        return LiveQualityState.analyzing;
      }

      // Calcular brilho médio (amostragem rápida)
      double brightness = _calculateBrightnessFromBytes(lumaBytes, width, height);

      // Calcular uniformidade de iluminação (amostragem rápida)
      double illumination =
          _calculateIlluminationFromBytes(lumaBytes, width, height);

      // ✨ NOVO: Verificar se há papel branco na área central da moldura
      final hasPaper = _hasPaperInFrameRegion(lumaBytes, width, height);

      // Determinar estado baseado em brightness e illumination
      if (brightness < 100) {
        return LiveQualityState.bad; // Muito escuro
      } else if (brightness > 240) {
        return LiveQualityState.bad; // Muito claro
      }

      // ✨ NOVO: Se não há papel na moldura, avisar usuário
      if (!hasPaper) {
        return LiveQualityState.warning; // Cartão fora da moldura
      }

      // Se iluminação ruim, warning
      if (illumination < 0.55) {
        return LiveQualityState.warning; // Sombra detectada
      }

      // Se tudo bom
      if (brightness >= 150 && brightness <= 220 && illumination > 0.75) {
        return LiveQualityState.excellent;
      }

      if (brightness >= 120 && brightness <= 230 && illumination > 0.65) {
        return LiveQualityState.good;
      }

      return LiveQualityState.warning;
    } catch (e) {
      print('❌ Erro na análise rápida: $e');
      return LiveQualityState.analyzing;
    }
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
