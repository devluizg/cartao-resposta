import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:logging/logging.dart' show Logger;
import 'package:shared_preferences/shared_preferences.dart';

// Importar a tela de login
import 'screens/login_screen.dart';
// Importar a tela de resultado
import 'screens/resultado_screen.dart';

final Logger _logger = Logger('CartaoRespostaApp');

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
  Map<String, dynamic>? _resultados;

  Uint8List? _imagemOriginalProcessada;
  Uint8List? _imagemBinarizada;
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
          _resultados = null;
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
          _resultados = null;
          _temImagensProcessadas = false;
        });
      }
    } catch (e) {
      setState(() {
        _mensagemErro = "Erro ao selecionar imagem: $e";
      });
    }
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
      _resultados = null;
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
          _resultados = responseData;
          _enviando = false;

          // Modificação aqui - verificar de forma mais robusta a existência das imagens
          _temImagensProcessadas =
              responseData.containsKey('imagem_original_base64') &&
                  responseData.containsKey('imagem_binaria_base64') &&
                  responseData['imagem_original_base64'] != null &&
                  responseData['imagem_binaria_base64'] != null;

          if (_temImagensProcessadas) {
            try {
              _imagemOriginalProcessada =
                  base64Decode(responseData['imagem_original_base64']);
              _imagemBinarizada =
                  base64Decode(responseData['imagem_binaria_base64']);
            } catch (e) {
              _temImagensProcessadas = false;
              _logger.warning('Erro ao decodificar imagens: $e');
            }
          }
        });

        // MODIFICAÇÃO: Navegar para a tela de resultados após processar o cartão
        if (responseData.containsKey('respostas') &&
            responseData['respostas'] != null) {
          // Convertendo as respostas para o formato esperado pela ResultadoScreen
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

          // Gabarito com base no tipo de prova selecionado
          Map<String, String> gabarito = {};
          int numQuestoes = int.tryParse(_numQuestoesController.text) ?? 10;

// Gabarito para cada tipo de prova
// Baseado na imagem do gabarito que você compartilhou
          switch (_tipoProva) {
            case 1:
              for (int i = 1; i <= numQuestoes; i++) {
                switch (i) {
                  case 1:
                    gabarito[i.toString()] = 'D';
                    break;
                  case 2:
                    gabarito[i.toString()] = 'D';
                    break;
                  case 3:
                    gabarito[i.toString()] = 'D';
                    break;
                  case 4:
                    gabarito[i.toString()] = 'C';
                    break;
                  case 5:
                    gabarito[i.toString()] = 'C';
                    break;
                  case 6:
                    gabarito[i.toString()] = 'B';
                    break;
                  case 7:
                    gabarito[i.toString()] = 'D';
                    break;
                  case 8:
                    gabarito[i.toString()] = 'C';
                    break;
                  case 9:
                    gabarito[i.toString()] = 'D';
                    break;
                  case 10:
                    gabarito[i.toString()] = 'D';
                    break;
                  default:
                    gabarito[i.toString()] =
                        'A'; // Padrão para questões adicionais
                }
              }
              break;
            case 2:
              for (int i = 1; i <= numQuestoes; i++) {
                switch (i) {
                  case 1:
                    gabarito[i.toString()] = 'C';
                    break;
                  case 2:
                    gabarito[i.toString()] = 'C';
                    break;
                  case 3:
                    gabarito[i.toString()] = 'C';
                    break;
                  case 4:
                    gabarito[i.toString()] = 'B';
                    break;
                  case 5:
                    gabarito[i.toString()] = 'B';
                    break;
                  case 6:
                    gabarito[i.toString()] = 'A';
                    break;
                  case 7:
                    gabarito[i.toString()] = 'C';
                    break;
                  case 8:
                    gabarito[i.toString()] = 'B';
                    break;
                  case 9:
                    gabarito[i.toString()] = 'C';
                    break;
                  case 10:
                    gabarito[i.toString()] = 'C';
                    break;
                  default:
                    gabarito[i.toString()] =
                        'B'; // Padrão para questões adicionais
                }
              }
              break;
            case 3:
              for (int i = 1; i <= numQuestoes; i++) {
                switch (i) {
                  case 1:
                    gabarito[i.toString()] = 'B';
                    break;
                  case 2:
                    gabarito[i.toString()] = 'B';
                    break;
                  case 3:
                    gabarito[i.toString()] = 'B';
                    break;
                  case 4:
                    gabarito[i.toString()] = 'A';
                    break;
                  case 5:
                    gabarito[i.toString()] = 'A';
                    break;
                  case 6:
                    gabarito[i.toString()] = 'E';
                    break;
                  case 7:
                    gabarito[i.toString()] = 'B';
                    break;
                  case 8:
                    gabarito[i.toString()] = 'A';
                    break;
                  case 9:
                    gabarito[i.toString()] = 'B';
                    break;
                  case 10:
                    gabarito[i.toString()] = 'B';
                    break;
                  default:
                    gabarito[i.toString()] =
                        'C'; // Padrão para questões adicionais
                }
              }
              break;
            case 4:
              for (int i = 1; i <= numQuestoes; i++) {
                switch (i) {
                  case 1:
                    gabarito[i.toString()] = 'A';
                    break;
                  case 2:
                    gabarito[i.toString()] = 'A';
                    break;
                  case 3:
                    gabarito[i.toString()] = 'A';
                    break;
                  case 4:
                    gabarito[i.toString()] = 'E';
                    break;
                  case 5:
                    gabarito[i.toString()] = 'E';
                    break;
                  case 6:
                    gabarito[i.toString()] = 'D';
                    break;
                  case 7:
                    gabarito[i.toString()] = 'A';
                    break;
                  case 8:
                    gabarito[i.toString()] = 'E';
                    break;
                  case 9:
                    gabarito[i.toString()] = 'A';
                    break;
                  case 10:
                    gabarito[i.toString()] = 'A';
                    break;
                  default:
                    gabarito[i.toString()] =
                        'D'; // Padrão para questões adicionais
                }
              }
              break;
            case 5:
              for (int i = 1; i <= numQuestoes; i++) {
                switch (i) {
                  case 1:
                    gabarito[i.toString()] = 'E';
                    break;
                  case 2:
                    gabarito[i.toString()] = 'E';
                    break;
                  case 3:
                    gabarito[i.toString()] = 'E';
                    break;
                  case 4:
                    gabarito[i.toString()] = 'D';
                    break;
                  case 5:
                    gabarito[i.toString()] = 'D';
                    break;
                  case 6:
                    gabarito[i.toString()] = 'C';
                    break;
                  case 7:
                    gabarito[i.toString()] = 'E';
                    break;
                  case 8:
                    gabarito[i.toString()] = 'D';
                    break;
                  case 9:
                    gabarito[i.toString()] = 'E';
                    break;
                  case 10:
                    gabarito[i.toString()] = 'E';
                    break;
                  default:
                    gabarito[i.toString()] =
                        'E'; // Padrão para questões adicionais
                }
              }
              break;
            default:
              // Caso padrão, não deve acontecer
              for (int i = 1; i <= numQuestoes; i++) {
                gabarito[i.toString()] = 'A';
              }
          }

// Calcular a nota com base na pontuação total informada
          double pontuacaoTotal =
              double.tryParse(_pontuacaoTotalController.text) ?? 10.0;
          double valorPorQuestao = pontuacaoTotal / numQuestoes;
          double notaFinal = 0;

          respostasAluno.forEach((questao, resposta) {
            if (resposta == gabarito[questao]) {
              notaFinal += valorPorQuestao;
            }
          });

          // Nome do aluno (da propriedade widget.aluno)
          String nomeAluno = widget.aluno['nome'] ?? 'Aluno';
          if (nomeAluno.isEmpty) {
            nomeAluno = 'Aluno';
          }

          // Navegar para a tela de resultados
          Navigator.push(
            // ignore: use_build_context_synchronously
            context,
            MaterialPageRoute(
              builder: (context) => ResultadoScreen(
                nomeAluno: nomeAluno,
                notaFinal: notaFinal,
                respostasAluno: respostasAluno,
                gabarito: gabarito,
                tipoProva: _tipoProva,
                pontuacaoTotal: pontuacaoTotal,
              ),
            ),
          );
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

  void _visualizarProcessamento() {
    if (_imagemOriginalProcessada == null || _imagemBinarizada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'As imagens processadas não estão disponíveis. Tente processar novamente.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImagensProcessadasScreen(
          imagemOriginal: _imagemOriginalProcessada!,
          imagemBinaria: _imagemBinarizada!,
        ),
      ),
    );
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

            // Botão para visualizar processamento
            ElevatedButton.icon(
              onPressed: (_imagemOriginalProcessada != null &&
                      _imagemBinarizada != null)
                  ? _visualizarProcessamento
                  : null,
              icon: const Icon(Icons.image_search),
              label: const Text('Ver Processamento'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade600,
              ),
            ),

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

            // Exibição dos resultados
            if (_resultados != null)
              Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Resultados:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Verificar se existe a chave 'respostas'
                    if (_resultados!.containsKey('respostas'))
                      ..._exibirRespostas(_resultados!['respostas'])
                    else
                      Text(
                        _resultados.toString(),
                        style: const TextStyle(fontSize: 16),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _exibirRespostas(dynamic respostas) {
    List<Widget> widgets = [];

    if (respostas is Map) {
      // Ordenar as questões numericamente
      List chaves = respostas.keys.toList();
      chaves.sort((a, b) => int.parse(a).compareTo(int.parse(b)));

      // Para cada questão, exibir o número e a resposta
      for (var numero in chaves) {
        var resposta = respostas[numero];
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Text(
                  'Questão $numero: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  resposta != null ? resposta.toString() : 'Não detectada',
                  style: TextStyle(
                    color: resposta == null
                        ? Colors.red
                        : (resposta.toString().contains('?')
                            ? Colors.orange
                            : Colors.black),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } else if (respostas is List) {
      // Se for uma lista, exibir cada item numerado
      for (int i = 0; i < respostas.length; i++) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Text(
                  'Questão ${i + 1}: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  respostas[i] != null
                      ? respostas[i].toString()
                      : 'Não detectada',
                  style: TextStyle(
                    color: respostas[i] == null
                        ? Colors.red
                        : (respostas[i].toString().contains('?')
                            ? Colors.orange
                            : Colors.black),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } else {
      // Caso o formato seja desconhecido
      widgets.add(Text(respostas.toString()));
    }

    return widgets;
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
