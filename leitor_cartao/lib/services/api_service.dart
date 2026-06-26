//api_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models/class_model.dart';
import 'models/student_model.dart';
import 'models/simulado_model.dart';
import 'models/resultado_model.dart';
import 'dart:async';
import 'dart:developer' as developer;

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String prodUrl  = 'https://simuladoapp.com.br';
  static const String _serverKey = 'server_url';

  String baseUrl = prodUrl;
  final Duration timeoutDuration = const Duration(seconds: 30);

  void setBaseUrl(String url) {
    baseUrl = url;
  }

  /// Carrega a URL salva pelo usuário (ou usa produção como padrão).
  Future<void> loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_serverKey) ?? prodUrl;
  }

  /// Persiste a URL atual para sobreviver a reinicializações do app.
  Future<void> saveCurrentUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, baseUrl);
  }

  /// Remove a URL salva e volta para produção.
  Future<void> resetToProduction() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serverKey);
    baseUrl = prodUrl;
  }

  // Get the stored access token
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  // Get auth headers for API requests
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getAccessToken(); // Usar método local
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Login method - Fixed to match Django Rest Framework SimpleJWT format
  Future<bool> login(String username, String password) async {
    print('\n=== API_SERVICE: Iniciando login ===');
    print('URL: $baseUrl/api/token/');
    print('Email: $username');
    print('Senha fornecida: ${password.isNotEmpty ? "Sim (${password.length} chars)" : "NÃO"}');

    try {
      final uri = Uri.parse('$baseUrl/api/token/');
      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({
        'email': username,
        'password': password,
      });

      print('URI: $uri');
      print('Headers: $headers');
      print('Body sendo enviado: $body');

      print('Enviando requisição POST...');
      final response = await http
          .post(
        uri,
        headers: headers,
        body: body,
      )
          .timeout(const Duration(seconds: 30), onTimeout: () {
        print('❌ TIMEOUT: Requisição expirou após 30 segundos');
        debugPrint('Requisição de login expirou após 30 segundos');
        throw TimeoutException(
            'A conexão expirou. Verifique sua conexão com a internet.');
      });

      print('✅ Resposta recebida!');
      print('Status Code: ${response.statusCode}');
      print('Response Headers: ${response.headers}');
      print('Response Body: ${response.body}');

      debugPrint(
          'Login status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Status 200 - Login bem-sucedido!');
        final tokenData = jsonDecode(response.body);
        print('Token data decodificado: $tokenData');
        print('Access token presente: ${tokenData.containsKey("access")}');
        print('Refresh token presente: ${tokenData.containsKey("refresh")}');

        final prefs = await SharedPreferences.getInstance();

        // Store tokens - SimpleJWT returns access and refresh tokens
        await prefs.setString('access_token', tokenData['access']);
        await prefs.setString('refresh_token', tokenData['refresh']);
        print('✅ Tokens salvos no SharedPreferences');

        // Fetch user info
        print('Buscando informações do usuário...');
        await getUserInfo();
        print('✅ Informações do usuário obtidas');
        return true;
      } else {
        print('❌ Login falhou - Status: ${response.statusCode}');
        print('❌ Resposta do servidor: ${response.body}');
        debugPrint('Login failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } on TimeoutException catch (e) {
      print('❌ TIMEOUT EXCEPTION: $e');
      debugPrint('Login timeout');
      return false;
    } catch (e, stackTrace) {
      print('❌ EXCEPTION durante login no ApiService:');
      print('Tipo: ${e.runtimeType}');
      print('Erro: $e');
      print('Stack trace:');
      print(stackTrace);
      debugPrint('Exception during login: $e');
      return false;
    }
  }

  // Refresh token method
  Future<bool> refreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');

      if (refreshToken == null) {
        return false;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refresh': refreshToken,
        }),
      );

      if (response.statusCode == 200) {
        final tokenData = jsonDecode(response.body);
        await prefs.setString('access_token', tokenData['access']);
        return true;
      } else {
        debugPrint(
            'Token refresh failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Exception during token refresh: $e');
      return false;
    }
  }

  // Get user information
  Future<Map<String, dynamic>?> getUserInfo() async {
    print('\n=== API_SERVICE: Obtendo informações do usuário ===');
    print('URL: $baseUrl/api/user-info/');

    try {
      final headers = await getAuthHeaders();
      print('Headers: $headers');
      print('Enviando requisição GET...');

      final response = await http.get(
        Uri.parse('$baseUrl/api/user-info/'),
        headers: headers,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('❌ TIMEOUT: getUserInfo expirou após 15 segundos');
          throw TimeoutException('Timeout ao obter informações do usuário');
        },
      );

      print('✅ Resposta recebida!');
      print('Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Informações do usuário obtidas com sucesso');
        final userData = jsonDecode(response.body);
        print('User data: $userData');

        final prefs = await SharedPreferences.getInstance();

        // Save user data
        await prefs.setString('user_name', userData['name']);
        await prefs.setString('user_email', userData['email']);
        print('✅ Dados do usuário salvos no SharedPreferences');

        return userData;
      } else if (response.statusCode == 401) {
        print('⚠️ Status 401 - Token expirado, tentando refresh...');
        // Token expired, try to refresh
        final refreshed = await refreshToken();
        if (refreshed) {
          print('✅ Token refreshed, tentando novamente...');
          // Retry with new token
          return getUserInfo();
        }
        print('❌ Falha ao refresh token');
        debugPrint('Failed to get user info: Token expired and refresh failed');
        return null;
      } else {
        print('❌ Falha ao obter user info - Status: ${response.statusCode}');
        print('❌ Resposta: ${response.body}');
        debugPrint(
            'Failed to get user info: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      print('❌ EXCEPTION ao obter user info:');
      print('Tipo: ${e.runtimeType}');
      print('Erro: $e');
      print('Stack trace:');
      print(stackTrace);
      debugPrint('Exception getting user info: $e');
      return null;
    }
  }

  // Generic authorized request method with token refresh and timeout
  Future<http.Response> authorizedRequest(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool retry = true,
  }) async {
    try {
      final headers = await getAuthHeaders();
      Uri uri = Uri.parse('$baseUrl$endpoint');
      late http.Response response;

      debugPrint('Making $method request to: $uri');
      if (body != null) {
        debugPrint('Request body: $body');
      }

      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(
            timeoutDuration,
            onTimeout: () {
              debugPrint('Requisição GET expirou: $uri');
              throw TimeoutException(
                  'A conexão expirou. Verifique sua internet e tente novamente.');
            },
          );
          break;
        case 'POST':
          response = await http
              .post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
              .timeout(
            timeoutDuration,
            onTimeout: () {
              debugPrint('Requisição POST expirou: $uri');
              throw TimeoutException(
                  'A conexão expirou. Verifique sua internet e tente novamente.');
            },
          );
          break;
        case 'PUT':
          response = await http
              .put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
              .timeout(
            timeoutDuration,
            onTimeout: () {
              debugPrint('Requisição PUT expirou: $uri');
              throw TimeoutException(
                  'A conexão expirou. Verifique sua internet e tente novamente.');
            },
          );
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers).timeout(
            timeoutDuration,
            onTimeout: () {
              debugPrint('Requisição DELETE expirou: $uri');
              throw TimeoutException(
                  'A conexão expirou. Verifique sua internet e tente novamente.');
            },
          );
          break;
        default:
          throw Exception('Unsupported HTTP method');
      }

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      // Handle token expiration
      if (response.statusCode == 401 && retry) {
        final refreshed = await refreshToken();
        if (refreshed) {
          // Retry the request with new token
          return authorizedRequest(
            endpoint,
            method: method,
            body: body,
            retry: false,
          );
        }
      }

      return response;
    } catch (e) {
      debugPrint('Exception in authorized request: $e');
      rethrow;
    }
  }

  // Get application configuration
  Future<Map<String, dynamic>?> getAppConfig() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/app-config/'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint(
            'Failed to get app config: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception getting app config: $e');
      return null;
    }
  }

  // Test API connection
  Future<bool> testConnection() async {
    print('\n=== API_SERVICE: Testando conexão ===');
    print('URL de teste: $baseUrl/api/test-connection/');

    try {
      final uri = Uri.parse('$baseUrl/api/test-connection/');
      print('URI: $uri');
      print('Enviando requisição GET...');

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('❌ TIMEOUT: Teste de conexão expirou após 10 segundos');
          throw TimeoutException('Timeout ao testar conexão');
        },
      );

      print('✅ Resposta recebida!');
      print('Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      final success = response.statusCode == 200;
      print(success ? '✅ Teste de conexão bem-sucedido!' : '❌ Teste de conexão falhou');
      return success;
    } catch (e, stackTrace) {
      print('❌ ERRO no teste de conexão:');
      print('Tipo: ${e.runtimeType}');
      print('Erro: $e');
      print('Stack trace:');
      print(stackTrace);
      debugPrint('Connection test failed: $e');
      return false;
    }
  }

  // Get all classes (turmas)
  Future<List<ClassModel>> getClasses() async {
    try {
      final response = await authorizedRequest('/api/classes/');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<ClassModel> classes = [];

        // Handle both paginated and non-paginated responses
        if (data is Map && data.containsKey('results')) {
          // Paginated response
          final results = data['results'] as List;
          classes = results.map((json) => ClassModel.fromJson(json)).toList();
        } else if (data is List) {
          // Direct list response
          classes = data.map((json) => ClassModel.fromJson(json)).toList();
        }

        debugPrint('Retrieved ${classes.length} classes');
        return classes;
      } else {
        debugPrint(
            'Failed to get classes: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Exception getting classes: $e');
      return [];
    }
  }

  // Get students for a specific class
  Future<List<StudentModel>> getStudentsByClass(int classId) async {
    try {
      final response =
          await authorizedRequest('/api/classes/$classId/students/');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<StudentModel> students = [];

        // Handle both paginated and non-paginated responses
        if (data is Map && data.containsKey('results')) {
          // Paginated response
          final results = data['results'] as List;
          students =
              results.map((json) => StudentModel.fromJson(json)).toList();
        } else if (data is List) {
          // Direct list response
          students = data.map((json) => StudentModel.fromJson(json)).toList();
        }

        debugPrint('Retrieved ${students.length} students for class $classId');
        return students;
      } else {
        debugPrint(
            'Failed to get students: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Exception getting students: $e');
      return [];
    }
  }

  // Get simulados for a specific class
  Future<List<SimuladoModel>> getSimuladosByClass(int classId) async {
    try {
      final response =
          await authorizedRequest('/api/classes/$classId/simulados/');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<SimuladoModel> simulados = [];

        // Handle both paginated and non-paginated responses
        if (data is Map && data.containsKey('results')) {
          // Paginated response
          final results = data['results'] as List;
          simulados =
              results.map((json) => SimuladoModel.fromJson(json)).toList();
        } else if (data is List) {
          // Direct list response
          simulados = data.map((json) => SimuladoModel.fromJson(json)).toList();
        }

        debugPrint(
            'Retrieved ${simulados.length} simulados for class $classId');
        return simulados;
      } else {
        debugPrint(
            'Failed to get simulados: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Exception getting simulados: $e');
      return [];
    }
  }

  // Get all turmas with better error handling and debugging
  Future<List<Map<String, dynamic>>> getTurmas() async {
    try {
      debugPrint('Fetching all turmas...');
      final response = await authorizedRequest('/api/classes/');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> turmas = [];

        // Handle paginated response
        if (data is Map && data.containsKey('results')) {
          turmas = List<Map<String, dynamic>>.from(data['results']);
        }
        // Handle direct list response
        else if (data is List) {
          turmas = List<Map<String, dynamic>>.from(data);
        }

        debugPrint('Successfully retrieved ${turmas.length} turmas');
        return turmas;
      } else {
        debugPrint(
            'Failed to get turmas: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Exception getting turmas: $e');
      return [];
    }
  }

  // Get simulados for a specific turma with better error handling
  Future<List<Map<String, dynamic>>> getSimuladosPorTurma(int turmaId) async {
    try {
      debugPrint('Fetching simulados for turma $turmaId...');
      final response =
          await authorizedRequest('/api/classes/$turmaId/simulados/');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> simulados = [];

        // Handle paginated response
        if (data is Map && data.containsKey('results')) {
          simulados = List<Map<String, dynamic>>.from(data['results']);
        }
        // Handle direct list response
        else if (data is List) {
          simulados = List<Map<String, dynamic>>.from(data);
        }

        debugPrint(
            'Successfully retrieved ${simulados.length} simulados for turma $turmaId');
        return simulados;
      } else {
        debugPrint(
            'Failed to get simulados: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Exception getting simulados: $e');
      return [];
    }
  }

  // Get alunos for a specific turma with better error handling
  Future<List<Map<String, dynamic>>> getAlunosPorTurma(int turmaId) async {
    try {
      debugPrint('Fetching alunos for turma $turmaId...');
      final response =
          await authorizedRequest('/api/classes/$turmaId/students/');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> alunos = [];

        // Handle paginated response
        if (data is Map && data.containsKey('results')) {
          alunos = List<Map<String, dynamic>>.from(data['results']);
        }
        // Handle direct list response
        else if (data is List) {
          alunos = List<Map<String, dynamic>>.from(data);
        }

        debugPrint(
            'Successfully retrieved ${alunos.length} alunos for turma $turmaId');
        return alunos;
      } else {
        debugPrint(
            'Failed to get alunos: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Exception getting alunos: $e');
      return [];
    }
  }

  // Get a specific simulado's details
  Future<SimuladoModel?> getSimulado(int simuladoId) async {
    try {
      final response = await authorizedRequest('/api/simulados/$simuladoId/');

      if (response.statusCode == 200) {
        return SimuladoModel.fromJson(jsonDecode(response.body));
      } else {
        debugPrint(
            'Failed to get simulado: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception getting simulado: $e');
      return null;
    }
  }

// MÉTODO ATUALIZADO: Buscar detalhes completos do simulado incluindo pontuação total
  Future<Map<String, dynamic>?> getSimuladoDetalhes(int simuladoId) async {
    try {
      debugPrint('🔍 Buscando detalhes completos do simulado $simuladoId...');

      // ✅ USAR O ENDPOINT /detalhes/ que funciona!
      final response =
          await authorizedRequest('/api/simulados/$simuladoId/detalhes/');

      debugPrint('🔍 Status da resposta: ${response.statusCode}');
      debugPrint('🔍 Corpo da resposta: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        debugPrint('🔍 Dados decodificados: $data');

        // ✅ Retornar os dados exatamente como vêm da API
        final detalhes = {
          'id': data['id'],
          'titulo': data['titulo'] ?? 'Simulado',
          'descricao': data['descricao'] ?? '',
          'numero_questoes':
              data['numero_questoes'] ?? 10, // ✅ Este campo já vem correto!
          'pontuacao_total': data['pontuacao_total'] ?? 10,
          'data_criacao': data['data_criacao'],
          'ultima_modificacao': data['ultima_modificacao'],
        };

        debugPrint('🔍 Detalhes finais sendo retornados: $detalhes');
        debugPrint('🔍 numero_questoes final: ${detalhes['numero_questoes']}');

        return detalhes;
      }

      // ✅ Fallback para endpoint básico se o /detalhes/ falhar
      debugPrint('🔍 Endpoint de detalhes falhou, tentando endpoint básico...');
      final basicResponse =
          await authorizedRequest('/api/simulados/$simuladoId/');

      if (basicResponse.statusCode == 200) {
        final basicData = jsonDecode(basicResponse.body);

        // ✅ Se o endpoint básico tem numero_questoes, usar ele
        final detalhes = {
          'id': basicData['id'],
          'titulo': basicData['titulo'] ?? 'Simulado',
          'descricao': basicData['descricao'] ?? '',
          'numero_questoes': basicData['numero_questoes'] ??
              (basicData['questoes'] is List
                  ? (basicData['questoes'] as List).length
                  : 10),
          'pontuacao_total': basicData['pontuacao_total'] ?? 10,
          'data_criacao': basicData['data_criacao'],
          'ultima_modificacao': basicData['ultima_modificacao'],
        };

        debugPrint('🔍 Fallback - detalhes retornados: $detalhes');
        return detalhes;
      }

      debugPrint('🔍 Falha em ambos os endpoints');
      return null;
    } catch (e) {
      debugPrint('🔍 Exceção ao buscar detalhes do simulado: $e');
      return null;
    }
  }

  // Get the answer key (gabarito) for a simulado
  Future<Map<String, String>?> getGabarito(int simuladoId,
      {required String tipo, String? versionCode}) async {
    try {
      debugPrint(
          '🔍 Solicitando gabarito para simulado $simuladoId, tipo: $tipo, versao_id: $versionCode');

      var url = '/api/simulados/$simuladoId/gabarito/?versao=versao$tipo&tipo=$tipo';
      if (versionCode != null && versionCode.isNotEmpty) {
        url += '&versao_id=$versionCode';
      }

      final response = await authorizedRequest(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('🚀 DEBUG: Gabarito recebido do servidor!');
        print('🚀 DADOS COMPLETOS: ${response.body}');
        debugPrint('📋 Gabarito (Processado): ${data['gabarito']}');
        return Map<String, String>.from(data['gabarito']);
      } else {
        debugPrint('❌ Falha ao obter gabarito: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Erro ao obter gabarito: $e');
      return null;
    }
  }

  // Submit student's answers for a simulado
  Future<ResultadoModel?> submitAnswers({
    required int studentId,
    required int simuladoId,
    required Map<String, String> answers,
    required String tipo, // Adicionado o parâmetro tipo
  }) async {
    try {
      // Mapear o tipo da prova do app para a versão correta no backend
      String versao =
          'versao$tipo'; // Converte tipo1 para versao1, tipo2 para versao2, etc.

      final requestBody = {
        'aluno_id': studentId,
        'simulado_id': simuladoId,
        'respostas': answers,
        'versao': versao, // Adicionado a versão para o backend
        'tipo_prova': tipo, // Adicionado o tipo de prova
      };

      print('🚀 DEBUG: Enviando correção para o backend!');
      print('🚀 URL: /api/simulados/$simuladoId/corrigir/');
      print('🚀 BODY: ${jsonEncode(requestBody)}');

      final response = await authorizedRequest(
        '/api/simulados/$simuladoId/corrigir/',
        method: 'POST',
        body: requestBody,
      );

      if (response.statusCode == 200) {
        return ResultadoModel.fromJson(jsonDecode(response.body));
      } else {
        debugPrint(
            'Failed to submit answers: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception submitting answers: $e');
      return null;
    }
  }

  // Process card image with Python backend
  Future<Map<String, dynamic>?> processCardImage({
    required String imageFilePath,
    required int numQuestions,
    required int numColumns,
    required int threshold,
    required String serverAddress,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://$serverAddress/processar_cartao'),
      );

      // Add image file
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        imageFilePath,
      ));

      // Add parameters
      request.fields['num_questoes'] = numQuestions.toString();
      request.fields['num_colunas'] = numColumns.toString();
      request.fields['threshold'] = threshold.toString();
      request.fields['retornar_imagens'] = 'true';

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint(
            'Failed to process image: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception processing image: $e');
      return null;
    }
  }

  // Process card image via Django backend (Claude Vision + OpenCV fallback)
  Future<Map<String, dynamic>?> processCardImageViaBackend({
    required String imageFilePath,
    required int numQuestoes,
    int? cartaoVersao,
  }) async {
    try {
      final token = await getAccessToken();
      final uri = Uri.parse('$baseUrl/api/processar-imagem-cartao/');

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(await http.MultipartFile.fromPath(
        'file',
        imageFilePath,
      ));
      request.fields['num_questoes'] = numQuestoes.toString();
      // v3: informa ao backend qual layout do cartão foi fotografado.
      // 3 = fiduciais ao redor da grade → deskew apertado. null/ausente = v2
      // legado (caminho congelado). O backend já aceita o campo (views_omr.py).
      if (cartaoVersao != null) {
        request.fields['cartao_versao'] = cartaoVersao.toString();
      }

      print('📤 Enviando imagem para backend Django '
          '(num_questoes=$numQuestoes, cartao_versao=${cartaoVersao ?? "v2"})...');

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('Backend timeout (>60s)'),
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Backend respondeu via método: ${data['metodo']}');
        return data;
      } else {
        debugPrint('❌ Backend falhou: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao processar via backend: $e');
      return null;
    }
  }

  // Send student results back to the Django website
  Future<bool> submitStudentResults({
    required int studentId,
    required int simuladoId,
    required String versao,
    required double nota,
    required Map<String, String> respostasAluno,
    required Map<String, String> gabarito,
    String? versionCode,
  }) async {
    try {
      final requestBody = {
        'aluno_id': studentId,
        'simulado_id': simuladoId,
        'versao': versao,
        'nota_final': nota,
        'respostas_aluno': respostasAluno,
        'gabarito': gabarito,
        'percentual_acerto': (nota / 10 * 100).toStringAsFixed(1),
        if (versionCode != null && versionCode.isNotEmpty)
          'versao_gabarito_code': versionCode,
      };

      print('🚀 DEBUG: Enviando submissão de resultado para o site!');
      print('🚀 URL: /api/resultados/submit/');
      print('🚀 BODY: ${jsonEncode(requestBody)}');

      final response = await authorizedRequest(
        '/api/resultados/submit/',
        method: 'POST',
        body: requestBody,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('Results successfully submitted to the website');
        return true;
      } else {
        debugPrint(
            'Failed to submit results: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Exception submitting results: $e');
      return false;
    }
  }

  // Combine processing results with Django backend
  Future<ResultadoModel?> processAndSubmitAnswers({
    required int studentId,
    required int simuladoId,
    required Map<String, String> detectedAnswers,
    required String tipo, // Adicionado o parâmetro tipo
  }) async {
    try {
      // Mapear o tipo da prova do app para a versão correta no backend
      String versao =
          'versao$tipo'; // Converte tipo1 para versao1, tipo2 para versao2, etc.

      final response = await authorizedRequest(
        '/api/procesar-cartao/',
        method: 'POST',
        body: {
          'aluno_id': studentId,
          'simulado_id': simuladoId,
          'respostas': detectedAnswers,
          'versao': versao, // Adicionado a versão para o backend
          'tipo_prova': tipo, // Adicionado o tipo de prova
        },
      );

      if (response.statusCode == 200) {
        return ResultadoModel.fromJson(jsonDecode(response.body));
      } else {
        debugPrint(
            'Failed to process and submit: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception processing and submitting: $e');
      return null;
    }
  }

  // ========================================
  // 🆕 NOVOS MÉTODOS PARA SISTEMA DE CRÉDITOS
  // ========================================

  /// Verificar saldo de créditos do usuário
  Future<Map<String, dynamic>?> getUserCredits() async {
    try {
      developer.log('💰 Verificando saldo de créditos do usuário...');
      final response = await authorizedRequest('/api/user_credits/');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final credits = {
          'available_credits': data['available_credits'] ?? 0,
          'total_credits': data['total_credits'] ?? 0,
          'used_credits': data['used_credits'] ?? 0,
          'last_updated': data['last_updated'],
        };

        developer.log(
            '💰 Créditos obtidos: ${credits['available_credits']} disponíveis');
        return credits;
      } else {
        developer.log(
            '💰 Falha ao obter créditos: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      developer.log('💰 Erro ao verificar créditos: $e');
      return null;
    }
  }

  /// Consumir um crédito após correção
  Future<bool> consumeCredit({
    required int studentId,
    required int simuladoId,
    required String action,
  }) async {
    try {
      developer.log('💳 Consumindo crédito para ação: $action');
      developer.log('💳 Aluno: $studentId, Simulado: $simuladoId');

      final response = await authorizedRequest(
        '/api/consume_credit/',
        method: 'POST',
        body: {
          'student_id': studentId,
          'simulado_id': simuladoId,
          'action': action,
          'timestamp': DateTime.now().toIso8601String(),
          'app_version': '1.0.0', // Para rastreamento
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        developer.log('💳 Crédito consumido com sucesso!');
        developer.log('💳 Créditos restantes: ${data['remaining_credits']}');
        return true;
      } else {
        developer.log('💳 Falha ao consumir crédito: ${response.statusCode}');
        developer.log('💳 Resposta: ${response.body}');
        return false;
      }
    } catch (e) {
      developer.log('💳 Erro ao consumir crédito: $e');
      return false;
    }
  }

  /// Verificar se há créditos suficientes
  Future<bool> hasAvailableCredits() async {
    try {
      final credits = await getUserCredits();
      final available = credits?['available_credits'] ?? 0;
      developer
          .log('🔍 Verificação rápida de créditos: $available disponíveis');
      return available > 0;
    } catch (e) {
      developer.log('🔍 Erro na verificação rápida de créditos: $e');
      return false;
    }
  }

  /// Obter histórico de uso de créditos (opcional)
  Future<List<Map<String, dynamic>>?> getCreditHistory({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      developer.log('📋 Buscando histórico de créditos...');
      final response = await authorizedRequest(
        '/api/users/credits/history/?limit=$limit&offset=$offset',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final history =
            List<Map<String, dynamic>>.from(data['results'] ?? data ?? []);

        developer.log('📋 Histórico obtido: ${history.length} registros');
        return history;
      } else {
        developer.log('📋 Falha ao obter histórico: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      developer.log('📋 Erro ao obter histórico de créditos: $e');
      return null;
    }
  }

  /// Verificar planos de créditos disponíveis (para futuras compras)
  Future<List<Map<String, dynamic>>?> getAvailablePlans() async {
    try {
      developer.log('🛒 Buscando planos de créditos disponíveis...');
      final response = await authorizedRequest('/api/credits/plans/');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final plans =
            List<Map<String, dynamic>>.from(data['results'] ?? data ?? []);

        developer.log('🛒 Planos encontrados: ${plans.length}');
        return plans;
      } else {
        developer.log('🛒 Falha ao obter planos: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      developer.log('🛒 Erro ao obter planos: $e');
      return null;
    }
  }

  /// Carregar todos os simulados
  Future<List<SimuladoModel>> getSimulados() async {
    try {
      developer.log('📚 Buscando todos os simulados...');
      final response = await authorizedRequest('/api/simulados/');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data is Map ? data['results'] as List? : data as List?;
        final simulados = (results ?? [])
            .map((s) => SimuladoModel.fromJson(s as Map<String, dynamic>))
            .toList();

        developer.log('📚 Simulados carregados: ${simulados.length}');
        return simulados;
      } else {
        developer.log('📚 Falha ao obter simulados: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      developer.log('📚 Erro ao obter simulados: $e');
      return [];
    }
  }

  /// Carregar todos os estudantes
  Future<List<StudentModel>> getStudents({String? turmaId}) async {
    try {
      developer.log('👥 Buscando estudantes...');
      final endpoint = turmaId != null ? '/api/students/?class_id=$turmaId' : '/api/students/';
      final response = await authorizedRequest(endpoint);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data is Map ? data['results'] as List? : data as List?;
        final students = (results ?? [])
            .map((s) => StudentModel.fromJson(s as Map<String, dynamic>))
            .toList();

        developer.log('👥 Estudantes carregados: ${students.length}');
        return students;
      } else {
        developer.log('👥 Falha ao obter estudantes: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      developer.log('👥 Erro ao obter estudantes: $e');
      return [];
    }
  }
}
