//api_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models/class_model.dart';
import 'models/student_model.dart';
import 'models/simulado_model.dart';
import 'models/resultado_model.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();

  // Singleton pattern
  factory ApiService() => _instance;

  ApiService._internal();

  // Base URL for API calls
  String baseUrl = 'http://192.168.1.8:8001';

  // Set base URL for all API calls
  void setBaseUrl(String url) {
    baseUrl = url;
  }

  // Get the stored access token
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  // Get auth headers for API requests
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getAccessToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Login method - Fixed to match Django Rest Framework SimpleJWT format
  Future<bool> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/token/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': username, // Changed from 'username' to 'email'
          'password': password,
        }),
      );

      debugPrint(
          'Login status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode == 200) {
        final tokenData = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();

        // Store tokens - SimpleJWT returns access and refresh tokens
        await prefs.setString('access_token', tokenData['access']);
        await prefs.setString('refresh_token', tokenData['refresh']);

        // Fetch user info
        await getUserInfo();
        return true;
      } else {
        debugPrint('Login failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
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
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/user-info/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final userData = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();

        // Save user data
        await prefs.setString('user_name', userData['name']);
        await prefs.setString('user_email', userData['email']);

        return userData;
      } else if (response.statusCode == 401) {
        // Token expired, try to refresh
        final refreshed = await refreshToken();
        if (refreshed) {
          // Retry with new token
          return getUserInfo();
        }
        debugPrint('Failed to get user info: Token expired and refresh failed');
        return null;
      } else {
        debugPrint(
            'Failed to get user info: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception getting user info: $e');
      return null;
    }
  }

  // Generic authorized request method with token refresh
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
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'PUT':
          response = await http.put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
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
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/test-connection/'),
      );
      return response.statusCode == 200;
    } catch (e) {
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

  // Get the answer key (gabarito) for a simulado
  Future<Map<String, String>?> getGabarito(int simuladoId,
      {required String tipo}) async {
    try {
      // Mapear o tipo da prova do app para a versão correta no backend
      String versao =
          'versao$tipo'; // Converte tipo1 para versao1, tipo2 para versao2, etc.

      debugPrint(
          'Obtendo gabarito para simulado $simuladoId, versão $versao, tipo $tipo');

      final response = await authorizedRequest(
        '/api/simulados/$simuladoId/gabarito/?versao=$versao&tipo=$tipo',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Resposta do gabarito: ${response.body}');
        return Map<String, String>.from(data['gabarito']);
      } else {
        debugPrint(
            'Failed to get gabarito: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception getting gabarito: $e');
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

      final response = await authorizedRequest(
        '/api/simulados/$simuladoId/corrigir/',
        method: 'POST',
        body: {
          'aluno_id': studentId,
          'simulado_id': simuladoId,
          'respostas': answers,
          'versao': versao, // Adicionado a versão para o backend
          'tipo_prova': tipo, // Adicionado o tipo de prova
        },
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
}
