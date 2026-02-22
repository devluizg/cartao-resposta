// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import '../widgets/custom_app_bar.dart';
import 'package:leitor_cartao/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../main.dart';
import 'dart:developer' as developer;
import 'package:leitor_cartao/services/models/class_model.dart';
import 'package:leitor_cartao/services/models/student_model.dart';
import 'package:leitor_cartao/services/models/simulado_model.dart';

class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});

  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String _errorMessage = '';
  String userName = 'Usuário';

  List<ClassModel> _turmas = [];
  List<SimuladoModel> _simulados = [];
  List<StudentModel> _alunos = [];

  int? _turmaId;
  int? _simuladoId;
  int? _alunoId;

  // Design System - Nova Paleta de Cores (Página de Vendas)
  static const Color primary = Color(0xFF0DA6F2);       // Azul claro/primário
  static const Color primaryMedium = Color(0xFF0A8CCB); // Azul médio
  static const Color primaryDark = Color(0xFF003D5C);   // Azul escuro
  
  static const Color bgLight = Color(0xFFF8FAFC);       // Cinza super claro (fundo)
  static const Color surfaceLight = Color(0xFFFFFFFF);  // Superfície branca
  static const Color textMain = Color(0xFF003D5C);      // Texto principal (Azul Escuro)
  static const Color textSub = Color(0xFF475569);       // Texto secundário (Slate 600)
  static const Color borderLight = Color(0xFFDBE2E6);   // Bordas gerais
  
  static const Color errorColor = Color(0xFFDC2626);    // Vermelho 600
  static const Color warningColor = Color(0xFFEA580C);  // Laranja (speed icon color)

  @override
  void initState() {
    super.initState();
    _iniciarApp();
  }

  Future<void> _iniciarApp() async {
    await _carregarNomeUsuario();
    await _verificarConexao();
  }

  Future<void> _verificarConexao() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final token = await _apiService.getAccessToken();
      if (token == null) {
        developer.log('Token de autenticação ausente');
        setState(() {
          _errorMessage = 'Sessão expirada. Por favor, faça login novamente.';
          _isLoading = false;
        });
        return;
      }

      bool conectado = await _apiService.testConnection();
      if (conectado) {
        developer.log('Conexão com a API estabelecida com sucesso');
        await _carregarTurmas();
      } else {
        setState(() {
          _errorMessage =
              'Não foi possível conectar ao servidor. Verifique sua conexão.';
          _isLoading = false;
        });
      }
    } catch (e) {
      developer.log('Erro ao verificar conexão: $e');
      setState(() {
        _errorMessage = 'Erro ao verificar conexão com o servidor: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _carregarNomeUsuario() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nome = prefs.getString('user_name');
      if (nome != null && mounted) {
        setState(() {
          userName = nome;
        });
      } else {
        final userInfo = await _apiService.getUserInfo();
        if (userInfo != null && mounted) {
          setState(() {
            userName = userInfo['name'] ?? 'Usuário';
          });
        }
      }
    } catch (e) {
      developer.log('Erro ao carregar nome do usuário: $e');
    }
  }

  Future<void> _carregarTurmas() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      developer.log('Solicitando turmas da API...');
      final turmas = await _apiService.getClasses();
      developer.log('Turmas recebidas: ${turmas.length}');

      if (mounted) {
        setState(() {
          _turmas = turmas;
          _isLoading = false;

          if (turmas.isEmpty) {
            _errorMessage =
                'Nenhuma turma encontrada. Verifique se existem turmas cadastradas no sistema.';
          }
        });
      }
    } catch (e) {
      developer.log('Erro ao carregar turmas: $e');
      if (mounted) {
        if (e.toString().contains('401')) {
          try {
            bool tokenRenovado = await _apiService.refreshToken();
            if (tokenRenovado) {
              return _carregarTurmas();
            } else {
              _logout();
              return;
            }
          } catch (_) {
            _logout();
            return;
          }
        }

        setState(() {
          _errorMessage = 'Erro ao carregar turmas: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _carregarSimulados(int turmaId) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _simulados = [];
      _simuladoId = null;
    });

    try {
      developer.log('Solicitando simulados para a turma ID: $turmaId');
      final simulados = await _apiService.getSimuladosByClass(turmaId);
      developer.log('Simulados recebidos: ${simulados.length}');

      if (mounted) {
        setState(() {
          _simulados = simulados;
          _isLoading = false;

          if (simulados.isEmpty) {
            _errorMessage = 'Nenhum simulado encontrado para esta turma.';
          }
        });
      }
    } catch (e) {
      developer.log('Erro ao carregar simulados: $e');
      if (mounted) {
        if (e.toString().contains('401')) {
          try {
            bool tokenRenovado = await _apiService.refreshToken();
            if (tokenRenovado) {
              return _carregarSimulados(turmaId);
            }
          } catch (_) {}
        }

        setState(() {
          _errorMessage = 'Erro ao carregar simulados: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _carregarAlunos(int turmaId) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _alunos = [];
      _alunoId = null;
    });

    try {
      developer.log('Solicitando alunos para a turma ID: $turmaId');
      final alunos = await _apiService.getStudentsByClass(turmaId);
      developer.log('Alunos recebidos: ${alunos.length}');

      if (mounted) {
        setState(() {
          _alunos = alunos;
          _isLoading = false;

          if (alunos.isEmpty) {
            _errorMessage = 'Nenhum aluno encontrado para esta turma.';
          }
        });
      }
    } catch (e) {
      developer.log('Erro ao carregar alunos: $e');
      if (mounted) {
        if (e.toString().contains('401')) {
          try {
            bool tokenRenovado = await _apiService.refreshToken();
            if (tokenRenovado) {
              return _carregarAlunos(turmaId);
            }
          } catch (_) {}
        }

        setState(() {
          _errorMessage = 'Erro ao carregar alunos: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onTurmaChanged(int? value) {
    if (value != null && value != _turmaId) {
      setState(() {
        _turmaId = value;
        _simuladoId = null;
        _alunoId = null;
        _simulados = [];
        _alunos = [];
      });
      developer.log('Turma selecionada: $value');
      _carregarSimulados(value);
      _carregarAlunos(value);
    }
  }

  void _onSimuladoChanged(int? value) {
    setState(() {
      _simuladoId = value;
    });
    developer.log('Simulado selecionado: $value');
  }

  void _onAlunoChanged(int? value) {
    setState(() {
      _alunoId = value;
    });
    developer.log('Aluno selecionado: $value');
  }

  void _continuarParaLeitor() {
    if (_turmaId == null || _simuladoId == null || _alunoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Por favor, selecione todos os campos'),
            ],
          ),
          backgroundColor: warningColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    final alunoSelecionado = _alunos.firstWhere(
      (aluno) => aluno.id == _alunoId,
      orElse: () => StudentModel(
        id: _alunoId!,
        name: 'Desconhecido',
        email: '',
        studentId: '',
        classes: [],
      ),
    );

    final simuladoSelecionado = _simulados.firstWhere(
      (simulado) => simulado.id == _simuladoId,
      orElse: () => SimuladoModel(
        id: _simuladoId!,
        titulo: 'Desconhecido',
        descricao: '',
        questoes: [],
        dataCriacao: DateTime.now(),
        ultimaModificacao: DateTime.now(),
        classes: [_turmaId!],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final turmaSelecionada = _turmas.firstWhere(
      (turma) => turma.id == _turmaId,
      orElse: () => ClassModel(
        id: _turmaId!,
        name: 'Turma Desconhecida',
        description: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    developer.log(
        'Navegando para TelaInicial com: Turma=$_turmaId (${turmaSelecionada.name}), Simulado=$_simuladoId (${simuladoSelecionado.titulo}), Aluno=$_alunoId (${alunoSelecionado.name})');

    final alunoMap = {
      'id': alunoSelecionado.id,
      'nome': alunoSelecionado.name,
    };

    final simuladoMap = {
      'id': simuladoSelecionado.id,
      'titulo': simuladoSelecionado.titulo,
    };

    final turmaMap = {
      'id': turmaSelecionada.id,
      'nome': turmaSelecionada.name,
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TelaInicial(
          turmaId: _turmaId!,
          simuladoId: _simuladoId!,
          alunoId: _alunoId!,
          aluno: alunoMap,
          simulado: simuladoMap,
          turma: turmaMap,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.remove('user_name');
      await prefs.remove('user_email');

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Text('Erro ao fazer logout: $e'),
              ],
            ),
            backgroundColor: errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _recarregarDados() async {
    _resetSelections();
    await _verificarConexao();
  }

  void _resetSelections() {
    setState(() {
      _turmaId = null;
      _simuladoId = null;
      _alunoId = null;
      _simulados = [];
      _alunos = [];
    });
  }

  bool get _canContinue =>
      !_isLoading &&
      _turmaId != null &&
      _simuladoId != null &&
      _alunoId != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: CustomAppBar(
        onReload: _recarregarDados,
        onExit: _logout,
      ),

      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(primary),
                      backgroundColor: borderLight,
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Carregando dados...',
                    style: TextStyle(
                      fontSize: 16,
                      color: textSub,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _recarregarDados,
              color: primary,
              backgroundColor: surfaceLight,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header boas-vindas com logo e gradiente
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [primaryDark, primaryMedium],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: primaryDark,
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Avatar do usuário
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.4),
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bem-vindo(a)!',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    userName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),

                                    ),
                                    child: const Text(
                                      'Professor',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Título da seção
                      const Text(
                        'Configurar Correção',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textMain,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Selecione a turma, o simulado e o aluno para iniciar',
                        style: TextStyle(
                          fontSize: 13,
                          color: textSub,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Card com formulário de seleção
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: surfaceLight,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: primary.withOpacity(0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: primary.withOpacity(0.08),
                              blurRadius: 40,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Dropdown Turma
                            _buildDropdownLabel(
                                'Turma', Icons.groups_rounded),
                            const SizedBox(height: 8),
                            _buildDropdown(
                              hint: 'Selecione uma turma',
                              value: _turmaId,
                              icon: Icons.groups_rounded,
                              items: _turmas.map((turma) {
                                return DropdownMenuItem<int>(
                                  value: turma.id,
                                  child: Text(
                                    turma.name,
                                    style: const TextStyle(color: textMain),
                                  ),
                                );
                              }).toList(),
                              onChanged: _onTurmaChanged,
                            ),

                            const SizedBox(height: 20),

                            // Dropdown Simulado
                            _buildDropdownLabel(
                                'Simulado', Icons.quiz_rounded),
                            const SizedBox(height: 8),
                            _buildDropdown(
                              hint: _turmaId == null
                                  ? 'Selecione uma turma primeiro'
                                  : 'Selecione um simulado',
                              value: _simuladoId,
                              icon: Icons.quiz_rounded,
                              items: _simulados.map((simulado) {
                                return DropdownMenuItem<int>(
                                  value: simulado.id,
                                  child: Text(
                                    simulado.titulo,
                                    style: const TextStyle(color: textMain),
                                  ),
                                );
                              }).toList(),
                              onChanged: _simulados.isEmpty
                                  ? null
                                  : _onSimuladoChanged,
                              disabledHint: _turmaId == null
                                  ? 'Selecione uma turma primeiro'
                                  : _isLoading
                                      ? 'Carregando simulados...'
                                      : 'Nenhum simulado disponível',
                            ),

                            const SizedBox(height: 20),

                            // Dropdown Aluno
                            _buildDropdownLabel(
                                'Aluno', Icons.person_search_rounded),
                            const SizedBox(height: 8),
                            _buildDropdown(
                              hint: _turmaId == null
                                  ? 'Selecione uma turma primeiro'
                                  : 'Selecione um aluno',
                              value: _alunoId,
                              icon: Icons.person_search_rounded,
                              items: _alunos.map((aluno) {
                                return DropdownMenuItem<int>(
                                  value: aluno.id,
                                  child: Text(
                                    aluno.name,
                                    style: const TextStyle(color: textMain),
                                  ),
                                );
                              }).toList(),
                              onChanged:
                                  _alunos.isEmpty ? null : _onAlunoChanged,
                              disabledHint: _turmaId == null
                                  ? 'Selecione uma turma primeiro'
                                  : _isLoading
                                      ? 'Carregando alunos...'
                                      : 'Nenhum aluno disponível',
                            ),
                          ],
                        ),
                      ),

                      // Mensagem de erro
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: errorColor.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: errorColor.withOpacity(0.4), width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.error_outline_rounded,
                                      color: errorColor, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Atenção',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: errorColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _errorMessage,
                                style: TextStyle(
                                  color: errorColor.withOpacity(0.85),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _recarregarDados,
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 18),
                                  label: const Text('Tentar Novamente'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: errorColor,
                                    side: BorderSide(
                                        color: errorColor.withOpacity(0.5)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),

                      // Botão continuar
                      SizedBox(
                        height: 56,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: _canContinue
                                ? const LinearGradient(
                                    colors: [primaryMedium, primaryDark],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  )
                                : null,
                            color: _canContinue ? null : borderLight,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: _canContinue
                                ? [
                                    BoxShadow(
                                      color: primary.withOpacity(0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ]
                                : [],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _canContinue ? _continuarParaLeitor : null,
                            icon: Icon(
                              Icons.camera_alt_rounded,
                              size: 20,
                              color: _canContinue ? Colors.white : textSub,
                            ),
                            label: Text(
                              'Iniciar Leitura',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _canContinue ? Colors.white : textSub,
                                letterSpacing: 0.3,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              disabledBackgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildDropdownLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: primary, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textMain,
          ),
        ),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderLight, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderLight, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderLight.withOpacity(0.5), width: 1),
        ),
        filled: true,
        fillColor: isEnabled ? bgLight : borderLight.withOpacity(0.3),
        prefixIcon: Icon(icon,
            color: isEnabled ? primary : textSub.withOpacity(0.5), size: 20),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      value: value,
      isExpanded: true,
      icon: Icon(Icons.keyboard_arrow_down_rounded,
          color: isEnabled ? primary : textSub.withOpacity(0.4)),
      style: const TextStyle(color: textMain, fontSize: 14),
      dropdownColor: surfaceLight,
      borderRadius: BorderRadius.circular(14),
      items: items,
      onChanged: onChanged,
      disabledHint: disabledHint != null
          ? Text(disabledHint,
              style: TextStyle(
                  color: textSub.withOpacity(0.6),
                  fontSize: 14))
          : null,
    );
  }
}
