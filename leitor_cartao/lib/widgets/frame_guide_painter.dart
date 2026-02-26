// frame_guide_painter.dart
// CustomPainter para desenhar guia de enquadramento proporcional ao PDF
import 'package:flutter/material.dart';
import '../services/frame_alignment_analyzer.dart';

/// Painter que desenha a moldura com proporções EXATAS do PDF A4
class FrameGuidePainter extends CustomPainter {
  final Color frameColor;
  final FrameAlignmentState alignmentState;
  final double skewAngle; // ângulo em graus
  final bool showAdvancedGuides;

  // ✨ CONSTANTES A4 EM MM (do PDF Django)
  static const double PAPER_WIDTH_MM = 210;
  static const double PAPER_HEIGHT_MM = 297;
  static const double CARTAO_ASPECT_RATIO = PAPER_WIDTH_MM / PAPER_HEIGHT_MM;

  // Padding externo do PDF (wrapper)
  static const double PADDING_MM = 8;

  // Marcadores de canto (4 círculos sólidos pretos)
  static const double MARKER_DIAMETER_MM = 14;
  static const double MARKER_OFFSET_MM = 4; // distância do canto até o centro

  // Bolhas de respostas
  static const double BUBBLE_RESPONSE_MM = 6.5; // Alternativas A-E
  static const double BUBBLE_TYPE_MM = 8;       // Tipo de prova

  // Margens internas
  static const double INNER_MARGIN_MM = 12; // Header, footer, laterais
  static const double SAFETY_MARGIN_MM = 8; // Borda de segurança

  FrameGuidePainter({
    required this.frameColor,
    required this.alignmentState,
    required this.skewAngle,
    this.showAdvancedGuides = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calcular altura da moldura (85% da tela)
    final frameHeight = size.height * 0.85;
    final frameWidth = frameHeight * CARTAO_ASPECT_RATIO;
    final frameLeft = (size.width - frameWidth) / 2;
    final frameTop = (size.height - frameHeight) / 2;

    // ✨ NOVA: Calcular escala mm → px
    final pxPerMm = frameWidth / PAPER_WIDTH_MM;

    if (showAdvancedGuides) {
      _drawAdvancedGuides(
        canvas,
        size,
        frameLeft,
        frameTop,
        frameWidth,
        frameHeight,
        pxPerMm,
      );
    } else {
      _drawSimpleFrame(
        canvas,
        frameLeft,
        frameTop,
        frameWidth,
        frameHeight,
        pxPerMm,
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
    double pxPerMm,
  ) {
    final paint = Paint()
      ..color = frameColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Borda principal
    canvas.drawRect(Rect.fromLTWH(left, top, width, height), paint);

    // Cantos em L (guias visuais)
    final cornerLen = 40 * pxPerMm;
    final cornerThick = 4 * pxPerMm;
    _drawCorners(canvas, left, top, width, height, cornerLen, cornerThick);
  }

  /// Desenha guias avançadas com múltiplos indicadores proporcionais
  void _drawAdvancedGuides(
    Canvas canvas,
    Size size,
    double left,
    double top,
    double width,
    double height,
    double pxPerMm,
  ) {
    // 1. Moldura principal
    _drawMainFrame(canvas, left, top, width, height);

    // 2. Marcadores de canto esperados (4 círculos PROPORCIONAIS)
    _drawExpectedCornerMarkers(canvas, left, top, width, height, pxPerMm);

    // 3. Indicador de ângulo (no topo)
    _drawAngleIndicator(canvas, size.width, 30);

    // 4. Indicador de distância (no canto inferior)
    _drawDistanceIndicator(canvas, size.width, size.height);

    // 5. Cantos em L (mais destacados)
    final cornerLen = 40.0 * pxPerMm;
    final cornerThick = 4.0 * pxPerMm;
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




  /// Desenha os 4 marcadores de canto COM TAMANHO PROPORCIONAL
  void _drawExpectedCornerMarkers(
    Canvas canvas,
    double left,
    double top,
    double width,
    double height,
    double pxPerMm,
  ) {
    // ✨ CORRIGIDO: Usar dimensões do PDF
    final markerDiameter = MARKER_DIAMETER_MM * pxPerMm;
    final markerRadius = markerDiameter / 2;
    final markerOffset = MARKER_OFFSET_MM * pxPerMm;

    final markerPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

    final markerStrokePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final corners = [
      (left + markerOffset, top + markerOffset), // TL
      (left + width - markerOffset, top + markerOffset), // TR
      (left + markerOffset, top + height - markerOffset), // BL
      (left + width - markerOffset, top + height - markerOffset), // BR
    ];

    // Desenhar círculos sólidos (como no PDF)
    for (final corner in corners) {
      canvas.drawCircle(
        Offset(corner.$1, corner.$2),
        markerRadius,
        markerPaint,
      );
      // Borda para melhor visibilidade
      canvas.drawCircle(
        Offset(corner.$1, corner.$2),
        markerRadius,
        markerStrokePaint,
      );
    }

    // Label "Marcadores" para a inst. visual
    const markerLabel = ['TL', 'TR', 'BL', 'BR'];
    for (int i = 0; i < corners.length; i++) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: '■ ${markerLabel[i]}',
          style: const TextStyle(
            color: Colors.green,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Posicionar label fora do círculo
      final offsetDistance = markerRadius + 12;
      double labelX = corners[i].$1;
      double labelY = corners[i].$2;

      switch (i) {
        case 0: // TL
          labelX += offsetDistance;
          labelY += 2;
          break;
        case 1: // TR
          labelX -= textPainter.width + offsetDistance;
          labelY += 2;
          break;
        case 2: // BL
          labelX += offsetDistance;
          labelY -= textPainter.height;
          break;
        case 3: // BR
          labelX -= textPainter.width + offsetDistance;
          labelY -= textPainter.height;
          break;
      }

      textPainter.paint(canvas, Offset(labelX, labelY));
    }
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
