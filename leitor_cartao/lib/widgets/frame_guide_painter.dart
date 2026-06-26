// frame_guide_painter.dart
// CustomPainter para desenhar guia de enquadramento proporcional ao PDF
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/frame_alignment_analyzer.dart';

// ── Geometria da grade v3 (espelha questions/pdf_generator.py) ───────────────
const double _kLarguraNecessariaMm = 36.2;
const double _kLarguraIndiceMm = 8.0;
const double _kEspacoColunasMm = 18.0;
const double _kEspacoQuestoesMm = 7.0;
const double _kMargemInternaMm = 4.0;
const double _kFiducialPaddingMm = 8.0;

/// Divisão de questões por coluna (espelha split_colunas do backend).
List<int> questoesPorColunaApp(int n) {
  final ncol = n <= 23 ? 1 : 2;
  if (ncol == 1) return [n];
  if (n % 2 == 0) return [n ~/ 2, n ~/ 2];
  return [n ~/ 2 + 1, n ~/ 2];
}

/// Largura/altura (mm) do retângulo dos CENTROS dos 4 fiduciais v3 — o bloco de
/// bolhas + 8mm de folga em cada lado. Depende de num_questoes.
({double wMm, double hMm}) retanguloFiduciaisMm(int numQuestoes) {
  final qpc = questoesPorColunaApp(numQuestoes);
  final ncol = qpc.length;
  final larguraTotal = _kLarguraNecessariaMm * ncol +
      _kEspacoColunasMm * (ncol - 1) +
      _kLarguraIndiceMm * ncol;
  final alturaBloco =
      qpc.reduce(math.max) * _kEspacoQuestoesMm + 2 * _kMargemInternaMm;
  return (
    wMm: larguraTotal + 2 * _kFiducialPaddingMm,
    hMm: alturaBloco + 2 * _kFiducialPaddingMm,
  );
}

/// Geometria da moldura v3 (FONTE ÚNICA — usada pelo painter E pela tela de
/// captura). A moldura agora enquadra SÓ a grade (não a folha A4): os 4 fiduciais
/// ficam ao redor do bloco de bolhas, então os 4 centros SÃO os cantos do
/// retângulo. Aspecto vem de num_questoes. Retorna os centros (TL,TR,BL,BR em
/// coords do canvas/preview), o retângulo e a escala px/mm.
///
/// [cameraPreviewRect] — área visível do preview da câmera dentro do canvas (pode
/// ter barras pretas acima/abaixo). Quando fornecido, a moldura é posicionada
/// DENTRO dessa área para garantir que os círculos-guia nunca fiquem nas barras.
({List<Offset> centros, double pxPerMm, Rect rect}) molduraGeometria(
    Size size, int numQuestoes, {Rect? cameraPreviewRect}) {
  final fid = retanguloFiduciaisMm(numQuestoes);
  final double aspect = fid.wMm / fid.hMm;

  // Área utilizável: preview real da câmera (sem barras pretas) ou tela completa.
  final Rect area = cameraPreviewRect ??
      Rect.fromLTWH(0, 0, size.width, size.height);

  // Cobertura alta = "zoom" na grade (bolhas maiores, mais certeza na leitura).
  double frameWidth = area.width * 0.88;
  double frameHeight = frameWidth / aspect;
  if (frameHeight > area.height * 0.84) {
    frameHeight = area.height * 0.84;
    frameWidth = frameHeight * aspect;
  }
  final double left = area.left + (area.width - frameWidth) / 2;
  final double top  = area.top  + (area.height - frameHeight) / 2;
  final double pxPerMm = frameWidth / fid.wMm;
  return (
    centros: <Offset>[
      Offset(left, top),                                // TL
      Offset(left + frameWidth, top),                   // TR
      Offset(left, top + frameHeight),                  // BL
      Offset(left + frameWidth, top + frameHeight),     // BR
    ],
    pxPerMm: pxPerMm,
    rect: Rect.fromLTWH(left, top, frameWidth, frameHeight),
  );
}

/// Painter que desenha a moldura com proporções EXATAS do PDF A4
class FrameGuidePainter extends CustomPainter {
  final Color frameColor;
  final FrameAlignmentState alignmentState;
  final double skewAngle; // ângulo em graus
  final bool showAdvancedGuides;
  final int numQuestoes; // v3: define o aspecto da moldura da grade

  // ✨ CONSTANTES A4 EM MM (do PDF Django)
  static const double PAPER_WIDTH_MM = 210;
  static const double PAPER_HEIGHT_MM = 297;
  static const double CARTAO_ASPECT_RATIO = PAPER_WIDTH_MM / PAPER_HEIGHT_MM;

  // Padding externo do PDF (wrapper)
  static const double PADDING_MM = 8;

  // Marcadores de canto (4 círculos sólidos pretos)
  static const double MARKER_DIAMETER_MM = 12;  // CORRIGIDO: diâmetro real do PDF (raio 6mm × 2)
  static const double MARKER_OFFSET_MM = 12;    // CORRIGIDO: centro do marcador a 12mm do canto

  // Bolhas de respostas
  static const double BUBBLE_RESPONSE_MM = 6.5; // Alternativas A-E
  static const double BUBBLE_TYPE_MM = 8;       // Tipo de prova

