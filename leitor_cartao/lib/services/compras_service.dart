import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
// ignore: depend_on_referenced_packages
import 'models/produto_credito.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ComprasService {
  static const String baseUrl = 'http://192.168.1.10:8000/api';

  // IDs dos produtos que serão cadastrados no Google Play Console
  static const List<String> produtoIds = [
    'starter_300_creditos',
    'professor_ativo_800_creditos',
    'escola_pequena_2000_creditos',
    'escola_profissional_5000_creditos',
  ];

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  List<ProductDetails> _produtos = [];
  List<ProdutoCredito> _produtosCredito = [];

  // Callbacks para notificar a UI
  Function(int creditos)? onCompraSucesso;
  Function(String erro)? onCompraErro;
  Function(String status)? onCompraStatus;

  // Getters
  List<ProductDetails> get produtos => _produtos;
  List<ProdutoCredito> get produtosCredito => _produtosCredito;

  ComprasService() {
    _inicializarCompras();
  }

  Future<void> _inicializarCompras() async {
    final bool isAvailable = await _inAppPurchase.isAvailable();
    if (!isAvailable) {
      throw Exception('Loja não disponível');
    }

    _subscription = _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (error) {
        _log('Erro no stream de compras: $error');
        onCompraErro?.call('Erro no stream de compras: $error');
      },
    );
  }

  Future<void> carregarProdutos() async {
    try {
      // ✅ Verificar conectividade primeiro
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        throw Exception('Sem conexão com a internet');
      }

      // Buscar produtos do Google Play
      final ProductDetailsResponse response =
          await _inAppPurchase.queryProductDetails(
        produtoIds.toSet(),
      );

      if (response.error != null) {
        throw Exception(
            'Erro ao carregar produtos: ${response.error?.message}');
      }

      _produtos = response.productDetails;

      // Mapear para produtos de crédito com informações locais
      _produtosCredito = _produtos.map((product) {
        return _mapearProdutoCredito(product);
      }).toList();
    } catch (e) {
      _log('Erro ao carregar produtos: $e');
      rethrow;
    }
  }

  ProdutoCredito _mapearProdutoCredito(ProductDetails product) {
    // Mapear IDs dos produtos para informações locais
    switch (product.id) {
      case 'starter_300_creditos':
        return ProdutoCredito(
          id: product.id,
          nome: 'Starter',
          creditos: 300,
          preco: product.price,
          descricao: '300 correções incluídas',
        );
      case 'professor_ativo_800_creditos':
        return ProdutoCredito(
          id: product.id,
          nome: 'Professor Ativo',
          creditos: 800,
          preco: product.price,
          descricao: '800 correções incluídas',
        );
      case 'escola_pequena_2000_creditos':
        return ProdutoCredito(
          id: product.id,
          nome: 'Escola Pequena',
          creditos: 2000,
          preco: product.price,
          descricao: '2000 correções incluídas',
        );
      case 'escola_profissional_5000_creditos':
        return ProdutoCredito(
          id: product.id,
          nome: 'Escola Profissional',
          creditos: 5000,
          preco: product.price,
          descricao: '5000 correções incluídas',
        );
      default:
        return ProdutoCredito(
          id: product.id,
          nome: product.title,
          creditos: 0,
          preco: product.price,
          descricao: product.description,
        );
    }
  }

  Future<void> comprarProduto(ProductDetails produto) async {
    try {
      onCompraStatus?.call('Iniciando compra...');

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: produto,
      );

      await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      _log('Erro ao iniciar compra: $e');
      onCompraErro?.call('Erro ao iniciar compra: $e');
      rethrow;
    }
  }

  void _onPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      _handlePurchase(purchaseDetails);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails.status == PurchaseStatus.purchased) {
      // Compra bem-sucedida
      onCompraStatus?.call('Processando compra...');
      await _processarCompraSucesso(purchaseDetails);
    } else if (purchaseDetails.status == PurchaseStatus.error) {
      // Erro na compra
      final errorMessage = 'Erro na compra: ${purchaseDetails.error?.message}';
      _log(errorMessage);
      onCompraErro?.call(errorMessage);
    } else if (purchaseDetails.status == PurchaseStatus.canceled) {
      // Compra cancelada
      const cancelMessage = 'Compra cancelada pelo usuário';
      _log(cancelMessage);
      onCompraStatus?.call(cancelMessage);
    } else if (purchaseDetails.status == PurchaseStatus.pending) {
      // Compra pendente
      const pendingMessage = 'Compra pendente';
      _log(pendingMessage);
      onCompraStatus?.call(pendingMessage);
    }

    if (purchaseDetails.pendingCompletePurchase) {
      await _inAppPurchase.completePurchase(purchaseDetails);
    }
  }

  Future<void> _processarCompraSucesso(PurchaseDetails purchaseDetails) async {
    try {
      // Encontrar o produto comprado
      final produto = _produtosCredito.firstWhere(
        (p) => p.id == purchaseDetails.productID,
        orElse: () => ProdutoCredito(
          id: purchaseDetails.productID,
          nome: 'Produto Desconhecido',
          creditos: 0,
        ),
      );

      // Enviar para o backend para validação
      await _validarCompraNoBackend(purchaseDetails, produto);
    } catch (e) {
      _log('Erro ao processar compra: $e');
      onCompraErro?.call('Erro ao processar compra: $e');
      rethrow;
    }
  }

  Future<void> _validarCompraNoBackend(
      PurchaseDetails purchaseDetails, ProdutoCredito produto) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/comprar_creditos/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
        body: jsonEncode({
          'produto_id': produto.id,
          'creditos': produto.creditos,
          'purchase_token':
              purchaseDetails.verificationData.serverVerificationData,
          'transaction_id': purchaseDetails.purchaseID,
          'plataforma': Platform.isAndroid ? 'android' : 'ios',
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        _log('Compra validada com sucesso: ${responseData['message']}');
        _notificarCompraSucesso(produto.creditos);
      } else {
        throw Exception('Erro ao validar compra: ${response.body}');
      }
    } catch (e) {
      _log('Erro ao validar compra no backend: $e');
      onCompraErro?.call('Erro ao validar compra no backend: $e');
      rethrow;
    }
  }

  Future<String> _getAuthToken() async {
    // Implementar lógica para obter token de autenticação
    // Por exemplo, de SharedPreferences ou de um gerenciador de estado
    return 'seu_token_aqui';
  }

  void _notificarCompraSucesso(int creditos) {
    _log('Compra realizada com sucesso! $creditos créditos adicionados.');
    onCompraSucesso?.call(creditos);
  }

  void _log(String message) {
    // Substitua por um sistema de logging adequado em produção
    // ignore: avoid_print
    print('[ComprasService] $message');
  }

  void dispose() {
    _subscription.cancel();
  }
}
