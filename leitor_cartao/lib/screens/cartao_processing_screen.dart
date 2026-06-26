// cartao_processing_screen.dart
// Tela 3: Fotografia do Cartão com Moldura Inteligente + Flash + Captura Estável
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/image_quality_analyzer.dart';
import '../services/frame_alignment_analyzer.dart';
import '../widgets/frame_guide_painter.dart';
import 'shared_data.dart';
import 'cartao_preview_screen.dart';
import 'capture_tips_screen.dart';

/// Tela 3: Fotografia do Cartão com Moldura Inteligente
class CartaoProcessingScreen extends StatefulWidget {
  final SimuladoData simulado;
  final AlunoData aluno;
  final int tipoProva;
  final String? versionCode;
  /// Versão do LAYOUT do cartão (V: do QR). 3 = fiduciais ao redor da grade
  /// (máscara apertada na grade + deskew apertado no backend). null = v2 legado
  /// (fiduciais nos cantos da folha A4, máscara A4, caminho congelado).
  final int? cartaoVersao;

  const CartaoProcessingScreen({
    super.key,
    required this.simulado,
    required this.aluno,
    required this.tipoProva,
    this.versionCode,
    this.cartaoVersao,
  });

  @override
  State<CartaoProcessingScreen> createState() => _CartaoProcessingScreenState();
}