  // Margens internas
  static const double INNER_MARGIN_MM = 12; // Header, footer, laterais
  static const double SAFETY_MARGIN_MM = 8; // Borda de segurança

  /// Área do preview real da câmera dentro do canvas.
  /// Fornecida pela tela de captura para evitar que os círculos-guia
  /// caiam nas barras pretas acima/abaixo do preview.
  final Rect? cameraPreviewRect;

  FrameGuidePainter({
    required this.frameColor,
    required this.alignmentState,
    required this.skewAngle,
    required this.numQuestoes,
    this.showAdvancedGuides = true,
    this.cameraPreviewRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fonte única da geometria (mesma usada pela tela para o registro).
    // v3: a moldura é o retângulo dos fiduciais (ao redor da grade); os 4 centros
    // SÃO os cantos, então o retângulo é o próprio bounding box.
    // cameraPreviewRect garante que os círculos fiquem DENTRO do preview da câmera.
    final g = molduraGeometria(size, numQuestoes,
        cameraPreviewRect: cameraPreviewRect);
    final rect = g.rect;

    _drawMolduraRetangulo(canvas, rect);                 // o retângulo (em torno da grade)
    _drawCornerRings(canvas, g.centros, g.pxPerMm);      // anéis nos 4 fiduciais
    _drawMensagem(canvas, size, rect);                   // mensagem-guia
  }

  /// Retângulo da moldura — a folha deve encaixar EXATAMENTE nessa borda. Vira verde
  /// (via frameColor) quando o cartão está registrado.
  void _drawMolduraRetangulo(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = frameColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      paint,
    );
  }

  /// Mensagem-guia acima da moldura.
  void _drawMensagem(Canvas canvas, Size size, Rect rect) {
    final tp = TextPainter(
      text: const TextSpan(
        text: '🎯 Aproxime e encaixe as 4 bolinhas em torno das colunas',
        style: TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width - 32);
    final x = (size.width - tp.width) / 2;
    final y = (rect.top - tp.height - 14).clamp(8.0, size.height);
    final bg = Paint()..color = Colors.black54;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 10, y - 5, tp.width + 20, tp.height + 10),
        const Radius.circular(8),
      ),
      bg,
    );
    tp.paint(canvas, Offset(x, y));
  }

  /// Desenha os 4 anéis-alvo (onde encaixar as bolinhas pretas do cartão).
  void _drawCornerRings(Canvas canvas, List<Offset> centros, double pxPerMm) {
    // Anel maior que o fiducial (12mm) p/ dar área de encaixe (mais fácil mirar).
    final double markerRadius = (MARKER_DIAMETER_MM / 2) * pxPerMm * 1.5;
    final ring = Paint()
      ..color = frameColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
    final centerDot = Paint()
      ..color = frameColor
      ..style = PaintingStyle.fill;
    for (final c in centros) {
      canvas.drawCircle(c, markerRadius, ring);
      canvas.drawCircle(c, 2.0, centerDot); // pontinho central p/ mirar
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

  /// Guia simplificada: APENAS os 4 círculos de canto (alvos de alinhamento).
  /// Sem retângulo, sem cantos em L, sem indicadores — o usuário sobrepõe cada
  /// bolinha preta do cartão exatamente em cima do círculo da moldura.
  void _drawAdvancedGuides(
    Canvas canvas,
    Size size,
    double left,
    double top,
    double width,
    double height,
    double pxPerMm,
  ) {
    _drawExpectedCornerMarkers(canvas, left, top, width, height, pxPerMm);
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




  /// Desenha os 4 círculos-alvo de canto (onde encaixar as bolinhas pretas).
  /// São ANÉIS (sem preenchimento) coloridos pelo estado: o usuário centraliza
  /// cada fiducial do cartão dentro do anel; vira verde quando alinhado.
  void _drawExpectedCornerMarkers(
    Canvas canvas,
    double left,
    double top,
    double width,
    double height,
    double pxPerMm,
  ) {
    // Anel um pouco maior que o fiducial (12mm) p/ a bolinha preta caber dentro.
    final double markerRadius = (MARKER_DIAMETER_MM / 2) * pxPerMm * 1.25;
    final double markerOffset = MARKER_OFFSET_MM * pxPerMm;

    final ring = Paint()
      ..color = frameColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
    final centerDot = Paint()
      ..color = frameColor
      ..style = PaintingStyle.fill;

    final corners = [
      (left + markerOffset, top + markerOffset),                    // TL
      (left + width - markerOffset, top + markerOffset),            // TR
      (left + markerOffset, top + height - markerOffset),           // BL
      (left + width - markerOffset, top + height - markerOffset),   // BR
    ];

    for (final c in corners) {
      final center = Offset(c.$1, c.$2);
      canvas.drawCircle(center, markerRadius, ring);
      canvas.drawCircle(center, 2.0, centerDot); // pontinho central p/ mirar
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
        oldDelegate.skewAngle != skewAngle ||
        oldDelegate.numQuestoes != numQuestoes ||
        oldDelegate.cameraPreviewRect != cameraPreviewRect;
  }
}
