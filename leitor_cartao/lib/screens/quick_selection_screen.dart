import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/models/class_model.dart';
import '../services/models/simulado_model.dart';
import '../services/models/student_model.dart';
import '../widgets/custom_app_bar.dart';
import 'simulado_selection_screen.dart';
import 'cartao_processing_screen.dart';

/// Tela exibida após o QR scan — mostra apenas turma (se múltiplas) + aluno.
class QuickSelectionScreen extends StatefulWidget {
  final SimuladoModel simulado;
  final List<ClassModel> turmas; // já filtradas para este simulado
  final int tipoProva;
  final String? versionCode;

  const QuickSelectionScreen({
    super.key,
    required this.simulado,
    required this.turmas,
    required this.tipoProva,
    this.versionCode,
  });

  @override
  State<QuickSelectionScreen> createState() => _QuickSelectionScreenState();
}

class _QuickSelectionScreenState extends State<QuickSelectionScreen> {
  final ApiService _apiService = ApiService();

  int? _turmaId;
  int? _alunoId;
  List<StudentModel> _alunos = [];
  bool _carregandoAlunos = false;

  static const Color primary = Color(0xFF0DA6F2);
  static const Color primaryDark = Color(0xFF003D5C);
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color textMain = Color(0xFF003D5C);
  static const Color textSub = Color(0xFF475569);
  static const Color borderLight = Color(0xFFDBE2E6);
  static const Color errorColor = Color(0xFFDC2626);

  @override
  void initState() {
    super.initState();
    // Auto-select turma if only one option
    if (widget.turmas.length == 1) {
      _turmaId = widget.turmas.first.id;
      _carregarAlunos(_turmaId!);
    }
  }

  Future<void> _carregarAlunos(int turmaId) async {
    setState(() {
      _carregandoAlunos = true;
      _alunos = [];
      _alunoId = null;
    });
    try {
      final alunos = await _apiService.getStudentsByClass(turmaId);
      if (mounted) {
        setState(() {
          _alunos = alunos;
          _carregandoAlunos = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _carregandoAlunos = false);
    }
  }

  void _onTurmaChanged(int? value) {
    if (value == null || value == _turmaId) return;
    setState(() {
      _turmaId = value;
      _alunoId = null;
      _alunos = [];
    });
    _carregarAlunos(value);
  }

  bool get _canContinue => _turmaId != null && _alunoId != null && !_carregandoAlunos;

  void _iniciar() {
    final turma = widget.turmas.firstWhere((t) => t.id == _turmaId);
    final aluno = _alunos.firstWhere((a) => a.id == _alunoId);

    final simuladoData = SimuladoData(
      id: widget.simulado.id,
      nome: widget.simulado.titulo,
      numQuestoes: widget.simulado.questoes.length,
      dataCriacao: widget.simulado.dataCriacao,
      notaMaxima: widget.simulado.notaMaxima,
    );

    final alunoData = AlunoData(
      id: aluno.id ?? 0,
      nome: aluno.name ?? 'Aluno',
      matricula: aluno.studentId?.toString() ?? 'N/A',
      turmaNome: turma.name,
    );

    // Vai direto para a fotografia — tipo e versão já vieram do primeiro QR scan
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CartaoProcessingScreen(
          simulado: simuladoData,
          aluno: alunoData,
          tipoProva: widget.tipoProva,
          versionCode: widget.versionCode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final turmaAutoSelecionada = widget.turmas.length == 1 ? widget.turmas.first : null;

    return Scaffold(
      backgroundColor: bgLight,
      appBar: CustomAppBar(showBack: true),
      body: SafeArea(
        child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Simulado card (locked)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [primaryDark, Color(0xFF0A8CCB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.qr_code_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Simulado identificado',
                          style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.simulado.titulo,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.simulado.questoes.length} questoes  ·  ${widget.simulado.notaMaxima.toStringAsFixed(widget.simulado.notaMaxima % 1 == 0 ? 0 : 1)} pts',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Turma (auto ou dropdown)
            if (turmaAutoSelecionada != null) ...[
              _buildInfoRow(
                icon: Icons.groups_rounded,
                label: 'Turma',
                value: turmaAutoSelecionada.name,
              ),
              const SizedBox(height: 20),
            ] else ...[
              _buildLabel('Turma', Icons.groups_rounded),
              const SizedBox(height: 8),
              _buildDropdown(
                hint: 'Selecione a turma',
                value: _turmaId,
                icon: Icons.groups_rounded,
                items: widget.turmas.map((t) => DropdownMenuItem(
                  value: t.id,
                  child: Text(t.name, style: const TextStyle(color: textMain)),
                )).toList(),
                onChanged: _onTurmaChanged,
              ),
              const SizedBox(height: 20),
            ],

            // Aluno
            _buildLabel('Aluno', Icons.person_search_rounded),
            const SizedBox(height: 8),
            _carregandoAlunos
                ? Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: bgLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderLight),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
                          SizedBox(width: 10),
                          Text('Carregando alunos...', style: TextStyle(color: textSub, fontSize: 13)),
                        ],
                      ),
                    ),
                  )
                : _buildDropdown(
                    hint: _turmaId == null ? 'Selecione a turma primeiro' : 'Selecione o aluno',
                    value: _alunoId,
                    icon: Icons.person_search_rounded,
                    items: _alunos.map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name ?? '', style: const TextStyle(color: textMain)),
                    )).toList(),
                    onChanged: _alunos.isEmpty ? null : (v) => setState(() => _alunoId = v),
                    disabledHint: _turmaId == null ? 'Selecione a turma primeiro' : 'Nenhum aluno disponivel',
                  ),

            const Spacer(),

            // Botao iniciar
            SizedBox(
              height: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _canContinue
                      ? const LinearGradient(
                          colors: [Color(0xFF0A8CCB), primaryDark],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : null,
                  color: _canContinue ? null : borderLight,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _canContinue
                      ? [BoxShadow(color: primary.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))]
                      : [],
                ),
                child: ElevatedButton.icon(
                  onPressed: _canContinue ? _iniciar : null,
                  icon: Icon(Icons.camera_alt_rounded, size: 20, color: _canContinue ? Colors.white : textSub),
                  label: Text(
                    'Iniciar Leitura',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _canContinue ? Colors.white : textSub,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: primary, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: textSub.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w500)),
              Text(value, style: const TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 18),
        ],
      ),
    );
  }

  Widget _buildLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: primary, size: 18),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textMain)),
      ],
    );
  }

  Widget _buildDropdown({
    required String hint,
    required int? value,
    required IconData icon,
    required List<DropdownMenuItem<int>> items,
    required void Function(int?)? onChanged,
    String? disabledHint,
  }) {
    final bool isEnabled = onChanged != null;
    return DropdownButtonFormField<int>(
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: textSub.withOpacity(0.7), fontSize: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderLight, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderLight, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primary, width: 2)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderLight.withOpacity(0.5), width: 1)),
        filled: true,
        fillColor: isEnabled ? bgLight : borderLight.withOpacity(0.3),
        prefixIcon: Icon(icon, color: isEnabled ? primary : textSub.withOpacity(0.5), size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      value: value,
      isExpanded: true,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: isEnabled ? primary : textSub.withOpacity(0.4)),
      style: const TextStyle(color: textMain, fontSize: 14),
      dropdownColor: surfaceLight,
      borderRadius: BorderRadius.circular(14),
      items: items,
      onChanged: onChanged,
      disabledHint: disabledHint != null
          ? Text(disabledHint, style: TextStyle(color: textSub.withOpacity(0.6), fontSize: 14))
          : null,
    );
  }
}
