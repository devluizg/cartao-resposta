import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:logging/logging.dart' show Logger;
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/cartao_resposta_preview_screen.dart';

// Importar a tela de login
import 'screens/login_screen.dart';
// Importar a tela de resultado
// Importar o serviço de API
import '../services/api_service.dart';

final Logger _logger = Logger('CartaoRespostaApp');
final ApiService _apiService = ApiService();

void main() {
  runApp(const CartaoRespostaApp());
}

class CartaoRespostaApp extends StatelessWidget {
  const CartaoRespostaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Leitor de Cartão Resposta',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthenticationWrapper(),
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
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isAuthenticated) {
      // Aqui você pode redirecionar para SelectionScreen se preferir
      return const TelaInicial(
        turmaId: 0,
        simuladoId: 0,
        alunoId: 0,
        aluno: {},
        simulado: {},
      );
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

  const TelaInicial({
    super.key,
    required this.turmaId,
    required this.simuladoId,
    required this.alunoId,
    required this.aluno,
    required this.simulado,
  });

  @override
  State<TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<TelaInicial> {
  File? _imagemSelecionada;
  final ImagePicker _picker = ImagePicker();
  bool _enviando = false;
  String? _mensagemErro;

  Uint8List? _imagemOriginalProcessada;
  bool _temImagensProcessadas = false;

  final TextEditingController _numQuestoesController =
      TextEditingController(text: "10");
  final TextEditingController _numColunasController =
      TextEditingController(text: "2");
  final TextEditingController _thresholdController =
      TextEditingController(text: "150");
  final TextEditingController _enderecoIPController =
      TextEditingController(text: "192.168.1.8:8000");
  final TextEditingController _pontuacaoTotalController =
      TextEditingController(text: "10");
  int _tipoProva = 1;

  Future<void> _capturarImagem() async {
    try {
      final XFile? imagem = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1600,
        maxHeight: 1200,
      );

      if (imagem != null) {
        setState(() {
          _imagemSelecionada = File(imagem.path);
          _mensagemErro = null;
          _temImagensProcessadas = false;
        });
      }
    } catch (e) {
      setState(() {
        _mensagemErro = "Erro ao capturar imagem: $e";
      });
    }
  }

  Future<void> _selecionarDaGaleria() async {
    try {
      final XFile? imagem = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
        maxWidth: 1600,
        maxHeight: 1200,
      );

      if (imagem != null) {
        setState(() {
          _imagemSelecionada = File(imagem.path);
          _mensagemErro = null;
          _temImagensProcessadas = false;
        });
      }
    } catch (e) {
      setState(() {
        _mensagemErro = "Erro ao selecionar imagem: $e";
      });
    }
  }

  // Função para obter o gabarito da API baseado no tipo de prova
  Future<Map<String, String>?> _obterGabarito() async {
    try {
      if (widget.simuladoId <= 0) {
        // Se não temos um simuladoId válido, use o gabarito local
        return _getGabaritoLocal();
      }

      // Obter o gabarito da API
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

  // Função auxiliar para obter gabarito local (fallback)
  Map<String, String> _getGabaritoLocal() {
    int numQuestoes = int.tryParse(_numQuestoesController.text) ?? 10;
    Map<String, String> gabarito = {};

    // Baseado nos dados do seu código original
    switch (_tipoProva) {
      case 1:
        // Gabarito para o Tipo 1 (Versão 1)
        final respostas = ['D', 'D', 'D', 'C', 'C', 'B', 'D', 'C', 'D', 'D'];
        for (int i = 0; i < numQuestoes && i < respostas.length; i++) {
          gabarito[(i + 1).toString()] = respostas[i];
        }
        break;
      case 2:
        // Gabarito para o Tipo 2 (Versão 2)
        final respostas = ['C', 'C', 'C', 'B', 'B', 'A', 'C', 'B', 'C', 'C'];
        for (int i = 0; i < numQuestoes && i < respostas.length; i++) {
          gabarito[(i + 1).toString()] = respostas[i];
        }
        break;
      case 3:
        // Gabarito para o Tipo 3 (Versão 3)
        final respostas = ['B', 'B', 'B', 'A', 'A', 'E', 'B', 'A', 'B', 'B'];
        for (int i = 0; i < numQuestoes && i < respostas.length; i++) {
          gabarito[(i + 1).toString()] = respostas[i];
        }
        break;
      case 4:
        // Gabarito para o Tipo 4 (Versão 4)
        final respostas = ['A', 'A', 'A', 'E', 'E', 'D', 'A', 'E', 'A', 'A'];
        for (int i = 0; i < numQuestoes && i < respostas.length; i++) {
          gabarito[(i + 1).toString()] = respostas[i];
        }
        break;
      case 5:
        // Gabarito para o Tipo 5 (Versão 5)
        final respostas = ['E', 'E', 'E', 'D', 'D', 'C', 'E', 'D', 'E', 'E'];
        for (int i = 0; i < numQuestoes && i < respostas.length; i++) {
          gabarito[(i + 1).toString()] = respostas[i];
        }
        break;
      default:
        // Caso padrão, não deve acontecer
        for (int i = 1; i <= numQuestoes; i++) {
          gabarito[i.toString()] = 'A';
        }
    }

    return gabarito;
  }

  Future<void> _enviarImagem() async {
    if (_imagemSelecionada == null) {
      setState(() {
        _mensagemErro = "Por favor, selecione uma imagem primeiro.";
      });
      return;
    }

    setState(() {
      _enviando = true;
      _mensagemErro = null;
      _temImagensProcessadas = false;
    });

    try {
      // Debug: verificar tamanho da imagem
      final imgBytes = await _imagemSelecionada!.readAsBytes();
      _logger.info('Enviando imagem: ${_imagemSelecionada!.path}');
      _logger.info('Tamanho da imagem: ${imgBytes.length} bytes');

      // Obter o endereço do servidor do campo de texto
      final serverAddress = _enderecoIPController.text;

      // Preparar a requisição multipart
      final uri = Uri.parse('http://$serverAddress/processar_cartao');
      final request = http.MultipartRequest('POST', uri);

      // Adicionar a imagem ao request
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        _imagemSelecionada!.path,
      ));

      // Adicionar os parâmetros
      request.fields['num_questoes'] = _numQuestoesController.text;
      request.fields['num_colunas'] = _numColunasController.text;
      request.fields['threshold'] = _thresholdController.text;
      // Adicionar campo para requisitar imagens processadas
      request.fields['retornar_imagens'] = 'true';

      // Enviar a requisição
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _logger.info('Resposta do servidor: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        setState(() {
          _enviando = false;

          // Verificar de forma mais robusta a existência das imagens
          _temImagensProcessadas =
              responseData.containsKey('imagem_processada_base64') &&
                  responseData.containsKey('imagem_processada_base64') &&
                  responseData['imagem_processada_base64'] != null &&
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

        // Verificar se há respostas detectadas para navegar para a tela de resultados
        if (responseData.containsKey('respostas') &&
            responseData['respostas'] != null) {
          // Convertendo as respostas para o formato esperado
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

          // Obter o gabarito correto para o tipo de prova selecionado
          final gabarito = await _obterGabarito();

          if (gabarito == null) {
            setState(() {
              _mensagemErro =
                  "Erro ao obter o gabarito. Verifique sua conexão.";
              _enviando = false;
            });
            return;
          }

          // Calcular a nota
          double pontuacaoTotal =
              double.tryParse(_pontuacaoTotalController.text) ?? 10.0;
          int numQuestoes = gabarito.length;
          double valorPorQuestao = pontuacaoTotal / numQuestoes;
          double notaFinal = 0;

          respostasAluno.forEach((questao, resposta) {
            if (resposta == gabarito[questao]) {
              notaFinal += valorPorQuestao;
            }
          });

          // Nome do aluno
          String nomeAluno = widget.aluno['nome'] ?? 'Aluno';
          if (nomeAluno.isEmpty) {
            nomeAluno = 'Aluno';
          }

          // ALTERAÇÃO: Sempre navegar para a tela de preview do cartão resposta
          if (_imagemOriginalProcessada != null) {
            // ignore: use_build_context_synchronously
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
                  nomeTurma: widget.aluno['name'] ??
                      '', // Ajuste o nome do campo se necessário
                  nomeSimulado: widget.simulado['titulo'] ?? '',
                ),
              ),
            );
          } else {
            // Mesmo se a imagem processada não estiver disponível,
            // tente usar a imagem original como fallback
            // ignore: use_build_context_synchronously
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

  // Função para fazer logout
  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.remove('user_name');
      await prefs.remove('user_email');

      if (!mounted) return;

      // Navegar de volta para a tela de login
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false, // Remove todas as rotas anteriores da pilha
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao fazer logout: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leitor de Cartão Resposta'),
        actions: [
          // Botão de logout
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Configurações
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configurações',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _enderecoIPController,
                      decoration: const InputDecoration(
                        labelText: 'Endereço do servidor (IP:porta)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _numQuestoesController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Número de questões',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _numColunasController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Número de colunas',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _thresholdController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Threshold (0-255)',
                        helperText:
                            'Valor de limiar para detecção de marcações',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            //Configuração de Prova
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configurações da Prova',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pontuacaoTotalController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Pontuação total da prova',
                              helperText: 'Ex: 10 pontos',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tipo de Prova:',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          for (int i = 1; i <= 5; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: Text('Tipo $i'),
                                selected: _tipoProva == i,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _tipoProva = i;
                                    });
                                  }
                                },
                                backgroundColor: Colors.grey[200],
                                selectedColor: Colors.blue,
                                labelStyle: TextStyle(
                                  color: _tipoProva == i
                                      ? Colors.white
                                      : Colors.black,
                                  fontWeight: _tipoProva == i
                                      ? FontWeight.bold
                                      : FontWeight.normal,
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

            // Área da imagem
            _imagemSelecionada != null
                ? Image.file(
                    _imagemSelecionada!,
                    height: 300,
                    fit: BoxFit.contain,
                  )
                : Container(
                    height: 300,
                    color: Colors.grey[300],
                    alignment: Alignment.center,
                    child: const Text('Nenhuma imagem selecionada'),
                  ),

            const SizedBox(height: 20),

            // Botões para capturar/selecionar imagem
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _capturarImagem,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Capturar'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _selecionarDaGaleria,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galeria'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Botão para enviar a imagem
            ElevatedButton.icon(
              onPressed: _imagemSelecionada == null || _enviando
                  ? null
                  : _enviarImagem,
              icon: _enviando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_enviando ? 'Processando...' : 'Processar Cartão'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 10),

            // Exibição de erro
            if (_mensagemErro != null)
              Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  _mensagemErro!,
                  style: TextStyle(color: Colors.red[900]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _numQuestoesController.dispose();
    _numColunasController.dispose();
    _thresholdController.dispose();
    _enderecoIPController.dispose();
    _pontuacaoTotalController.dispose();
    super.dispose();
  }
}

class ImagensProcessadasScreen extends StatelessWidget {
  final Uint8List imagemOriginal;
  final Uint8List imagemBinaria;

  const ImagensProcessadasScreen(
      {super.key, required this.imagemOriginal, required this.imagemBinaria});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Imagens Processadas'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Original', icon: Icon(Icons.image)),
              Tab(text: 'Processada', icon: Icon(Icons.filter)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab da imagem original
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Imagem Original com Marcações',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      boundaryMargin: const EdgeInsets.all(20.0),
                      child: Image.memory(
                        imagemOriginal,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Tab da imagem processada (binarizada)
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Imagem Binarizada',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      boundaryMargin: const EdgeInsets.all(20.0),
                      child: Image.memory(
                        imagemBinaria,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.pop(context);
          },
          tooltip: 'Voltar',
          child: const Icon(Icons.arrow_back),
        ),
      ),
    );
  }
}
