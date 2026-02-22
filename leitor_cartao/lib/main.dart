import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert' show utf8, latin1, jsonDecode, json, base64Decode;
import 'package:logging/logging.dart' show Logger;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'screens/cartao_resposta_preview_screen.dart';
import 'screens/camera_capture_screen.dart';
import 'screens/selection_screen.dart';
import 'services/credit_manager.dart';
import 'screens/loja_creditos_screen.dart';

// Importar a tela de login
import 'screens/login_screen.dart';
// Importar o serviço de API
import 'services/api_service.dart';
import 'widgets/custom_app_bar.dart';

final Logger _logger = Logger('CartaoRespostaApp');
final ApiService _apiService = ApiService();

// Paleta de cores do site Django
class AppColors {
  static const Color primaryColor = Color(0xFF0DA6F2);  // Azul claro/primário
  static const Color secondaryColor = Color(0xFF003D5C); // Azul escuro
  static const Color bgDark = Color(0xFF121E25);        // Azul escuro (fundo do mockup - modo escuro)
  static const Color bgLight = Color(0xFFF8FAFC);       // Cinza super claro (fundo do mockup - modo claro)
  static const Color bgSurface = Color(0xFF1A2A33);     // Azul escuro acinzentado (cards - modo escuro)
  static const Color bgSurfaceLight = Color(0xFFFFFFFF);// Cards modo claro
  static const Color borderColor = Color(0xFFDBE2E6);   // Cinza claro (bordas)
  static const Color textLight = Color(0xFFF8FAFC);     // Texto claro
  static const Color textMuted = Color(0xFF94A3B8);     // Slate 400
  static const Color successColor = Color(0xFF16A34A);  // Verde
  static const Color dangerColor = Color(0xFFEF4444);   // Vermelho
  static const Color warningColor = Color(0xFFF2A93B);  // Aviso
}

int? _parseTipoProvaFromQr(String? data) {
  if (data == null || data.trim().isEmpty) return null;
  final raw = data.trim();

  final matchTipo = RegExp(r'T\s*[:=]\s*(\d+)', caseSensitive: false)
      .firstMatch(raw);
  if (matchTipo != null) {
    return int.tryParse(matchTipo.group(1)!);
  }

  final matchLabel =
      RegExp(r'\bTIPO\s*(\d+)\b', caseSensitive: false).firstMatch(raw);
  if (matchLabel != null) {
    return int.tryParse(matchLabel.group(1)!);
  }

  if (RegExp(r'^\d+$').hasMatch(raw)) {
    return int.tryParse(raw);
  }

  return null;
}

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _controller;
  bool _found = false;
  String? _lastCode;
  String? _errorMessage;

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      _controller?.pauseCamera();
    }
    _controller?.resumeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    _controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (_found) return;
      final code = scanData.code;
      final tipo = _parseTipoProvaFromQr(code);
      if (tipo != null && tipo >= 1 && tipo <= 5) {
        _found = true;
        _controller?.pauseCamera();
        Navigator.pop(context, tipo);
      } else {
        setState(() {
          _lastCode = code;
          _errorMessage = 'QR lido, mas não contém o tipo da prova.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.black,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Ler QR do Cartão-Resposta',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Pular',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  QRView(
                    key: _qrKey,
                    onQRViewCreated: _onQRViewCreated,
                    overlay: QrScannerOverlayShape(
                      borderColor: AppColors.primaryColor,
                      borderRadius: 8,
                      borderLength: 24,
                      borderWidth: 4,
                      cutOutSize: 240,
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Aponte para o QR Code no topo do cartão.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AppColors.warningColor,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          if (_lastCode != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Lido: $_lastCode',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  runApp(const CartaoRespostaApp());
}

class CartaoRespostaApp extends StatefulWidget {
  const CartaoRespostaApp({super.key});

  @override
  State<CartaoRespostaApp> createState() => _CartaoRespostaAppState();
}

class _CartaoRespostaAppState extends State<CartaoRespostaApp> {
  @override
  void initState() {
    super.initState();
    _initializeCreditSystem();
  }

  Future<void> _initializeCreditSystem() async {
    try {
      await CreditManager().initializePurchases();
      _logger.info('✅ Sistema de compras inicializado');
    } catch (e) {
      _logger.severe('❌ Erro ao inicializar compras: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimuladoApp',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scaffoldBackgroundColor: AppColors.bgLight,
        cardTheme: CardTheme(
          color: AppColors.bgSurfaceLight,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.borderColor, width: 1),
          ),
        ),
      ),
      home: const AuthenticationWrapper(),
      routes: {
        '/loja-creditos': (context) => const LojaCreditosScreen(),
      },
    );
  }
}

// Classe para verificar a autenticação do usuário
class AuthenticationWrapper extends StatefulWidget {
  const AuthenticationWrapper({super.key});

  @override
  State<AuthenticationWrapper> createState() => _AuthenticationWrapperState();
}

class _AuthenticationWrapperState extends State<AuthenticationWrapper> {
  bool _checkingAuth = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');

    setState(() {
      _isAuthenticated = accessToken != null;
      _checkingAuth = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) {
      return const Scaffold(
        backgroundColor: AppColors.bgLight,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryColor,
          ),
        ),
      );
    }

    if (_isAuthenticated) {
      return const SelectionScreen();
    } else {
      return const LoginScreen();
    }
  }
}

