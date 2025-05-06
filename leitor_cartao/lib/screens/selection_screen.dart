import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leitor_cartao/services/auth_service.dart';
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

  // Usar os modelos de dados em vez de Map<String, dynamic>
  List<ClassModel> _turmas = [];
  List<SimuladoModel> _simulados = [];
  List<StudentModel> _alunos = [];

  int? _turmaId;
  int? _simuladoId;
  int? _alunoId;

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
      // Verificar token de autenticação
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
              'Não foi possível conectar ao servidor. Verifique se o servidor está rodando.';
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
        // Se não encontrar o nome, tenta buscar novamente da API
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
      // Usar o método getClasses() em vez de getTurmas()
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
          // Tenta renovar o token e tentar novamente
          try {
            bool tokenRenovado = await _apiService.refreshToken();
            if (tokenRenovado) {
              return _carregarTurmas();
            } else {
              _logout(); // Token não pode ser renovado, faça logout
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
      // Usar o método getSimuladosByClass() em vez de getSimuladosPorTurma()
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
      // Usar o método getStudentsByClass() em vez de getAlunosPorTurma()
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
        const SnackBar(
          content: Text('Por favor, selecione todos os campos'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Encontra os objetos selecionados
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
      ),
    );

    developer.log(
        'Navegando para TelaInicial com: Turma=$_turmaId, Simulado=$_simuladoId, Aluno=$_alunoId');

    // Converter para Map para manter a compatibilidade com a classe TelaInicial
    final alunoMap = {
      'id': alunoSelecionado.id,
      'nome': alunoSelecionado.name,
    };

    final simuladoMap = {
      'id': simuladoSelecionado.id,
      'titulo': simuladoSelecionado.titulo,
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
        ),
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await AuthService.logout();

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer logout: $e'),
            backgroundColor: Colors.red,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecionar Turma e Aluno'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: _recarregarDados,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Carregando dados...'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _recarregarDados,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bem-vindo(a), $userName!',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Selecione a turma, o simulado e o aluno para iniciar a correção do cartão resposta.',
                                style: TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Dados da Correção',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                  labelText: 'Turma',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.group),
                                ),
                                value: _turmaId,
                                hint: const Text('Selecione uma turma'),
                                isExpanded: true,
                                items: _turmas.map((turma) {
                                  return DropdownMenuItem<int>(
                                    value: turma.id,
                                    child: Text(turma.name),
                                  );
                                }).toList(),
                                onChanged: _onTurmaChanged,
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                  labelText: 'Simulado',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.assignment),
                                ),
                                value: _simuladoId,
                                hint: _turmaId == null
                                    ? const Text('Selecione uma turma primeiro')
                                    : const Text('Selecione um simulado'),
                                isExpanded: true,
                                items: _simulados.map((simulado) {
                                  return DropdownMenuItem<int>(
                                    value: simulado.id,
                                    child: Text(simulado.titulo),
                                  );
                                }).toList(),
                                onChanged: _simulados.isEmpty
                                    ? null
                                    : _onSimuladoChanged,
                                disabledHint: _turmaId == null
                                    ? const Text('Selecione uma turma primeiro')
                                    : _isLoading
                                        ? const Text('Carregando simulados...')
                                        : const Text(
                                            'Nenhum simulado disponível'),
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                  labelText: 'Aluno',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person),
                                ),
                                value: _alunoId,
                                hint: _turmaId == null
                                    ? const Text('Selecione uma turma primeiro')
                                    : const Text('Selecione um aluno'),
                                isExpanded: true,
                                items: _alunos.map((aluno) {
                                  return DropdownMenuItem<int>(
                                    value: aluno.id,
                                    child: Text(aluno.name),
                                  );
                                }).toList(),
                                onChanged:
                                    _alunos.isEmpty ? null : _onAlunoChanged,
                                disabledHint: _turmaId == null
                                    ? const Text('Selecione uma turma primeiro')
                                    : _isLoading
                                        ? const Text('Carregando alunos...')
                                        : const Text('Nenhum aluno disponível'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_errorMessage.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _errorMessage,
                                style: TextStyle(color: Colors.red[900]),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _recarregarDados,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red[100],
                                  foregroundColor: Colors.red[900],
                                ),
                                child: const Text('Tentar Novamente'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: (_isLoading ||
                                _turmaId == null ||
                                _simuladoId == null ||
                                _alunoId == null)
                            ? null
                            : _continuarParaLeitor,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Continuar para Leitura'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
