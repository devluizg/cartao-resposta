// frame_guide_painter.dart
// CustomPainter para desenhar guia de enquadramento avançado
import 'package:flutter/material.dart';
import '../services/frame_alignment_analyzer.dart';

/// Painter que desenha a moldura de guia com todos os indicadores
class FrameGuidePainter extends CustomPainter {
  final Color frameColor;
  final FrameAlignmentState alignmentState;
  final double skewAngle; // ângulo em graus
  final bool showAdvancedGuides;

  // Constantes de dimensões (em proporção da tela)
  static const double CARTAO_ASPECT_RATIO = 210 / 297; // A4

  FrameGuidePainter({
    required this.frameColor,
    required this.alignmentState,
    required this.skewAngle,
    this.showAdvancedGuides = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calcular dimensões da moldura A4
    final frameHeight = size.height * 0.85; // 85% da altura disponível
    final frameWidth = frameHeight * CARTAO_ASPECT_RATIO;
    final frameLeft = (size.width - frameWidth) / 2;
    final frameTop = (size.height - frameHeight) / 2;

    if (showAdvancedGuides) {
      _drawAdvancedGuides(
        canvas,
        size,
        frameLeft,
        frameTop,
        frameWidth,
        frameHeight,
      );
    } else {
      _drawSimpleFrame(
        canvas,
        frameLeft,
        frameTop,
        frameWidth,
        frameHeight,
      );
    }
  }

  /// Desenha moldura simples (compatível com implementação atual)
  void _drawSimpleFrame(
    Canvas canvas,
    double left,
    double top,
    double width,
    double height,
  ) {
    final paint = Paint()
      ..color = frameColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Borda principal
    canvas.drawRect(Rect.fromLTWH(left, top, width, height), paint);

    // Cantos em L (guias visuais)
    const cornerLen = 30.0;
    const cornerThick = 3.0;
    _drawCorners(canvas, left, top, width, height, cornerLen, cornerThick);
  }

  /// Desenha guias avançadas com múltiplos indicadores
  void _drawAdvancedGuides(
    Canvas canvas,
    Size size,
    double left,
    double top,
    double width,
    double height,
  ) {
    // 1. Moldura principal
    _drawMainFrame(canvas, left, top, width, height);

    // 2. Área de segurança (não cortar conteúdo)
    _drawSafetyArea(canvas, left, top, width, height);

    // 3. Marcadores de canto esperados (4 círculos)
    _drawExpectedCornerMarkers(canvas, left, top, width, height);

    // 4. Linhas de perspectiva (detecta inclinação)
    _drawPerspectiveLines(canvas, left, top, width, height);

    // 5. Indicador de ângulo (no topo)
    _drawAngleIndicator(canvas, size.width, 30);

    // 6. Indicador de distância (no canto inferior)
    _drawDistanceIndicator(canvas, size.width, size.height);

    // 7. Cantos em L (mais destacados)
    const cornerLen = 40.0;
    const cornerThick = 4.0;
    _drawCorners(canvas, left, top, width, height, cornerLen, cornerThick);
  }

  /// Desenha a moldura principal A4
  void _drawMainFrame(Canvas canvas, double left, double top, double width,
      double height) {
    final paint = Paint()
      ..color = frameColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawRect(Rect.fromLTWH(left, top, width, height), paint);
  }

  /// Desenha a área de segurança (linha vermelha onde não cortar)
  void _drawSafetyArea(Canvas canvas, double left, double top, double width,
      double height) {
    final safetyMargin = 15.0; // px
    final safetyPaint = Paint()
      ..color = Colors.red.withOpacity(0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawRect(
      Rect.fromLTWH(left + safetyMargin, top + safetyMargin,
          width - 2 * safetyMargin, height - 2 * safetyMargin),
      safetyPaint,
    );

    // Texto de aviso
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '🚫 Não corte',
        style: TextStyle(
          color: Colors.red,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(left + 8, top + 5));
  }

  /// Desenha os 4 marcadores de canto esperados
  void _drawExpectedCornerMarkers(Canvas canvas, double left, double top,
      double width, double height) {
    const markerSize = 12.0;
    const offset = 8.0;

    final markerPaint = Paint()
      ..color = Colors.green.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final corners = [
      (left + offset, top + offset), // TL
      (left + width - offset, top + offset), // TR
      (left + offset, top + height - offset), // BL
      (left + width - offset, top + height - offset), // BR
    ];

    for (final corner in corners) {
      canvas.drawCircle(Offset(corner.$1, corner.$2), 4, markerPaint);
    }

    // Texto identificando os marcadores
    const markerLabel = ['TL', 'TR', 'BL', 'BR'];
    for (int i = 0; i < corners.length; i++) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: markerLabel[i],
          style: const TextStyle(
            color: Colors.green,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(corners[i].$1 + 8, corners[i].$2 + 8),
      );
    }
  }

  /// Desenha linhas de perspectiva (detecta inclinação)
  void _drawPerspectiveLines(Canvas canvas, double left, double top,
      double width, double height) {
    final perspectivePaint = Paint()
      ..color = Colors.blue.withOpacity(0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Linhas diagonais (X) para detectar perspectiva
    canvas.drawLine(Offset(left, top), Offset(left + width, top + height),
        perspectivePaint);
    canvas.drawLine(Offset(left + width, top), Offset(left, top + height),
        perspectivePaint);

    // Linhas verticais (detecta inclinação)
    final verticalPaint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..strokeWidth = 1
      ..dashPattern = [5, 5]
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(left, top), Offset(left, top + height),
        verticalPaint); // Esquerda
    canvas.drawLine(Offset(left + width, top), Offset(left + width, top + height),
        verticalPaint); // Direita
  }

  /// Desenha indicador de ângulo (topo da câmera)
  void _drawAngleIndicator(Canvas canvas, double screenWidth, double y) {
    final centerX = screenWidth / 2;

    // Fundo semi-transparente
    final bgPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - 80, y, 160, 40),
        const Radius.circular(8),
      ),
      bgPaint,
    );

    // Desenhar escala de ângulo
    final scalePaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = 1;

    // Marcas de -15 a +15 graus
    for (int angle = -15; angle <= 15; angle += 5) {
      final x = centerX - 60 + ((angle + 15) / 30) * 120;
      final markHeight = angle % 10 == 0 ? 8 : 4;
      canvas.drawLine(
        Offset(x, y + 15),
        Offset(x, y + 15 + markHeight),
        scalePaint,
      );
    }

    // Indicador atual (linha vermelha ou verde)
    final indicatorColor =
        alignmentState == FrameAlignmentState.perfectAngle ||
                alignmentState == FrameAlignmentState.goodAngle
            ? Colors.green
            : Colors.red;

    final indicatorX = centerX - 60 + ((skewAngle.clamp(-15, 15) + 15) / 30) * 120;
    final indicatorPaint = Paint()
      ..color = indicatorColor
      ..strokeWidth = 3;

    canvas.drawLine(Offset(indicatorX, y + 10), Offset(indicatorX, y + 30),
        indicatorPaint);

    // Texto do ângulo
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${skewAngle.toStringAsFixed(1)}°',
        style: TextStyle(
          color: indicatorColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(centerX - textPainter.width / 2, y + 35));
  }

  /// Desenha indicador de distância (canto inferior)
  void _drawDistanceIndicator(Canvas canvas, double screenWidth,
      double screenHeight) {
    final x = screenWidth - 120;
    final y = screenHeight - 60;

    // Fundo
    final bgPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, 110, 50),
        const Radius.circular(8),
      ),
      bgPaint,
    );

    // Ícone de distância
    final iconPainter = TextPainter(
      text: const TextSpan(
        text: '📏',
        style: TextStyle(fontSize: 20),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(canvas, Offset(x + 10, y + 5));

    // Texto
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Ideal:\n20-30cm',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x + 35, y + 8));
  }

  /// Desenha cantos em L (guias visuais)
  void _drawCorners(
    Canvas canvas,
    double left,
    double top,
    double width,
    double height,
    double cornerLen,
    double cornerThick,
  ) {
    final paint = Paint()
      ..color = frameColor
      ..strokeWidth = cornerThick
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final corners = [
      (left, top, true, true), // TL
      (left + width, top, false, true), // TR
      (left, top + height, true, false), // BL
      (left + width, top + height, false, false), // BR
    ];

    for (final corner in corners) {
      final x = corner.$1;
      final y = corner.$2;
      final isLeft = corner.$3;
      final isTop = corner.$4;

      final endX = isLeft ? x + cornerLen : x - cornerLen;
      final endY = isTop ? y + cornerLen : y - cornerLen;

      // Linha horizontal
      canvas.drawLine(Offset(x, y), Offset(endX, y), paint);
      // Linha vertical
      canvas.drawLine(Offset(x, y), Offset(x, endY), paint);
    }
  }

  @override
  bool shouldRepaint(FrameGuidePainter oldDelegate) {
    return oldDelegate.frameColor != frameColor ||
        oldDelegate.alignmentState != alignmentState ||
        oldDelegate.skewAngle != skewAngle;
  }
}