class TelaInicial extends StatefulWidget {
  final int turmaId;
  final int simuladoId;
  final int alunoId;
  final Map<String, dynamic> aluno;
  final Map<String, dynamic> simulado;
  final Map<String, dynamic>? turma; // ADICIONADO

  const TelaInicial({
    super.key,
    required this.turmaId,
    required this.simuladoId,
    required this.alunoId,
    required this.aluno,
    required this.simulado,
    this.turma, // ADICIONADO
  });

  @override
  State<TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<TelaInicial> {
  File? _imagemSelecionada;
  bool _enviando = false;
  String? _mensagemErro;

  // Variáveis para dados do simulado
  bool _carregandoSimulado = true;
  int? _numeroQuestoes;
  double? _pontuacaoTotal; // Vem do Django
  String _tituloSimulado = '';
  String _nomeAluno = '';

  Uint8List? _imagemOriginalProcessada;
  bool _temImagensProcessadas = false;

  final TextEditingController _enderecoIPController =
      TextEditingController(text: "192.168.1.10:8000");
  int _tipoProva = 1;

  // ✅ ADICIONAR ESTA LINHA
  final CreditManager _creditManager = CreditManager();

  Future<int?> _lerTipoProvaViaQr() async {
    final tipoDetectado = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (context) => const QrScanScreen(),
      ),
    );

    if (tipoDetectado != null &&
        tipoDetectado >= 1 &&
        tipoDetectado <= 5 &&
        mounted) {
      setState(() {
        _tipoProva = tipoDetectado;
      });
    }

