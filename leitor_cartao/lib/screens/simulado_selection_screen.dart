// simulado_selection_screen.dart
// Tela 1: Seleção de Simulado e Aluno
import 'package:flutter/material.dart';
import 'qr_capture_screen.dart';

class SimuladoData {
  final int id;
  final String nome;
  final int numQuestoes;
  final DateTime dataCriacao;

  SimuladoData({
    required this.id,
    required this.nome,
    required this.numQuestoes,
    required this.dataCriacao,
  });
}

class AlunoData {
  final int id;
  final String nome;
  final String matricula;

  AlunoData({
    required this.id,
    required this.nome,
    required this.matricula,
  });
}

/// Tela 1: Seleção de Simulado e Aluno
class SimuladoSelectionScreen extends StatefulWidget {
  const SimuladoSelectionScreen({super.key});

  @override
  State<SimuladoSelectionScreen> createState() => _SimuladoSelectionScreenState();
}

class _SimuladoSelectionScreenState extends State<SimuladoSelectionScreen> {
  // ✨ TODO: Conectar com API real
  final List<SimuladoData> simulados = [
    SimuladoData(
      id: 1,
      nome: 'ENEM 2024 - Simulado 1',
      numQuestoes: 45,
      dataCriacao: DateTime(2024, 1, 15),
    ),
    SimuladoData(
      id: 2,
      nome: 'ENEM 2024 - Simulado 2',
      numQuestoes: 45,
      dataCriacao: DateTime(2024, 2, 10),
    ),
    SimuladoData(
      id: 3,
      nome: 'Simulado Geral - 30 questões',
      numQuestoes: 30,
      dataCriacao: DateTime(2024, 2, 20),
    ),
  ];

  final List<AlunoData> alunos = [
    AlunoData(id: 1, nome: 'João Silva', matricula: '2024001'),
    AlunoData(id: 2, nome: 'Maria Santos', matricula: '2024002'),
    AlunoData(id: 3, nome: 'Pedro Oliveira', matricula: '2024003'),
  ];

  SimuladoData? _simuladoSelecionado;
  AlunoData? _alunoSelecionado;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Corrigir Cartão-Resposta',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SEÇÃO 1: SELEÇÃO DO SIMULADO
              _buildSection(
                title: 'Passo 1: Selecione o Simulado',
                icon: Icons.assignment,
                child: _buildSimuladoSelection(),
              ),

              const SizedBox(height: 24),

              // SEÇÃO 2: SELEÇÃO DO ALUNO
              _buildSection(
                title: 'Passo 2: Selecione o Aluno',
                icon: Icons.person,
                child: _buildAlunoSelection(),
              ),

              const SizedBox(height: 32),

              // BOTÃO: PRÓXIMO
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
                    backgroundColor: const Color(0xFF0DA6F2),
                    disabledBackgroundColor: Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // INFO: Fluxo
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade900.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF0DA6F2).withOpacity(0.5),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ℹ️ Fluxo:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1️⃣ Simulado + Aluno\n2️⃣ Ler QR Code\n3️⃣ Fotografar Cartão\n4️⃣ Processar\n5️⃣ Ver Resultado',
                      style: TextStyle(
                        color: Colors.white70,
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
            Icon(icon, color: const Color(0xFF0DA6F2), size: 24),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ],
    );
  }

  Widget _buildSimuladoSelection() {
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
                  color: isSelected
                      ? const Color(0xFF0DA6F2).withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF0DA6F2)
                        : Colors.white24,
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
                          color: isSelected
                              ? const Color(0xFF0DA6F2)
                              : Colors.white30,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Center(
                              child: Icon(Icons.check,
                                  color: Color(0xFF0DA6F2), size: 14),
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
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${simulado.numQuestoes} questões • ${simulado.dataCriacao.day}/${simulado.dataCriacao.month}/${simulado.dataCriacao.year}',
                            style: const TextStyle(
                              color: Colors.white60,
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
                  color: isSelected
                      ? const Color(0xFF0DA6F2).withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF0DA6F2)
                        : Colors.white24,
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
                          color: isSelected
                              ? const Color(0xFF0DA6F2)
                              : Colors.white30,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Center(
                              child: Icon(Icons.check,
                                  color: Color(0xFF0DA6F2), size: 14),
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
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Matrícula: ${aluno.matricula}',
                            style: const TextStyle(
                              color: Colors.white60,
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