class _CartaoProcessingScreenState extends State<CartaoProcessingScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _hasError = false;
  String _errorMessage = '';

  // Estados para feedback ao vivo
  LiveQualityState _liveQuality = LiveQualityState.analyzing;
  String _liveTip = 'Encaixe o cartão na moldura';
  bool _isAnalyzingLive = false;

  // Estados para alinhamento
  FrameAlignmentState _frameAlignment = FrameAlignmentState.analyzing;
  double _skewAngle = 0.0;

  // ✨ NOVO: Flash
  FlashMode _currentFlashMode = FlashMode.torch; // ✨ Flash LIGADO por padrão para eliminar sombras

  // ✨ NOVO: Captura estabilizada
  int _stableFrameCount = 0;
  static const int _requiredStableFrames = 8; // ~2s com análise a cada ~250ms
  bool _isStabilized = false;

  // ✨ NOVO: Controle de dicas
  bool _showTips = true;

  // ✨ NOVO: Sugestão de flash mostrada
  bool _flashSuggestionShown = false;
  int _badFrameCount = 0;

  // Throttle do log de métricas da moldura (evita spam: ~1 log/seg)
  int _lastLiveLogMs = 0;

  // Última cobertura de papel medida (proxy de distância) — p/ calibração
  double _liveCobertura = 0;

  // Auto-disparo por REGISTRO: dispara quando os 4 fiduciais do cartão estão EM
  // CIMA dos círculos da moldura (registro), por alguns frames seguidos.
  bool _autoCaptureDone = false;
  bool _liveFiduciaisOk = false;   // pré-filtro: 4 fiduciais formando retângulo A4
  bool _liveRegistrado = false;    // fiduciais sobre os círculos da moldura
  double _liveErroReg = 1.0;       // maior distância detectado↔alvo (0-1) p/ calibração
  int _registroOkFrames = 0;

  // ALVO dos fiduciais em coords NORMALIZADAS do buffer (TL,TR,BL,BR).
  // É onde os fiduciais caem quando o cartão está na POSIÇÃO IDEAL (papel rente, reto).
  //
  // v2 (cartão antigo, fiduciais nos cantos da folha A4): posição salva calibrada
  // por aparelho (SM A256E, 23/06/2026). PERMANECE INTACTA — é o fallback.
  static const List<double> _alvoFiduciaisV2 = [
    0.06, 0.12,  // TL
    0.95, 0.09,  // TR
    0.04, 0.92,  // BL
    0.95, 0.93,  // BR
  ];

  // v3 (fiduciais ao redor da grade): alvo DERIVADO da geometria da moldura
  // (não depende mais de aparelho). Computado em _alvoFiduciaisV3Derivado().
  // Cache: recálculado quando o Stack size muda.
  List<double> _alvoFiduciaisV3Cache = const [];
  Size? _lastStackSizeForAlvo;
  double _lastCameraAspectForAlvo = 0;

  // Stack size + aspect da câmera, capturados no build (em _buildCameraWithGuide)
  // para o cálculo do alvo v3.
  Size? _stackSize;
  double _cameraAspectForAlvo = 0;

  static const double _tolRegistro = 0.12; // tolerância (fração do buffer) — maior = encaixa mais fácil

  /// Alvo ativo conforme a versão do cartão.
  /// v3 → derivado da geometria da moldura (grade).
  /// v2/legado → _alvoFiduciaisV2 (hardcoded por aparelho).
  List<double> _alvoFiduciaisAtivo() {
    if (widget.cartaoVersao == 3) {
      final derivado = _alvoFiduciaisV3Derivado();
      if (derivado.length == 8) return derivado;
    }
    return _alvoFiduciaisV2;
  }

  /// Deriva o alvo v3 no espaço do buffer da câmera a partir do retângulo da
  /// moldura desenhada no canvas. Converte canvas→buffer assumindo o caso mais
  /// comum (Android back camera: sensorOrientation=90, app em retrato, buffer
  /// landscape rotacionado 90° horária no display).
  ///
  /// Mapeamento canvas(retrato)→buffer(landscape) para rotação 90° horária:
  ///   x_buf_norm = y_disp_norm
  ///   y_buf_norm = 1 - x_disp_norm
  /// E a convenção do _detectarFiduciais (TL=menor soma, TR=maior diff,
  /// BR=maior soma, BL=menor diff) remapeia os cantos:
  ///   TL_detect ← TR_display,  TR_detect ← BR_display,
  ///   BL_detect ← TL_display,  BR_detect ← BL_display
  ///
  /// ⚠️ Se o sensor do aparelho usar rotação 270° (anti-horária), o sentido
  /// inverte — neste caso o alvo v3 não engata e o auto-disparo fica desligado
  /// (fallback: fotografe manualmente). A fórmula está isolada aqui pra ajuste.
  List<double> _alvoFiduciaisV3Derivado() {
    final stack = _stackSize;
    if (stack == null || _cameraAspectForAlvo <= 0) return const [];

    // Reaproveita o cache se nada mudou.
    if (_lastStackSizeForAlvo == stack &&
        _lastCameraAspectForAlvo == _cameraAspectForAlvo &&
        _alvoFiduciaisV3Cache.length == 8) {
      return _alvoFiduciaisV3Cache;
    }

    // displayAspect = W/H do preview em retrato (= 1/cameraAspect).
    // O AspectRatio widget tenta preencher a altura; se ultrapassar a largura, clipa.
    final cameraAspect = _cameraAspectForAlvo;
    final displayAspect = 1 / cameraAspect;
    double cameraW = stack.height * displayAspect; // tenta altura total
    double cameraH = stack.height;
    if (cameraW > stack.width) {
      // Limitado pela largura do Stack.
      cameraW = stack.width;
      cameraH = cameraW / displayAspect;
    }
    final cameraLeft = (stack.width - cameraW) / 2;
    final cameraTop = (stack.height - cameraH) / 2;

    // Área real do preview (pode ter barras pretas acima/abaixo).
    // Passamos ao molduraGeometria para que os círculos-guia fiquem DENTRO dela.
    final cameraPreviewRect =
        Rect.fromLTWH(cameraLeft, cameraTop, cameraW, cameraH);

    // Geometria da moldura v3 no canvas (retrato). Mesma fonte do painter.
    final g = molduraGeometria(stack, widget.simulado.numQuestoes,
        cameraPreviewRect: cameraPreviewRect);
    final rect = g.rect; // (left, top, width, height) no Stack

    // Rect da moldura em coords da câmera display (normalizado 0-1 na câmera).
    final rxn = (rect.left - cameraLeft) / cameraW;
    final ryn = (rect.top - cameraTop) / cameraH;
    final rwn = rect.width / cameraW;
    final rhn = rect.height / cameraH;

    // Clampa (se a moldura extrapola a câmera, algo está errado).
    if (rxn < -0.02 || ryn < -0.02 || rxn + rwn > 1.02 || ryn + rhn > 1.02) {
      return const [];
    }

    // Cantos da moldura no display (retrato), normalizados:
    //   TL_disp=(rxn, ryn), TR_disp=(rxn+rwn, ryn),
    //   BR_disp=(rxn+rwn, ryn+rhn), BL_disp=(rxn, ryn+rhn)
    // Converter display→buffer (90° horária): (xd, yd) → (xb=yd, yb=1-xd)
    // E remapear para a convenção do _detectarFiduciais:
    //   TL_detect = TR_disp = (rxn+rwn, ryn)      → (ryn, 1-rxn-rwn)
    //   TR_detect = BR_disp = (rxn+rwn, ryn+rhn)   → (ryn+rhn, 1-rxn-rwn)
    //   BL_detect = TL_disp = (rxn, ryn)          → (ryn, 1-rxn)
    //   BR_detect = BL_disp = (rxn, ryn+rhn)       → (ryn+rhn, 1-rxn)
    final alvo = <double>[
      ryn,           1 - rxn - rwn,  // TL_detect
      ryn + rhn,     1 - rxn - rwn,  // TR_detect
      ryn,           1 - rxn,        // BL_detect
      ryn + rhn,     1 - rxn,        // BR_detect
    ];

    _alvoFiduciaisV3Cache = alvo;
    _lastStackSizeForAlvo = stack;
    _lastCameraAspectForAlvo = _cameraAspectForAlvo;
    return alvo;
  }

  // ── GATE GEOMÉTRICO do disparo (além do registro): só dispara/fica verde quando a foto
  // está REALMENTE reta + centralizada + na distância certa. Sem isso o verde acendia em
  // ângulo torto (perspectiva lr~0.88, rot até 4.8°) e os extremos de coluna saíam AMBIGUA.
  //
  // ⚠️ v3 (cartaoVersao==3): a máscara enquadra SÓ a grade (não a folha A4), então a
  // cobertura de papel no buffer SOBE (a grade preenche mais a tela que a folha A4).
  // Os limites abaixo foram calibrados para v2 (folha A4). Para v3, RECALIBRAR no
  // aparelho: fotografe um cartão v3 na distância ideal e leia `cobertura` no log
  // [MOLDURA]. Ajuste _gateCoberturaMin/Max para a faixa observada (provável ~0.85-0.98).
  // Por enquanto, v3 usa os mesmos limites do v2 — se a cobertura passar de _gateCoberturaMax,
  // o auto-disparo não engata (fallback: fotografe manualmente).
  static const double _gateCoberturaMin = 0.74; // exige papel RENTE (ideal medido = 0.80-0.83)
  static const double _gateCoberturaMax = 0.95; // rejeita perto demais
  static const double _gateRotMax = 3.5;         // graus de rotação máx da borda de cima (ideal ≤3)
  static const double _gateTbMin = 0.90, _gateTbMax = 1.10; // razão topo/base (perspectiva V)
  static const double _gateLrMin = 0.82, _gateLrMax = 1.18; // razão esq/dir (perspectiva H)

  /// Geometria dos 4 fiduciais (TL,TR,BL,BR) p/ o log: o quanto a foto está inclinada.
  /// tb = razão lado-de-cima/lado-de-baixo, lr = esq/dir (1.00 = plano; >1 = perspectiva),
  /// rot = rotação da borda de cima em graus. Quanto mais longe de 1.00/0°, mais torto.
  String _geoFiduciais(List<double> p) {
    if (p.length < 8) return 'tb=- lr=- rot=-';
    double d(int a, int b) {
      final dx = p[a] - p[b], dy = p[a + 1] - p[b + 1];
      return math.sqrt(dx * dx + dy * dy);
    }
    final top = d(0, 2), bottom = d(4, 6), left = d(0, 4), right = d(2, 6);
    final tb = top / (bottom == 0 ? 1e-6 : bottom);
    final lr = left / (right == 0 ? 1e-6 : right);
    final rot = (math.atan2(p[3] - p[1], p[2] - p[0]) * 180 / math.pi).abs();
    return 'tb=${tb.toStringAsFixed(2)} lr=${lr.toStringAsFixed(2)} '
        'rot=${rot.toStringAsFixed(1)}';
  }

  /// Gate geométrico: a foto está reta (tb/lr ~1, rot baixo) e na distância certa
  /// (cobertura na faixa)? Só então vale como "registrado" p/ ficar verde e disparar.
  bool _geoGateOk(List<double> p, double cobertura) {
    if (p.length < 8) return false;
    double d(int a, int b) {
      final dx = p[a] - p[b], dy = p[a + 1] - p[b + 1];
      return math.sqrt(dx * dx + dy * dy);
    }
    final top = d(0, 2), bottom = d(4, 6), left = d(0, 4), right = d(2, 6);
    if (bottom == 0 || right == 0) return false;
    final tb = top / bottom;
    final lr = left / right;
    final rot = (math.atan2(p[3] - p[1], p[2] - p[0]) * 180 / math.pi).abs();
    return cobertura >= _gateCoberturaMin && cobertura <= _gateCoberturaMax &&
        rot <= _gateRotMax &&
        tb >= _gateTbMin && tb <= _gateTbMax &&
        lr >= _gateLrMin && lr <= _gateLrMax;
  }

  /// Maior distância entre cada fiducial detectado e seu alvo (0-1). 1.0 se inválido.
  double _erroRegistro(List<double> pts) {
    if (pts.length < 8) return 1.0;
    final alvo = _alvoFiduciaisAtivo();
    if (alvo.length < 8) return 1.0;
    double maxD = 0.0;
    for (int i = 0; i < 4; i++) {
      final double dx = pts[i * 2] - alvo[i * 2];
      final double dy = pts[i * 2 + 1] - alvo[i * 2 + 1];
      final double d = math.sqrt(dx * dx + dy * dy);
      if (d > maxD) maxD = d;
    }
    return maxD;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkTips();
  }

  Future<void> _checkTips() async {
    final prefs = await SharedPreferences.getInstance();
    final jaViu = prefs.getBool('capture_tips_seen') ?? false;
    if (jaViu) {
      if (mounted) setState(() => _showTips = false);
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.stopImageStream().catchError((_) {});
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Nenhuma câmera encontrada';
        });
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.max, // ✨ CORRIGIDO: era 'high' (720p) — muito baixo para OMR
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      if (_controller!.value.isInitialized) {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setFlashMode(_currentFlashMode);
        _startLiveQualityAnalysis();

        // ✨ Re-aplica o torch DEPOIS que o stream já está rodando (vários Android não
        // engatam o LED se setFlashMode é chamado antes do stream ativo / após restart).
        _reaplicarTorchComAtraso();
      }

      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _hasError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Erro ao iniciar câmera: $e';
        });
      }
    }
  }

  /// Re-aplica o torch algumas vezes com atraso. Necessário porque o restart do stream /
  /// a reconfiguração da sessão da câmera APAGA o LED no A256E (o ícone fica "ligado" mas
  /// a luz não sai). Re-aplicar com o stream já ativo religa o LED de verdade.
  void _reaplicarTorchComAtraso() {
    if (_currentFlashMode == FlashMode.off) return;
    for (final ms in const [350, 900, 1600]) {
      Future.delayed(Duration(milliseconds: ms), () async {
        if (!mounted ||
            _controller == null ||
            !_controller!.value.isInitialized ||
            _currentFlashMode == FlashMode.off) return;
        try {
          await _controller!.setFlashMode(_currentFlashMode);
        } catch (_) {}
      });
    }
  }

  void _startLiveQualityAnalysis() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      _controller!.startImageStream(_onFrameReceived).catchError((e) {
        print('❌ Erro ao iniciar stream: $e');
      });
    } catch (e) {
      print('❌ Erro ao iniciar stream: $e');
    }
  }

  Future<void> _onFrameReceived(CameraImage frame) async {
    if (_isAnalyzingLive || _isCapturing) return;

    _isAnalyzingLive = true;

    try {
      final lumaBytes = frame.planes[0].bytes;
      final width = frame.width;
      final height = frame.height;

      // Executar análise rápida em isolate para não travar a UI
      final metrics = await compute(
        _analyzeLiveFrameInIsolate,
        _FrameAnalysisData(lumaBytes, width, height,
            numQuestoes: widget.simulado.numQuestoes,
            cartaoVersao: widget.cartaoVersao),
      );
      final liveState = metrics.state;

      // REGISTRO: os 4 fiduciais detectados estão sobre os círculos da moldura?
      final double erroReg = _erroRegistro(metrics.fiduciaisPontos);
      final bool geoOk = _geoGateOk(metrics.fiduciaisPontos, metrics.coberturaPapel);
      final bool registrado = metrics.fiduciaisOk && erroReg < _tolRegistro && geoOk;
      if (registrado) {
        _registroOkFrames++;
      } else {
        _registroOkFrames = 0;
      }

      // LOG (throttle ~1/seg) — inclui os pts detectados para CALIBRAR o alvo.
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastLiveLogMs >= 1000) {
        _lastLiveLogMs = nowMs;
        final pts = metrics.fiduciaisPontos
            .map((v) => v.toStringAsFixed(2))
            .join(',');
        final alvoAtivo = _alvoFiduciaisAtivo();
        final alvoStr = alvoAtivo.length == 8
            ? alvoAtivo.map((v) => v.toStringAsFixed(2)).join(',')
            : 'fallback-v2';
        final rot = widget.cartaoVersao == 3 ? 'v3' : 'v2';
        print('📐 [MOLDURA] frame=${width}x$height $metrics '
            '| registro=${registrado ? "OK" : "nao"} err=${erroReg.toStringAsFixed(2)} '
            '| geo_ok=$geoOk geo(${_geoFiduciais(metrics.fiduciaisPontos)}) '
            '| pts=[$pts] alvo_$rot=[$alvoStr] | flash=${_currentFlashMode.name}');
      }

      if (mounted) {
        setState(() {
          _liveCobertura = metrics.coberturaPapel;
          _liveFiduciaisOk = metrics.fiduciaisOk;
          _liveRegistrado = registrado;
          _liveErroReg = erroReg;
          _liveQuality = liveState;
          _liveTip =
              ImageQualityAnalyzer.getTipForLiveQualityState(liveState);

          // ✨ NOVO: Contar frames estáveis consecutivos
          if (liveState == LiveQualityState.excellent ||
              liveState == LiveQualityState.good) {
            _stableFrameCount++;
            if (_stableFrameCount >= _requiredStableFrames) {
              _isStabilized = true;
            }
          } else {
            _stableFrameCount = 0;
            _isStabilized = false;
          }

          // ✨ NOVO: Sugerir flash se muitos frames ruins
          if (liveState == LiveQualityState.bad) {
            _badFrameCount++;
            if (_badFrameCount >= 10 && !_flashSuggestionShown && _currentFlashMode == FlashMode.off) {
              _flashSuggestionShown = true;
              _suggestFlash();
            }
          } else {
            _badFrameCount = 0;
          }
        });
      }

      // ✨ AUTO-DISPARO POR REGISTRO: dispara quando os 4 fiduciais ficam SOBRE os
      // círculos da moldura (registro) por alguns frames seguidos.
      // Religado: o alvo (_alvoFiduciais) agora é a POSIÇÃO IDEAL salva, então o auto-disparo
      // trava exatamente nesse enquadramento. Pra testar posições no manual, ponha false.
      const bool autoDisparoHabilitado = true;
      const int framesRegistroParaAuto = 8; // ~2s registrado antes de disparar
      if (autoDisparoHabilitado &&
          _registroOkFrames >= framesRegistroParaAuto &&
          _currentFlashMode != FlashMode.off &&
          !_isCapturing &&
          !_autoCaptureDone) {
        _autoCaptureDone = true;
        print('🤖 [AUTO] Fiduciais registrados na moldura '
            '(${_registroOkFrames} frames, err=${_liveErroReg.toStringAsFixed(2)}) — disparando');
        _capturarFoto();
      }
    } catch (e) {
      print('❌ Erro ao analisar frame: $e');
    } finally {
      _isAnalyzingLive = false;
    }
  }

  /// Função estática para rodar em isolate
  static LiveFrameMetrics _analyzeLiveFrameInIsolate(
    _FrameAnalysisData data,
  ) {
    return ImageQualityAnalyzer.analyzeLiveFrameFastMetrics(
      data.lumaBytes,
      data.width,
      data.height,
      numQuestoes: data.numQuestoes,
      cartaoVersao: data.cartaoVersao,
    );
  }

  /// ✨ NOVO: Sugerir ativação do flash ao usuário
  void _suggestFlash() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.flash_on_rounded, color: Colors.yellow, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ambiente escuro detectado! Ative o flash para melhor leitura.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'ATIVAR',
          textColor: Colors.yellow,
          onPressed: () => _setFlashMode(FlashMode.torch),
        ),
      ),
    );
  }

  /// ✨ NOVO: Alternar modo de flash (OFF → TORCH → AUTO → OFF)
  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    FlashMode nextMode;
    switch (_currentFlashMode) {
      case FlashMode.off:
        nextMode = FlashMode.torch;
        break;
      case FlashMode.torch:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.off;
        break;
      default:
        nextMode = FlashMode.off;
    }

    await _setFlashMode(nextMode);
  }

  Future<void> _setFlashMode(FlashMode mode) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    await _controller!.setFlashMode(mode);
    setState(() {
      _currentFlashMode = mode;
      _badFrameCount = 0;
    });
  }

  /// Obter ícone baseado no modo de flash
  IconData _getFlashIcon() {
    switch (_currentFlashMode) {
      case FlashMode.off:
        return Icons.flash_off_rounded;
      case FlashMode.torch:
        return Icons.flash_on_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      default:
        return Icons.flash_off_rounded;
    }
  }

  /// Obter label do flash
  String _getFlashLabel() {
    switch (_currentFlashMode) {
      case FlashMode.off:
        return 'OFF';
      case FlashMode.torch:
        return 'ON';
      case FlashMode.auto:
        return 'AUTO';
      default:
        return 'OFF';
    }
  }

  // Cor da moldura, simples e estável:
  // VERDE só quando os 4 fiduciais estão alinhados (= vai disparar);
  // VERMELHO quando está escuro demais; LARANJA enquanto posiciona.
  // (Antes, "good" também era verde → ficava verde "do nada" antes de alinhar.)
  Color get _frameColor {
    if (_liveQuality == LiveQualityState.bad) {
      return const Color(0xFFEF4444); // vermelho — muito escuro
    }
    if (_registroOkFrames >= 2 && _currentFlashMode != FlashMode.off) {
      return const Color(0xFF22C55E); // verde — fiduciais SOBRE os círculos da moldura
    }
    return const Color(0xFFF59E0B); // laranja — posicionando
  }

  // PRONTO = fiduciais registrados sobre os círculos da moldura + flash ligado.
  bool get _isReadyToCapture =>
      _liveRegistrado && _currentFlashMode != FlashMode.off;

  // Mensagem-guia que reflete o ESTADO REAL (flash → registro → pronto).
  String get _mensagemGuia {
    if (_currentFlashMode == FlashMode.off) {
      return '🔦 Ligue o flash para leitura perfeita';
    }
    if (_liveQuality == LiveQualityState.bad) {
      return '🔦 Muito escuro — melhore a luz';
    }
    if (_isReadyToCapture) {
      return '✅ Encaixado — disparando...';
    }
    return '⊡ Encaixe os 4 cantos do cartão nos círculos';
  }

  Future<void> _capturarFoto() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) return;

    setState(() => _isCapturing = true);

    // Estado do flash NO MOMENTO do disparo (antes de desligar) — p/ log correto
    final String flashNoDisparo = _currentFlashMode.name;

    try {
      await _controller!.stopImageStream().catchError((_) {});

      final XFile foto = await _controller!.takePicture();

      // ✨ Desliga o torch ao sair da tela de captura (preview/resultado não precisam de luz).
      // No "Refazer" (Navigator.pop de volta pra cá) o bloco de RE-ARME abaixo religa o torch
      // — por isso agora pode desligar sem deixar o retake no escuro.
      await _controller!.setFlashMode(FlashMode.off);
      if (mounted) setState(() => _currentFlashMode = FlashMode.off);

      final dir = await getTemporaryDirectory();
      final String novoPath = path.join(
        dir.path,
        'cartao_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final File arquivoFinal = await File(foto.path).copy(novoPath);

      // ✨ DEBUG v3: salva uma CÓPIA acessível da foto na pasta Documents do app
      // para diagnóstico via `adb pull` ou gerenciador de arquivos. Só ativa quando
      // v3 (cartaoVersao==3) — em v2 não polui o storage. Remover após calibrar.
      if (widget.cartaoVersao == 3) {
        try {
          final docsDir = await getApplicationDocumentsDirectory();
          final String debugPath = path.join(
            docsDir.path,
            'debug_v3_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          await File(foto.path).copy(debugPath);
          print('🔬 [DEBUG-v3] cópia acessível salva: $debugPath');
        } catch (e) {
          print('⚠️ [DEBUG-v3] falhou ao salvar cópia: $e');
        }
      }

      // LOG: foto que será enviada ao servidor (tamanho aproxima a resolução real).
      final int tamBytes = await arquivoFinal.length();
      print('📸 [CAPTURA] foto salva: ${(tamBytes / 1024).toStringAsFixed(0)}KB '
          '| qualidade_ultima_moldura=${_liveQuality.name} '
          '| cobertura=${_liveCobertura.toStringAsFixed(2)} '
          '| estabilizada=$_isStabilized | flash=$flashNoDisparo '
          '| path=$novoPath');

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CartaoPreviewScreen(
              imageFile: arquivoFinal,
              simulado: widget.simulado,
              aluno: widget.aluno,
              tipoProva: widget.tipoProva,
              versionCode: widget.versionCode,
              cartaoVersao: widget.cartaoVersao,
            ),
          ),
        );

        // ✨ Voltou da pré-visualização (ex.: "Refazer" faz Navigator.pop pra ESTA tela).
        // Re-arma a captura: o stream foi parado e _autoCaptureDone/_isCapturing ficaram
        // travados — sem isto o retake fica numa tela morta (sem análise/auto-disparo/flash).
        if (mounted) {
          setState(() {
            _isCapturing = false;
            _autoCaptureDone = false;
            _registroOkFrames = 0;
            _stableFrameCount = 0;
            _isStabilized = false;
            _currentFlashMode = FlashMode.torch;
          });
          try {
            _startLiveQualityAnalysis(); // reinicia o stream de análise ao vivo
            // Re-aplica o torch DEPOIS do restart (o restart da sessão apaga o LED).
            _reaplicarTorchComAtraso();
          } catch (_) {}
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _hasError = true;
          _errorMessage = 'Erro ao capturar: $e';
        });
      }
    }
  }

  /// ✨ NOVO: Callback quando dicas são fechadas → salvar flag + iniciar câmera
  void _onTipsClosed() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('capture_tips_seen', true);
    });
    setState(() {
      _showTips = false;
    });
    _initCamera();
  }

  @override
  Widget build(BuildContext context) {
    // ✨ NOVO: Mostrar dicas primeiro
    if (_showTips) {
      return CaptureTipsScreen(onContinue: _onTipsClosed);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A2E), size: 20),
        ),
        title: RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'SIMULADO',
                style: TextStyle(color: Color(0xFF1A1A2E), fontSize: 16, fontWeight: FontWeight.w900),
              ),
              TextSpan(
                text: 'APP',
                style: TextStyle(color: Color(0xFF0DA6F2), fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
        actions: [
          _buildFlashButton(),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: SafeArea(
        child: _hasError
            ? _buildErrorView()
            : !_isCameraReady
                ? _buildLoadingView()
                : _buildCameraWithGuide(),
      ),
    );
  }

  /// ✨ NOVO: Botão de flash no AppBar
  Widget _buildFlashButton() {
    final isOn = _currentFlashMode != FlashMode.off;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: _toggleFlash,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isOn
                ? const Color(0xFFFEF9C3)
                : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isOn ? const Color(0xFFFBBF24) : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getFlashIcon(),
                color: isOn ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF),
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                _getFlashLabel(),
                style: TextStyle(
                  color: isOn ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF0DA6F2)),
            SizedBox(height: 16),
            Text(
              'Iniciando câmera...',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _isCameraReady = false;
                  });
                  _initCamera();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0DA6F2),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Tentar novamente', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraWithGuide() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cameraAspect = _controller!.value.aspectRatio;
        final displayAspect = 1 / cameraAspect;

        // Captura o tamanho do Stack + aspect da câmera para o cálculo do
        // alvo v3 (derivado da geometria da moldura).
        _stackSize = Size(constraints.maxWidth, constraints.maxHeight);
        _cameraAspectForAlvo = cameraAspect;

        // Área real do preview (pode ter barras pretas acima/abaixo).
        final double screenW = constraints.maxWidth;
        final double screenH = constraints.maxHeight;
        final Rect camPreviewRect;
        if (displayAspect * screenH <= screenW) {
          final double pw = screenH * displayAspect;
          camPreviewRect = Rect.fromLTWH((screenW - pw) / 2, 0, pw, screenH);
        } else {
          final double ph = screenW / displayAspect;
          camPreviewRect =
              Rect.fromLTWH(0, (screenH - ph) / 2, screenW, ph);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // CÂMERA AO VIVO
            Center(
              child: AspectRatio(
                aspectRatio: displayAspect,
                child: CameraPreview(_controller!),
              ),
            ),

            // MOLDURA INTELIGENTE (com guias de canto)
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: FrameGuidePainter(
                frameColor: _frameColor,
                alignmentState: _frameAlignment,
                skewAngle: _skewAngle,
                numQuestoes: widget.simulado.numQuestoes,
                showAdvancedGuides: true,
                cameraPreviewRect: camPreviewRect,
              ),
            ),

            // ✨ STATUS BADGE (TOPO) com indicador de estabilização
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: _buildStatusBadge(),
            ),

            // DICA DINÂMICA (BASE)
            Positioned(
              bottom: 80,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _liveQuality == LiveQualityState.bad
                          ? Icons.warning_rounded
                          : _liveQuality == LiveQualityState.warning
                              ? Icons.info_rounded
                              : Icons.wb_sunny_outlined,
                      color: _frameColor,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _mensagemGuia,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // BOTÃO DE CAPTURA (com indicador de estabilização)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: _buildCaptureButton(),
            ),
          ],
        );
      },
    );
  }

  /// ✨ NOVO: Badge de status com barra de estabilização
  Widget _buildStatusBadge() {
    final badgeColor = _isReadyToCapture
        ? const Color(0xFF22C55E)
        : _liveQuality == LiveQualityState.bad
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);

    final progress = _isStabilized
        ? 1.0
        : (_stableFrameCount / _requiredStableFrames).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor.withOpacity(0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isReadyToCapture
                    ? Icons.check_circle_rounded
                    : _isStabilized
                        ? Icons.schedule_rounded
                        : Icons.pending_rounded,
                color: badgeColor,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                _isReadyToCapture
                    ? '✅ Cartão alinhado — disparando...'
                    : _currentFlashMode == FlashMode.off
                        ? '🔦 Ligue o flash para leitura perfeita'
                        : _liveQuality == LiveQualityState.bad
                            ? '🔦 Ative o flash ou melhore a luz'
                            : 'Encaixe os 4 cantos do cartão na moldura',
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          // Barra de progresso de estabilização
          if (!_isStabilized && _stableFrameCount > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ✨ NOVO: Botão de captura com estado visual
  Widget _buildCaptureButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _isCapturing ? null : _capturarFoto,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _isReadyToCapture
                    ? const Color(0xFF22C55E)
                    : Colors.white30,
                width: 4,
              ),
              color: _isCapturing
                  ? Colors.grey.shade700
                  : _isReadyToCapture
                      ? Colors.white.withOpacity(0.3)
                      : Colors.white.withOpacity(0.1),
            ),
            child: _isCapturing
                ? const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isReadyToCapture
                            ? Colors.white
                            : Colors.white38,
                      ),
                      child: _isReadyToCapture
                          ? const Icon(
                              Icons.camera_alt_rounded,
                              color: Color(0xFF22C55E),
                              size: 28,
                            )
                          : const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.white54,
                              size: 24,
                            ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Dados para enviar ao isolate
class _FrameAnalysisData {
  final List<int> lumaBytes;
  final int width;
  final int height;
  final int numQuestoes;
  final int? cartaoVersao;
  _FrameAnalysisData(this.lumaBytes, this.width, this.height,
      {this.numQuestoes = 0, this.cartaoVersao});
}