    return tipoDetectado;
  }

  String _decodificarTexto(String? texto) {
    if (texto == null || texto.isEmpty) return '';

    // Decodificar caracteres HTML/UTF-8 comuns
    String textoDecodificado = texto
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&aacute;', 'á')
        .replaceAll('&Aacute;', 'Á')
        .replaceAll('&agrave;', 'à')
        .replaceAll('&Agrave;', 'À')
        .replaceAll('&acirc;', 'â')
        .replaceAll('&Acirc;', 'Â')
        .replaceAll('&atilde;', 'ã')
        .replaceAll('&Atilde;', 'Ã')
        .replaceAll('&eacute;', 'é')
        .replaceAll('&Eacute;', 'É')
        .replaceAll('&ecirc;', 'ê')
        .replaceAll('&Ecirc;', 'Ê')
        .replaceAll('&iacute;', 'í')
        .replaceAll('&Iacute;', 'Í')
        .replaceAll('&oacute;', 'ó')
        .replaceAll('&Oacute;', 'Ó')
        .replaceAll('&ocirc;', 'ô')
        .replaceAll('&Ocirc;', 'Ô')
        .replaceAll('&otilde;', 'õ')
        .replaceAll('&Otilde;', 'Õ')
        .replaceAll('&uacute;', 'ú')
        .replaceAll('&Uacute;', 'Ú')
        .replaceAll('&ccedil;', 'ç')
        .replaceAll('&Ccedil;', 'Ç')
        .replaceAll('&ntilde;', 'ñ')
        .replaceAll('&Ntilde;', 'Ñ');

    // Tentar decodificar UTF-8 se necessário
    try {
      // Se o texto contém sequências como "Ã§Ã£o"
      if (textoDecodificado.contains('Ã')) {
        List<int> bytes = latin1.encode(textoDecodificado);
        textoDecodificado = utf8.decode(bytes, allowMalformed: true);
      }
    } catch (e) {
      // Se falhar, manter o texto original
      if (kDebugMode) {
        print('Erro ao decodificar UTF-8: $e');
      }
    }

    return textoDecodificado.trim();
  }

  @override
  void initState() {
    super.initState();
    _inicializarDados();
    // ✅ ADICIONAR ESTA LINHA
    _checkPendingPurchases();
  }

