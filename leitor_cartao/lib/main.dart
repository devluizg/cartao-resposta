import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logging/logging.dart' show Logger;

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
      home: const TelaInicial(),
    );
  }
}

class TelaInicial extends StatefulWidget {
  const TelaInicial({super.key});

  @override
  State<TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<TelaInicial> {
  File? _imagemSelecionada;
  final ImagePicker _picker = ImagePicker();
  bool _enviando = false;
  String? _mensagemErro;
  Map<String, dynamic>? _resultados;

  // Controladores para os campos de entrada
  final TextEditingController _numQuestoesController =
      TextEditingController(text: "10");
  final TextEditingController _numColunasController =
      TextEditingController(text: "2");
  final TextEditingController _thresholdController =
      TextEditingController(text: "150");
  final TextEditingController _enderecoIPController =
      TextEditingController(text: "192.168.1.8:8000");

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

      // Enviar a requisição
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _logger.info('Resposta do servidor: ${response.body}');

      if (response.statusCode == 200) {
        setState(() {
          _resultados = json.decode(response.body);
          _enviando = false;
        });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leitor de Cartão Resposta'),
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
    super.dispose();
  }
}
