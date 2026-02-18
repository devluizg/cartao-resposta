"""
URLs do app Catálogo
"""
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import CategoriaViewSet, ItemCatalogoViewSet, ConsumoInsumoViewSet

router = DefaultRouter()
router.register(r'categorias', CategoriaViewSet, basename='categoria')
router.register(r'itens', ItemCatalogoViewSet, basename='item')
router.register(r'insumos', ConsumoInsumoViewSet, basename='insumo')

urlpatterns = [
    path('', include(router.urls)),
]