// ✅ ADICIONAR ESTE MÉTODO
  Future<void> _checkPendingPurchases() async {
    await _creditManager.checkPendingPurchases();
  }

  // Inicializar dados
  Future<void> _inicializarDados() async {
    // Carregar dados básicos primeiro
    String nomeOriginal =
        widget.aluno['nome'] ?? widget.aluno['name'] ?? 'Aluno';
    String tituloOriginal = widget.simulado['titulo'] ?? 'Simulado';

    _nomeAluno = _decodificarTexto(nomeOriginal);
    _tituloSimulado = _decodificarTexto(tituloOriginal);

    _logger.info('Nome do aluno decodificado: $_nomeAluno');
    _logger.info('Título do simulado decodificado: $_tituloSimulado');

    // Carregar detalhes do simulado se disponível
    await _carregarDadosSimulado();
  }

  // Carregar dados do simulado do Django
  Future<void> _carregarDadosSimulado() async {
    setState(() {
      _carregandoSimulado = true;
      _mensagemErro = null;
    });

    try {
      if (widget.simuladoId > 0) {
        _logger.info('Carregando detalhes do simulado ${widget.simuladoId}...');

        // Buscar detalhes completos do simulado
        final detalhes =
            await _apiService.getSimuladoDetalhes(widget.simuladoId);

        if (detalhes != null && mounted) {
          setState(() {
            _numeroQuestoes =
                detalhes['numero_questoes'] ?? detalhes['total_questoes'];
            // Converter para double - o Django retorna um inteiro
            _pontuacaoTotal = (detalhes['pontuacao_total'] ?? 10).toDouble();

            String tituloApi = detalhes['titulo'] ?? _tituloSimulado;
            _tituloSimulado = _decodificarTexto(tituloApi);

            _carregandoSimulado = false;
          });

          _logger.info('Simulado carregado: $_tituloSimulado');
          _logger.info('Número de questões: $_numeroQuestoes');
          _logger.info('Pontuação total: $_pontuacaoTotal');
        } else {
          // Fallback - tentar buscar simulado básico
          _logger.warning(
              'Detalhes não encontrados, tentando buscar simulado básico...');
          final response = await _apiService
              .authorizedRequest('/api/simulados/${widget.simuladoId}/');

          if (response.statusCode == 200) {
            final simuladoData = jsonDecode(response.body);
            setState(() {
              _numeroQuestoes = simuladoData['questoes']?.length ?? 10;
              _pontuacaoTotal =
                  (simuladoData['pontuacao_total'] ?? 10).toDouble();

              String tituloFallback = simuladoData['titulo'] ?? _tituloSimulado;
              _tituloSimulado = _decodificarTexto(tituloFallback);

              _carregandoSimulado = false;
            });
            _logger.info(
                'Simulado carregado via fallback: $_numeroQuestoes questões');
          } else {
            throw Exception('Não foi possível carregar os dados do simulado');
          }
        }
      } else {
        // Sem simulado selecionado - usar valores padrão
        setState(() {
          _numeroQuestoes = 10;
          _pontuacaoTotal = 10.0;
          _carregandoSimulado = false;
        });
        _logger.warning('Nenhum simulado selecionado, usando valores padrão');
      }
    } catch (e) {
      setState(() {
        _mensagemErro = 'Erro ao carregar simulado: $e';
        _numeroQuestoes = 10; // Fallback
        _pontuacaoTotal = 10.0; // Fallback
        _carregandoSimulado = false;
      });
      _logger.severe('Erro ao carregar simulado: $e');
    }
  }

  /// Abre a tela de captura guiada com overlay de enquadramento
  Future<void> _iniciarFluxoLeitura() async {
    try {
      // ✅ Verificar créditos antes de iniciar o fluxo
      final availableCredits = await _creditManager.getAvailableCredits();
      if (availableCredits <= 0) {
        await CreditManager.showInsufficientCreditsDialog(
          // ignore: use_build_context_synchronously
          context,
          currentCredits: availableCredits,
          onBuyCredits: () {
            Navigator.pushNamed(context, '/loja-creditos');
          },
        );
        return;
      }

      if (_numeroQuestoes == null) {
        setState(() {
          _mensagemErro =
              "Número de questões não definido. Tente recarregar o simulado.";
        });
        return;
      }

      setState(() {
        _mensagemErro = null;
      });

      // ✅ Primeiro lê o QR Code do cartão para definir o tipo de prova
      final tipoLido = await _lerTipoProvaViaQr();
      if (tipoLido == null) {
        setState(() {
          _mensagemErro = "Leitura do QR cancelada ou inválida.";
        });
        return;
      }

      final result = await Navigator.push<CaptureResult>(
        context,
        MaterialPageRoute(
          builder: (context) => CameraCaptureScreen(
            numQuestoes: _numeroQuestoes ?? 24,
            tipoProva: tipoLido,
          ),
        ),
      );

      if (result != null) {
        setState(() {
          _imagemSelecionada = result.imageFile;
          _mensagemErro = null;
          _temImagensProcessadas = false;
          _tipoProva = tipoLido;
        });
        await _enviarImagem();
      } else {
        setState(() {
          _mensagemErro = "Captura cancelada.";
        });
      }
    } catch (e) {
      setState(() {
        _mensagemErro = "Erro no fluxo de leitura: $e";
      });
    }
  }

  // Função para obter o gabarito da API baseado no tipo de prova
  Future<Map<String, String>?> _obterGabarito() async {
    try {
      if (widget.simuladoId <= 0) {
        return _getGabaritoLocal();
      }

      final gabarito = await _apiService.getGabarito(
        widget.simuladoId,
        tipo: _tipoProva.toString(),
      );

      if (gabarito != null) {
        _logger.info('Gabarito obtido da API: $gabarito');
        return gabarito;
      } else {
        _logger.warning('Falha ao obter gabarito da API, usando local');
        return _getGabaritoLocal();
      }
    } catch (e) {
      _logger.severe('Erro ao obter gabarito: $e');
      return _getGabaritoLocal();
    }
  }

  // Gabarito local usando _numeroQuestoes
  Map<String, String> _getGabaritoLocal() {
    int numQuestoes = _numeroQuestoes ?? 10;
    Map<String, String> gabarito = {};

    switch (_tipoProva) {
      case 1:
        final respostas = ['D', 'D', 'D', 'C', 'C', 'B', 'D', 'C', 'D', 'D'];
        for (int i = 0; i < numQuestoes && i < respostas.length; i++) {
          gabarito[(i + 1).toString()] = respostas[i];
        }
        break;
      case 2:
        final respostas = ['C', 'C', 'C', 'B', 'B', 'A', 'C', 'B', 'C', 'C'];
        for (int i = 0; i < numQuestoes && i < respostas.length; i++) {
          gabarito[(i + 1).toString()] = respostas[i];
        }
        break;
      case 3:
        final respostas = ['B', 'B', 'B', 'A', 'A', 'E', 'B', 'A', 'B', 'B'];
        for (int i = 0; i < numQuestoes && i < respostas.length; i++) {
          gabarito[(i + 1).toString()] = respostas[i];
        }
        break;
      case 4:
        final respostas = ['A', 'A', 'A', 'E', 'E', 'D', 'A', 'E', 'A', 'A'];
        for (int i = 0; i < numQuestoes && i < respostas.length; i++) {
          gabarito[(i + 1).toString()] = respostas[i];
        }
        break;
      case 5:
        final respostas = ['E', 'E', 'E', 'D', 'D', 'C', 'E', 'D', 'E', 'E'];
        for (int i = 0; i < numQuestoes && i < respostas.length; i++) {
          gabarito[(i + 1).toString()] = respostas[i];
        }
        break;
      default:
        for (int i = 1; i <= numQuestoes; i++) {
          gabarito[i.toString()] = 'A';
        }
    }

    return gabarito;
  }

  int _determinarNumColunas(int numQuestoes) {
    if (numQuestoes <= 23) {
      return 1;
    } else if (numQuestoes <= 45) {
      return 2;
    } else {
      return 3;
    }
  }

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.remove('user_name');
      await prefs.remove('user_email');

      // ✅ LIMPAR CACHE DE CRÉDITOS
      _creditManager.clearCache();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao fazer logout: $e'),
          backgroundColor: AppColors.dangerColor,
        ),
      );
    }
  }

  // Enviar imagem para processamento
  Future<void> _enviarImagem() async {
    if (_imagemSelecionada == null) {
      setState(() {
        _mensagemErro = "Por favor, selecione uma imagem primeiro.";
      });
      return;
    }

    // Verificar se número de questões foi carregado
    if (_numeroQuestoes == null) {
      setState(() {
        _mensagemErro =
            "Número de questões não definido. Tente recarregar o simulado.";
      });
      return;
    }

    // ✅ VERIFICAR CRÉDITOS ANTES DO PROCESSAMENTO
    try {
      final availableCredits = await _creditManager.getAvailableCredits();

      if (availableCredits <= 0) {
        await CreditManager.showInsufficientCreditsDialog(
          // ignore: use_build_context_synchronously
          context,
          currentCredits: availableCredits,
          onBuyCredits: () {
            Navigator.pushNamed(context, '/loja-creditos');
          },
        );
        return;
      }
    } catch (e) {
      setState(() {
        _mensagemErro = "Erro ao verificar créditos: $e";
      });
      return;
    }

    setState(() {
      _enviando = true;
      _mensagemErro = null;
      _temImagensProcessadas = false;
    });

    try {
      final imgBytes = await _imagemSelecionada!.readAsBytes();
      _logger.info('Enviando imagem: ${_imagemSelecionada!.path}');
      _logger.info('Tamanho da imagem: ${imgBytes.length} bytes');
      _logger.info('Número de questões do simulado: $_numeroQuestoes');

      final uri =
          Uri.parse('http://sokk4wsk8c4ok4sccswwwccg.65.108.245.193.sslip.io/processar_cartao');
      final request = http.MultipartRequest('POST', uri);

      request.files.add(await http.MultipartFile.fromPath(
        'file',
        _imagemSelecionada!.path,
      ));

      // Usar _numeroQuestoes em vez de controller
      request.fields['num_questoes'] = _numeroQuestoes.toString();
      int numColunas = _determinarNumColunas(_numeroQuestoes!);
      request.fields['num_colunas'] = numColunas.toString();
      request.fields['threshold'] = '150';
      request.fields['retornar_imagens'] = 'true';

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _logger.info('Resposta do servidor: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        setState(() {
          _enviando = false;

          _temImagensProcessadas =
              responseData.containsKey('imagem_processada_base64') &&
                  responseData['imagem_processada_base64'] != null;

          if (_temImagensProcessadas) {
            try {
              _imagemOriginalProcessada =
                  base64Decode(responseData['imagem_processada_base64']);
            } catch (e) {
              _temImagensProcessadas = false;
              _logger.warning('Erro ao decodificar imagens: $e');
            }
          }
        });

        if (responseData.containsKey('respostas') &&
            responseData['respostas'] != null) {
          Map<String, String> respostasAluno = {};
          if (responseData['respostas'] is Map) {
            responseData['respostas'].forEach((key, value) {
              respostasAluno[key.toString()] =
                  value != null ? value.toString() : 'Não detectada';
            });
          } else if (responseData['respostas'] is List) {
            for (int i = 0; i < responseData['respostas'].length; i++) {
              final resposta = responseData['respostas'][i];
              respostasAluno[(i + 1).toString()] =
                  resposta != null ? resposta.toString() : 'Não detectada';
            }
          }

          final gabarito = await _obterGabarito();

          if (gabarito == null) {
            setState(() {
              _mensagemErro =
                  "Erro ao obter o gabarito. Verifique sua conexão.";
              _enviando = false;
            });
            return;
          }

          // Usar pontuação total do Django
          double pontuacaoTotal = _pontuacaoTotal ?? 10.0;
          int numQuestoes = gabarito.length;
          double valorPorQuestao = pontuacaoTotal / numQuestoes;
          double notaFinal = 0;

          respostasAluno.forEach((questao, resposta) {
            if (resposta == gabarito[questao]) {
              notaFinal += valorPorQuestao;
            }
          });

          // Usar _nomeAluno em vez de acessar widget.aluno diretamente
          String nomeAluno = _nomeAluno.isNotEmpty ? _nomeAluno : 'Aluno';

          if (_imagemOriginalProcessada != null) {
            Navigator.push(
              // ignore: use_build_context_synchronously
              context,
              MaterialPageRoute(
                builder: (context) => CartaoRespostaPreviewScreen(
                  imagemProcessada: _imagemOriginalProcessada!,
                  respostasAluno: respostasAluno,
                  gabarito: gabarito,
                  nomeAluno: nomeAluno,
                  notaFinal: notaFinal,
                  tipoProva: _tipoProva,
                  pontuacaoTotal: pontuacaoTotal,
                  alunoId: widget.alunoId,
                  simuladoId: widget.simuladoId,
                  turmaId: widget.turmaId,
                  nomeTurma: widget.turma?['nome'],
                  nomeSimulado: _tituloSimulado,
                ),
              ),
            );
          } else {
            Navigator.push(
              // ignore: use_build_context_synchronously
              context,
              MaterialPageRoute(
                builder: (context) => CartaoRespostaPreviewScreen(
                  imagemProcessada: imgBytes,
                  respostasAluno: respostasAluno,
                  gabarito: gabarito,
                  nomeAluno: nomeAluno,
                  notaFinal: notaFinal,
                  tipoProva: _tipoProva,
                  pontuacaoTotal: pontuacaoTotal,
                  alunoId: widget.alunoId,
                  simuladoId: widget.simuladoId,
                  turmaId: widget.turmaId,
                  nomeTurma: widget.turma?['nome'],
                  nomeSimulado: _tituloSimulado,
                ),
              ),
            );
          }
        }
      } else {
        setState(() {
          _mensagemErro =
              "Erro no servidor: ${response.statusCode} - ${response.body}";
          _enviando = false;
        });
      }
    } catch (e) {
      setState(() {
        _mensagemErro = "Erro ao enviar a imagem: $e";
        _enviando = false;
      });
    }
  }

  // ignore: unused_element
  Future<void> _atualizarIndicadorCreditos() async {
    if (mounted) {
      setState(() {
        // Força o rebuild do FutureBuilder
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: CustomAppBar(
        onReload: _carregarDadosSimulado,
        onExit: _logout,
      ),
      body: _carregandoSimulado
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: AppColors.primaryColor,
                    backgroundColor: AppColors.borderColor,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Carregando dados do simulado...',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12.0),
              children: [
                const SizedBox(height: 12),

                // Card de Créditos
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(
                        color: AppColors.borderColor, width: 1),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.green, Colors.teal],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Correções Disponíveis',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.secondaryColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FutureBuilder<int>(
                                future: _creditManager.getAvailableCredits(),
                                builder: (context, snapshot) {
                                  final credits = snapshot.data ?? 0;
                                  return Text(
                                    '$credits créditos',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: credits > 0
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.pushNamed(context, '/loja-creditos');
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.green, Colors.teal],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add,
                                      size: 16, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'Créditos',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Card com informações do simulado
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(
                        color: AppColors.borderColor, width: 1),
                  ),
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.secondaryColor,
                          AppColors.primaryColor
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header compacto - Nome do simulado e aluno na mesma linha
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.quiz,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                      _decodificarTexto(_tituloSimulado),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textLight,
                                        height: 1.2,
                                      ),
                                      maxLines: 1,
                                    ),
                                    const SizedBox(height: 2),
                                    SelectableText(
                                      _decodificarTexto(_nomeAluno),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withOpacity(0.9),
                                        height: 1.2,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Cards de Questões e Pontuação - mais compactos
                          Row(
                            children: [
                              // Card de Questões
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: AppColors.borderColor),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryColor
                                              .withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(
                                          Icons.help_outline,
                                          color: AppColors.primaryColor,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Questões',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textMuted,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              '${_numeroQuestoes ?? "..."}',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.secondaryColor,
                                                height: 1.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(width: 10),

                              // Card de Pontuação
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: AppColors.borderColor),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppColors.warningColor
                                              .withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(
                                          Icons.grade,
                                          color: AppColors.warningColor,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Pontuação',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textMuted,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              _pontuacaoTotal?.toStringAsFixed(1) ??
                                                  "...",
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.secondaryColor,
                                                height: 1.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Card de fluxo rápido (QR + captura + processamento)
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(
                        color: AppColors.borderColor, width: 1),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.primaryColor,
                                    AppColors.secondaryColor
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                Icons.qr_code_scanner,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Leitura Rápida',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '1. Leia o QR do cartão\n2. Fotografe o cartão\n3. Correção automática',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _enviando ? null : _iniciarFluxoLeitura,
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: _enviando
                                      ? null
                                      : const LinearGradient(
                                          colors: [
                                            AppColors.primaryColor,
                                            AppColors.secondaryColor
                                          ],
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                        ),
                                  color: _enviando
                                      ? AppColors.borderColor
                                      : null,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                alignment: Alignment.center,
                                child: _enviando
                                    ? const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            'Processando...',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.camera_alt,
                                              size: 20, color: Colors.white),
                                          SizedBox(width: 8),
                                          Text(
                                            'Ler QR e Fotografar',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Área da última imagem
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(
                        color: AppColors.borderColor, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: AppColors.bgLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _imagemSelecionada != null
                          ? Image.file(
                              _imagemSelecionada!,
                              fit: BoxFit.contain,
                            )
                          : const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.document_scanner_outlined,
                                    size: 48,
                                    color: AppColors.textMuted,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Nenhuma captura ainda',
                                    style:
                                        TextStyle(color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),

                if (_imagemSelecionada != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.verified,
                            size: 16, color: AppColors.successColor),
                        const SizedBox(width: 6),
                        Text(
                          'Tipo detectado: $_tipoProva',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.successColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                // Exibição de erro
                if (_mensagemErro != null)
                  Card(
                    color: AppColors.dangerColor.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(
                          color: AppColors.dangerColor, width: 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: AppColors.dangerColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Erro',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.dangerColor,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: Colors.white,
                                      title: const Text(
                                        'Detalhes do Erro',
                                        style: TextStyle(
                                            color: AppColors.secondaryColor),
                                      ),
                                      content: SingleChildScrollView(
                                        child: Text(
                                          _mensagemErro!,
                                          style: const TextStyle(
                                              color: AppColors.textMuted),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text(
                                            'Fechar',
                                            style: TextStyle(
                                                color: AppColors.primaryColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Ver detalhes',
                                  style:
                                      TextStyle(color: AppColors.dangerColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _mensagemErro!,
                            style: const TextStyle(
                              color: AppColors.dangerColor,
                              fontSize: 14,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_mensagemErro!.contains('simulado'))
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _carregarDadosSimulado,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.dangerColor
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: AppColors.dangerColor),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.refresh,
                                            size: 16,
                                            color: AppColors.dangerColor),
                                        SizedBox(width: 4),
                                        Text(
                                          'Recarregar Simulado',
                                          style: TextStyle(
                                              color: AppColors.dangerColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _enderecoIPController.dispose();
    _creditManager.dispose();
    super.dispose();
  }
}

class ImagensProcessadasScreen extends StatelessWidget {
  final Uint8List imagemOriginal;
  final Uint8List imagemBinaria;

  const ImagensProcessadasScreen({
    super.key,
    required this.imagemOriginal,
    required this.imagemBinaria,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppColors.bgSurface,
          foregroundColor: AppColors.textLight,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryColor, AppColors.secondaryColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.image_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Imagens Processadas',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: AppColors.textLight,
                ),
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(49),
            child: Column(
              children: [
                const TabBar(
                  indicatorColor: AppColors.primaryColor,
                  labelColor: AppColors.textLight,
                  unselectedLabelColor: AppColors.textMuted,
                  tabs: [
                    Tab(
                      text: 'Original',
                      icon: Icon(Icons.image_outlined),
                    ),
                    Tab(
                      text: 'Processada',
                      icon: Icon(Icons.filter_b_and_w_outlined),
                    ),
                  ],
                ),
                Container(
                  height: 1,
                  color: AppColors.borderColor,
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            // Tab da imagem original
            Container(
              color: AppColors.bgDark,
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Card(
                          color: AppColors.bgSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(
                                color: AppColors.borderColor, width: 1),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            AppColors.primaryColor,
                                            AppColors.secondaryColor
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.image_outlined,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Imagem Original com Marcações',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Esta é a imagem capturada com as marcações de detecção das respostas.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textMuted,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.borderColor, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 4.0,
                            boundaryMargin: const EdgeInsets.all(20.0),
                            child: Image.memory(
                              imagemOriginal,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.primaryColor.withOpacity(0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              color: AppColors.primaryColor,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Use gestos de pinça para ampliar e arrastar para navegar',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Tab da imagem processada (binarizada)
            Container(
              color: AppColors.bgDark,
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Card(
                          color: AppColors.bgSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(
                                color: AppColors.borderColor, width: 1),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.textMuted,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.filter_b_and_w_outlined,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Imagem Binarizada',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Esta é a versão processada em preto e branco usada pelo algoritmo de detecção.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textMuted,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.borderColor, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 4.0,
                            boundaryMargin: const EdgeInsets.all(20.0),
                            child: Image.memory(
                              imagemBinaria,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.textMuted.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.textMuted.withOpacity(0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppColors.textMuted,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Imagem convertida para facilitar a detecção automática das marcações',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.pop(context);
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryColor, AppColors.secondaryColor],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Voltar',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }
}
