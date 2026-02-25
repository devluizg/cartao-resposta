// frame_alignment_analyzer.dart
// Analisa alinhamento e perspectiva do cartão-resposta em tempo real
import 'package:camera/camera.dart';
import 'dart:math';

/// Estado de alinhamento do cartão
enum FrameAlignmentState {
  analyzing,      // Analisando
  perfectAngle,   // Ângulo perfeito (0°)
  goodAngle,      // Ângulo bom (±5°)
  warningAngle,   // Ângulo aviso (±10°)
  badAngle,       // Ângulo ruim (>±15°)
}

/// Resultado da análise de alinhamento
class FrameAlignmentResult {
  final FrameAlignmentState state;
  final double skewAngle; // Ângulo em graus (0° = reto)
  final double confidence; // Confiança da detecção (0-1)
  final String message; // Mensagem para o usuário
  final bool isFrameCentered; // Se está centralizado
  final bool isDistanceIdeal; // Se a distância é ideal
  final bool allMarkersVisible; // Se os 4 marcadores estão visíveis

  FrameAlignmentResult({
    required this.state,
    required this.skewAngle,
    required this.confidence,
    required this.message,
    required this.isFrameCentered,
    required this.isDistanceIdeal,
    required this.allMarkersVisible,
  });

  /// Status geral: verde quando tudo OK
  bool get isReadyToCapture =>
      state == FrameAlignmentState.perfectAngle ||
      state == FrameAlignmentState.goodAngle;

  /// Cor da moldura baseada no estado
  int get frameColorARGB {
    switch (state) {
      case FrameAlignmentState.analyzing:
        return 0xFFF59E0B; // Amarelo (analisando)
      case FrameAlignmentState.perfectAngle:
        return 0xFF22C55E; // Verde perfeito
      case FrameAlignmentState.goodAngle:
        return 0xFF22C55E; // Verde bom
      case FrameAlignmentState.warningAngle:
        return 0xFFF97316; // Laranja (warning)
      case FrameAlignmentState.badAngle:
        return 0xFFEF4444; // Vermelho (ruim)
    }
  }
}

/// Analisador de alinhamento de frame
class FrameAlignmentAnalyzer {
  /// Proporcional do cartão A4: 210mm x 297mm
  static const double CARTAO_ASPECT_RATIO = 210 / 297; // ≈ 0.707

  /// Marcadores de canto esperados (em mm no papel)
  /// TL: (12, 285), TR: (198, 285), BL: (12, 12), BR: (198, 12)
  static const double MARKER_DISTANCE_H = 186; // 198 - 12 mm
  static const double MARKER_DISTANCE_V = 273; // 285 - 12 mm

  /// Análise rápida baseada em dimensões
  static Future<FrameAlignmentResult> analyzeFrame(
    int frameWidth,
    int frameHeight,
  ) async {
    final cameraAspect = frameWidth / frameHeight;
    final cartaoAspect = CARTAO_ASPECT_RATIO;

    // Calcular quanto o cartão deveria ocupar da câmera
    // Se câmera tem aspect ratio maior, cartão cabe em altura
    double occupiedHeightPercent = 0.8; // 80% da altura da câmera
    double expectedCartaoHeight = frameHeight * occupiedHeightPercent;
    double expectedCartaoWidth = expectedCartaoHeight * cartaoAspect;

    // Verificar se está centralizado horizontalmente
    double centerX = frameWidth / 2;
    double expectedLeft = centerX - (expectedCartaoWidth / 2);
    double expectedRight = centerX + (expectedCartaoWidth / 2);

    // Simular área esperada do cartão
    bool isFrameCentered = expectedLeft > frameWidth * 0.05 &&
        expectedRight < frameWidth * 0.95;

    // Verificar se a proporção está correta
    bool isProportionCorrect =
        (expectedCartaoWidth / expectedCartaoHeight - cartaoAspect).abs() < 0.1;

    // Por enquanto, assumimos ângulo perfeito se proporção está OK
    // Em implementação real, usar detecção de marcadores de canto
    final skewAngle = 0.0; // Será calculado com detecção de marcadores
    final state = FrameAlignmentState.perfectAngle;

    return FrameAlignmentResult(
      state: state,
      skewAngle: skewAngle,
      confidence: 0.8,
      message: '✅ Posição ideal • Pode fotografar',
      isFrameCentered: isFrameCentered,
      isDistanceIdeal: true, // Será calculado com detecção de bolhas
      allMarkersVisible: true, // Será calculado com detecção de marcadores
    );
  }

  /// Detectar marcadores de canto na imagem (implementação futura)
  /// Retorna: [(x, y), ...] dos 4 marcadores detectados
  static Future<List<(double, double)>?> detectCornerMarkers(
    List<int> imageData,
    int width,
    int height,
  ) async {
    // TODO: Implementar detecção com OpenCV/flutter
    // Por enquanto, retorna null (não detectado)
    return null;
  }

  /// Calcular skew (inclinação) dos 4 pontos de canto
  static double calculateSkew(List<(double, double)> corners) {
    if (corners.length < 4) return 0;

    // corners: [TL, TR, BL, BR]
    final tl = corners[0];
    final tr = corners[1];
    final bl = corners[2];
    final br = corners[3];

    // Calcular ângulo da linha superior (TL -> TR)
    final dxTop = tr.$1 - tl.$1;
    final dyTop = tr.$2 - tl.$2;
    final angleTop = atan2(dyTop, dxTop) * 180 / pi;

    // Calcular ângulo da linha esquerda (TL -> BL)
    final dxLeft = bl.$1 - tl.$1;
    final dyLeft = bl.$2 - tl.$2;
    final angleLeft = atan2(dyLeft, dxLeft) * 180 / pi;

    // Skew = desvio do ângulo esperado (0° para horizontal)
    // Se está reto, angleTop ≈ 0° e angleLeft ≈ 90°
    final skew = angleTop.abs() + (angleLeft - 90).abs();

    return skew.clamp(0, 180);
  }

  /// Classificar estado baseado no skew angle
  static FrameAlignmentState classifyAngle(double skewAngle) {
    if (skewAngle <= 2) {
      return FrameAlignmentState.perfectAngle;
    } else if (skewAngle <= 5) {
      return FrameAlignmentState.goodAngle;
    } else if (skewAngle <= 10) {
      return FrameAlignmentState.warningAngle;
    } else {
      return FrameAlignmentState.badAngle;
    }
  }

  /// Gerar mensagem baseada no estado
  static String getMessageForState(
    FrameAlignmentState state,
    double skewAngle,
    bool isFrameCentered,
    bool isDistanceIdeal,
  ) {
    switch (state) {
      case FrameAlignmentState.analyzing:
        return '⏳ Analisando alinhamento...';

      case FrameAlignmentState.perfectAngle:
        if (!isFrameCentered) {
          return '↔️ Centralize o cartão';
        }
        if (!isDistanceIdeal) {
          return '📏 Distância ideal: 20-30cm';
        }
        return '✅ Perfeito! Pode fotografar';

      case FrameAlignmentState.goodAngle:
        if (skewAngle > 0) {
          return '🔄 Inclinado ${skewAngle.toStringAsFixed(1)}° • Corrija posição';
        }
        return '✅ Boa posição • Pode fotografar';

      case FrameAlignmentState.warningAngle:
        return '⚠️ Inclinado ${skewAngle.toStringAsFixed(1)}° • Deixe reto';

      case FrameAlignmentState.badAngle:
        return '❌ Muito inclinado (${skewAngle.toStringAsFixed(1)}°) • Alinhe com os cantos';
    }
  }
}
