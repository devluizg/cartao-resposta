"""
Views da API do app Catálogo
"""
from rest_framework import viewsets, filters, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from django.db.models import Q
from .models import Categoria, ItemCatalogo, ConsumoInsumo
from .serializers import (
    CategoriaSerializer,
    ItemCatalogoSerializer,
    ItemCatalogoListSerializer,
    ItemCatalogoSiteSerializer,
    ItemCatalogoWhatsAppSerializer,
    ConsumoInsumoSerializer
)


class CategoriaViewSet(viewsets.ModelViewSet):
    """
    API para gerenciar Categorias
    
    list: GET /api/catalogo/categorias/
    retrieve: GET /api/catalogo/categorias/{id}/
    create: POST /api/catalogo/categorias/
    update: PUT /api/catalogo/categorias/{id}/
    destroy: DELETE /api/catalogo/categorias/{id}/
    """
    queryset = Categoria.objects.filter(ativa=True)
    serializer_class = CategoriaSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['nome', 'descricao']
    ordering_fields = ['nome', 'criado_em']


class ItemCatalogoViewSet(viewsets.ModelViewSet):
    """
    API para gerenciar Itens do Catálogo (Produtos e Serviços)
    
    list: GET /api/catalogo/itens/
    retrieve: GET /api/catalogo/itens/{id}/
    produtos: GET /api/catalogo/itens/produtos/
    servicos: GET /api/catalogo/itens/servicos/
    site: GET /api/catalogo/itens/site/ (público)
    whatsapp: GET /api/catalogo/itens/whatsapp/ (para o bot)
    consultar_preco: GET /api/catalogo/itens/consultar_preco/?nome=polimento
    estoque_baixo: GET /api/catalogo/itens/estoque_baixo/
    """
    queryset = ItemCatalogo.objects.filter(ativo=True).select_related('categoria')
    permission_classes = [IsAuthenticated]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['nome', 'descricao', 'categoria__nome']
    ordering_fields = ['nome', 'preco_venda', 'estoque_atual', 'criado_em']
    
    def get_serializer_class(self):
        """Retorna serializer apropriado para cada ação"""
        if self.action == 'list':
            return ItemCatalogoListSerializer
        elif self.action == 'site':
            return ItemCatalogoSiteSerializer
        elif self.action == 'whatsapp':
            return ItemCatalogoWhatsAppSerializer
        return ItemCatalogoSerializer
    
    def get_permissions(self):
        """Endpoints públicos não requerem autenticação"""
        if self.action in ['site', 'whatsapp', 'consultar_preco']:
            return [AllowAny()]
        return super().get_permissions()
    
    @action(detail=False, methods=['get'])
    def produtos(self, request):
        """
        Retorna apenas produtos físicos
        GET /api/catalogo/itens/produtos/
        """
        produtos = self.get_queryset().filter(tipo='PRODUTO')
        serializer = self.get_serializer(produtos, many=True)
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def servicos(self, request):
        """
        Retorna apenas serviços
        GET /api/catalogo/itens/servicos/
        """
        servicos = self.get_queryset().filter(tipo='SERVICO')
        serializer = self.get_serializer(servicos, many=True)
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'], permission_classes=[AllowAny])
    def site(self, request):
        """
        Endpoint PÚBLICO para o site vitrine
        GET /api/catalogo/itens/site/
        
        Retorna apenas itens com:
        - visivel_no_site = True
        - ativo = True
        - estoque_atual > 0 (para produtos)
        """
        itens = self.get_queryset().filter(visivel_no_site=True)
        
        # Filtrar produtos sem estoque
        itens = itens.filter(
            Q(tipo='SERVICO') | Q(tipo='PRODUTO', estoque_atual__gt=0)
        ).order_by('-destaque', 'nome')
        
        serializer = self.get_serializer(itens, many=True)
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'], permission_classes=[AllowAny])
    def whatsapp(self, request):
        """
        Endpoint para o bot do WhatsApp
        GET /api/catalogo/itens/whatsapp/
        
        Retorna apenas itens com visivel_no_zap = True
        """
        itens = self.get_queryset().filter(visivel_no_zap=True).order_by('-destaque', 'nome')
        serializer = self.get_serializer(itens, many=True)
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'], permission_classes=[AllowAny])
    def consultar_preco(self, request):
        """
        Endpoint para o GPT consultar preços
        GET /api/catalogo/itens/consultar_preco/?nome=polimento
        
        Busca por nome (case insensitive) e retorna o preço
        """
        nome = request.query_params.get('nome', '').strip()
        
        if not nome:
            return Response(
                {'erro': 'Parâmetro "nome" é obrigatório'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Busca case-insensitive
        itens = self.get_queryset().filter(
            nome__icontains=nome,
            visivel_no_zap=True
        )
        
        if not itens.exists():
            return Response(
                {'mensagem': f'Item "{nome}" não encontrado no catálogo'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Se encontrar mais de um, retorna todos
        serializer = ItemCatalogoWhatsAppSerializer(itens, many=True)
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def estoque_baixo(self, request):
        """
        Retorna produtos com estoque abaixo do mínimo
        GET /api/catalogo/itens/estoque_baixo/
        """
        produtos_baixo = []
        for item in self.get_queryset().filter(tipo='PRODUTO'):
            if item.estoque_baixo():
                produtos_baixo.append(item)
        
        serializer = ItemCatalogoListSerializer(produtos_baixo, many=True)
        return Response(serializer.data)
    
    @action(detail=True, methods=['post'])
    def ajustar_estoque(self, request, pk=None):
        """
        Ajusta o estoque de um produto
        POST /api/catalogo/itens/{id}/ajustar_estoque/
        Body: {"quantidade": 10, "operacao": "adicionar"} ou "subtrair"
        """
        item = self.get_object()
        
        if item.tipo != 'PRODUTO':
            return Response(
                {'erro': 'Apenas produtos têm estoque'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        quantidade = request.data.get('quantidade', 0)
        operacao = request.data.get('operacao', 'adicionar')
        
        try:
            quantidade = int(quantidade)
        except ValueError:
            return Response(
                {'erro': 'Quantidade deve ser um número inteiro'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if operacao == 'adicionar':
            item.estoque_atual += quantidade
        elif operacao == 'subtrair':
            if item.estoque_atual - quantidade < 0:
                return Response(
                    {'erro': 'Estoque insuficiente'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            item.estoque_atual -= quantidade
        else:
            return Response(
                {'erro': 'Operação deve ser "adicionar" ou "subtrair"'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        item.save()
        serializer = self.get_serializer(item)
        return Response(serializer.data)


class ConsumoInsumoViewSet(viewsets.ModelViewSet):
    """
    API para gerenciar Consumo de Insumos
    """
    queryset = ConsumoInsumo.objects.all().select_related('servico_pai', 'produto_filho')
    serializer_class = ConsumoInsumoSerializer
    permission_classes = [IsAuthenticated]
    
    @action(detail=False, methods=['get'])
    def por_servico(self, request):
        """
        Retorna insumos de um serviço específico
        GET /api/catalogo/insumos/por_servico/?servico_id=1
        """
        servico_id = request.query_params.get('servico_id')
        
        if not servico_id:
            return Response(
                {'erro': 'Parâmetro "servico_id" é obrigatório'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        insumos = self.get_queryset().filter(servico_pai_id=servico_id)
        serializer = self.get_serializer(insumos, many=True)
        return Response(serializer.data)