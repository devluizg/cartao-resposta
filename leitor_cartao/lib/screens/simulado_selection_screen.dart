// simulado_selection_screen.dart
// Tela 1: Seleção de Simulado e Aluno (com integração API)
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import '../services/api_service.dart';
import '../services/models/simulado_model.dart';
import '../services/models/student_model.dart';
import 'qr_capture_screen.dart';

class SimuladoData {
  final int id;
  final String nome;
  final int numQuestoes;
  final DateTime dataCriacao;
  final double notaMaxima;

  SimuladoData({
    required this.id,
    required this.nome,
    required this.numQuestoes,
    required this.dataCriacao,
    this.notaMaxima = 10.0,
  });

  factory SimuladoData.fromApiModel(SimuladoModel model) {
    return SimuladoData(
      id: model.id,
      nome: model.titulo,
      numQuestoes: model.questoes.length,
      dataCriacao: model.dataCriacao,
      notaMaxima: model.notaMaxima,
    );
  }
}

class AlunoData {
  final int id;
  final String nome;
  final String matricula;
  final String? turmaNome;

  AlunoData({
    required this.id,
    required this.nome,
    required this.matricula,
    this.turmaNome,
  });

  factory AlunoData.fromApiModel(StudentModel model) {
    return AlunoData(
      id: model.id,
      nome: model.name,
      matricula: model.studentId?.toString() ?? 'N/A',
    );
  }
}

class SimuladoSelectionScreen extends StatefulWidget {
  final int? turmaId;

  const SimuladoSelectionScreen({
    super.key,
    this.turmaId,
  });

  @override
  State<SimuladoSelectionScreen> createState() => _SimuladoSelectionScreenState();
}

class _SimuladoSelectionScreenState extends State<SimuladoSelectionScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String _errorMessage = '';

  List<SimuladoData> simulados = [];
  List<AlunoData> alunos = [];

  SimuladoData? _simuladoSelecionado;
  AlunoData? _alunoSelecionado;

  static const Color primary = Color(0xFF0DA6F2);
  static const Color primaryDark = Color(0xFF003D5C);
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color textMain = Color(0xFF003D5C);
  static const Color textSub = Color(0xFF475569);
  static const Color borderLight = Color(0xFFDBE2E6);

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final simuladosApi = await _apiService.getSimulados();
      final alunosApi = await _apiService.getStudents(
        turmaId: widget.turmaId?.toString(),
      );

      setState(() {
        simulados = simuladosApi
            .map((s) => SimuladoData.fromApiModel(s))
            .toList();
        alunos = alunosApi
            .map((a) => AlunoData.fromApiModel(a))
            .toList();
        _isLoading = false;

        if (simulados.isEmpty) {
          _errorMessage = 'Nenhum simulado encontrado';
        }
        if (alunos.isEmpty) {
          _errorMessage = _errorMessage.isEmpty
              ? 'Nenhum aluno encontrado'
              : 'Sem simulados e alunos';
        }
      });
    } catch (e) {
      developer.log('Erro ao carregar dados: $e');
      setState(() {
        _errorMessage = 'Erro ao carregar dados: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Corrigir Cartão-Resposta',
          style: TextStyle(
            color: textMain,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: textMain),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: primary),
            )
          : _errorMessage.isNotEmpty
              ? _buildErrorView()
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSection(
                          title: 'Passo 1: Selecione o Simulado',
                          icon: Icons.assignment,
                          child: _buildSimuladoSelection(),
                        ),
                        const SizedBox(height: 24),
                        _buildSection(
                          title: 'Passo 2: Selecione o Aluno',
                          icon: Icons.person,
                          child: _buildAlunoSelection(),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _simuladoSelecionado != null &&
                                    _alunoSelecionado != null
                                ? _avancar
                                : null,
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text('PRÓXIMO: Ler QR Code'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              disabledBackgroundColor: Colors.grey.shade300,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: primary.withOpacity(0.2),
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ℹ️ Fluxo:',
                                style: TextStyle(
                                  color: textMain,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '1️⃣ Simulado + Aluno\n2️⃣ Ler QR Code\n3️⃣ Fotografar Cartão\n4️⃣ Processar\n5️⃣ Ver Resultado',
                                style: TextStyle(
                                  color: textSub,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade600, size: 48),
          const SizedBox(height: 12),
          Text(
            _errorMessage,
            style: const TextStyle(color: textSub, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _carregarDados,
            style: ElevatedButton.styleFrom(backgroundColor: primary),
            child: const Text(
              'Tentar novamente',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: primary, size: 24),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: textMain,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderLight),
          ),
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ],
    );
  }

  Widget _buildSimuladoSelection() {
    if (simulados.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum simulado disponível',
          style: TextStyle(color: textSub),
        ),
      );
    }

    return Column(
      children: simulados.map((simulado) {
        final isSelected = _simuladoSelecionado?.id == simulado.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _simuladoSelecionado = simulado;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? primary.withOpacity(0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? primary : borderLight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? primary : Colors.grey.shade400,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Center(
                              child: Icon(Icons.check, color: primary, size: 14),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            simulado.nome,
                            style: const TextStyle(
                              color: textMain,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${simulado.numQuestoes} questões • ${simulado.dataCriacao.day}/${simulado.dataCriacao.month}/${simulado.dataCriacao.year}',
                            style: const TextStyle(
                              color: textSub,
                              fontSize: 11,
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
        );
      }).toList(),
    );
  }

  Widget _buildAlunoSelection() {
    if (alunos.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum aluno disponível',
          style: TextStyle(color: textSub),
        ),
      );
    }

    return Column(
      children: alunos.map((aluno) {
        final isSelected = _alunoSelecionado?.id == aluno.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _alunoSelecionado = aluno;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? primary.withOpacity(0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? primary : borderLight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? primary : Colors.grey.shade400,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Center(
                              child: Icon(Icons.check, color: primary, size: 14),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            aluno.nome,
                            style: const TextStyle(
                              color: textMain,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Matrícula: ${aluno.matricula}',
                            style: const TextStyle(
                              color: textSub,
                              fontSize: 11,
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
        );
      }).toList(),
    );
  }

  void _avancar() {
    if (_simuladoSelecionado == null || _alunoSelecionado == null) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QRCaptureScreen(
          simulado: _simuladoSelecionado!,
          aluno: _alunoSelecionado!,
        ),
      ),
    );
  }
}
