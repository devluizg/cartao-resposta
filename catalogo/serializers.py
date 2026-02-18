"""
Serializers do app Catálogo
Converte Models Python ↔ JSON
"""
from rest_framework import serializers
from .models import Categoria, ItemCatalogo, ConsumoInsumo


class CategoriaSerializer(serializers.ModelSerializer):
    """Serializer para Categoria"""
    
    total_itens = serializers.SerializerMethodField()
    
    class Meta:
        model = Categoria
        fields = ['id', 'nome', 'descricao', 'ativa', 'total_itens', 'criado_em']
        read_only_fields = ['criado_em']
    
    def get_total_itens(self, obj):
        return obj.itens.filter(ativo=True).count()


class ConsumoInsumoSerializer(serializers.ModelSerializer):
    """Serializer para Consumo de Insumos (Ficha Técnica)"""
    
    produto_nome = serializers.CharField(source='produto_filho.nome', read_only=True)
    produto_unidade = serializers.CharField(source='produto_filho.unidade_medida', read_only=True)
    custo_total = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)
    
    class Meta:
        model = ConsumoInsumo
        fields = [
            'id',
            'produto_filho',
            'produto_nome',
            'produto_unidade',
            'quantidade',
            'custo_total'
        ]


class ItemCatalogoSerializer(serializers.ModelSerializer):
    """Serializer completo para ItemCatalogo"""
    
    categoria_nome = serializers.CharField(source='categoria.nome', read_only=True)
    tipo_display = serializers.CharField(source='get_tipo_display', read_only=True)
    margem_lucro = serializers.SerializerMethodField()
    estoque_baixo = serializers.SerializerMethodField()
    insumos_necessarios = ConsumoInsumoSerializer(many=True, read_only=True)
    
    class Meta:
        model = ItemCatalogo
        fields = [
            'id',
            'tipo',
            'tipo_display',
            'categoria',
            'categoria_nome',
            'nome',
            'descricao',
            'preco_venda',
            'custo_base',
            'margem_lucro',
            'estoque_atual',
            'estoque_minimo',
            'estoque_baixo',
            'unidade_medida',
            'visivel_no_site',
            'visivel_no_zap',
            'imagem',
            'ativo',
            'destaque',
            'insumos_necessarios',
            'criado_em',
            'atualizado_em'
        ]
        read_only_fields = ['criado_em', 'atualizado_em']
    
    def get_margem_lucro(self, obj):
        return round(obj.margem_lucro(), 2)
    
    def get_estoque_baixo(self, obj):
        return obj.estoque_baixo()


class ItemCatalogoListSerializer(serializers.ModelSerializer):
    """
    Serializer simplificado para listagens
    (menos campos = resposta mais rápida)
    """
    
    categoria_nome = serializers.CharField(source='categoria.nome', read_only=True)
    tipo_display = serializers.CharField(source='get_tipo_display', read_only=True)
    
    class Meta:
        model = ItemCatalogo
        fields = [
            'id',
            'tipo',
            'tipo_display',
            'categoria_nome',
            'nome',
            'preco_venda',
            'estoque_atual',
            'imagem',
            'destaque',
            'ativo'
        ]


class ItemCatalogoSiteSerializer(serializers.ModelSerializer):
    """
    Serializer público para o site (sem dados sensíveis)
    """
    
    categoria_nome = serializers.CharField(source='categoria.nome', read_only=True)
    tipo_display = serializers.CharField(source='get_tipo_display', read_only=True)
    
    class Meta:
        model = ItemCatalogo
        fields = [
            'id',
            'tipo',
            'tipo_display',
            'categoria_nome',
            'nome',
            'descricao',
            'preco_venda',
            'imagem',
            'destaque'
        ]


class ItemCatalogoWhatsAppSerializer(serializers.ModelSerializer):
    """
    Serializer otimizado para o bot do WhatsApp
    """
    
    categoria_nome = serializers.CharField(source='categoria.nome', read_only=True)
    
    class Meta:
        model = ItemCatalogo
        fields = [
            'id',
            'tipo',
            'nome',
            'descricao',
            'preco_venda',
            'categoria_nome',
            'estoque_atual'
        ]