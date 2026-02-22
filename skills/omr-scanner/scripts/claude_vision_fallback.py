#!/usr/bin/env python3
"""
claude_vision_fallback.py
Fallback inteligente via Claude Vision API para OMR.

Modos:
  completo   — Pipeline OpenCV falhou totalmente; Claude lê toda a folha
  parcial    — OpenCV funcionou, mas algumas questões ficaram ambíguas

Pré-requisito: ANTHROPIC_API_KEY no ambiente.

Saída: JSON em stdout + arquivo JSON de saída.
"""

import argparse
import base64
import json
import os
import sys
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)

# ─── Verificação de dependências ───────────────────────────────────────────
try:
    import anthropic
    ANTHROPIC_DISPONIVEL = True
except ImportError:
    ANTHROPIC_DISPONIVEL = False
    log.warning("SDK Anthropic não instalado. Execute: pip install anthropic")


def _erro(msg: str) -> dict:
    return {"status": "erro", "mensagem": msg}


def _ok(dados: dict) -> dict:
    return {"status": "ok", **dados}


def _imagem_para_base64(caminho: str) -> tuple[str, str]:
    """Retorna (base64_data, media_type)."""
    ext = Path(caminho).suffix.lower()
    media_types = {".jpg": "image/jpeg", ".jpeg": "image/jpeg",
                   ".png": "image/png", ".webp": "image/webp"}
    media_type = media_types.get(ext, "image/jpeg")
    with open(caminho, "rb") as f:
        data = base64.standard_b64encode(f.read()).decode("utf-8")
    return data, media_type


def _carregar_gabarito(gabarito_path: str) -> dict:
    if gabarito_path and os.path.exists(gabarito_path):
        with open(gabarito_path, encoding="utf-8") as f:
            return json.load(f)
    return {}


# ═══════════════════════════════════════════════════════════════════════════
# PROMPT BUILDER
# ═══════════════════════════════════════════════════════════════════════════

PROMPT_COMPLETO = """Você está analisando uma folha de respostas de múltipla escolha (gabarito OMR).
Sua tarefa é identificar com precisão qual alternativa (A, B, C, D ou E) está marcada em cada questão.

REGRAS ESTRITAS:
1. Para cada questão visível, retorne exatamente UMA alternativa marcada.
2. Se nenhuma alternativa estiver marcada, retorne "EM_BRANCO".
3. Se duas ou mais estiverem marcadas com intensidade similar, retorne "AMBIGUA".
4. Não faça suposições — baseie-se apenas no preenchimento visual das bolhas.
5. Retorne SOMENTE o JSON, sem texto adicional.

FORMATO DE SAÍDA OBRIGATÓRIO:
{
  "respostas": {
    "1": "A",
    "2": "C",
    "3": "EM_BRANCO",
    "4": "AMBIGUA",
    ...
  },
  "num_questoes_detectadas": 20,
  "confianca": 0.95,
  "observacoes": "Questão 4 tem duas marcações quase igualmente preenchidas."
}"""

PROMPT_PARCIAL_TEMPLATE = """Você está analisando uma folha de respostas de múltipla escolha.
O sistema de visão computacional já processou a maioria das questões, mas NÃO conseguiu
determinar com certeza as seguintes questões: {questoes_ambiguas}.

Analise a imagem e determine qual alternativa (A, B, C, D ou E) está marcada
SOMENTE para as questões listadas acima.

REGRAS:
1. Retorne UMA alternativa por questão ambígua.
2. Se realmente impossível determinar, retorne "IMPOSSIVEL_DETERMINAR".
3. Retorne SOMENTE o JSON, sem texto adicional.

FORMATO DE SAÍDA OBRIGATÓRIO:
{
  "resolucoes": {
    "3": "B",
    "7": "D",
    "12": "IMPOSSIVEL_DETERMINAR"
  },
  "confianca": 0.88,
  "observacoes": "Questão 12 está muito apagada."
}"""


# ═══════════════════════════════════════════════════════════════════════════
# MODOS DE FALLBACK
# ═══════════════════════════════════════════════════════════════════════════

def fallback_completo(input_path: str, output_json: str, gabarito_path: str) -> dict:
    """Claude analisa toda a folha de respostas como fallback total."""
    if not ANTHROPIC_DISPONIVEL:
        return _erro("SDK Anthropic não instalado.")

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return _erro("ANTHROPIC_API_KEY não definida no ambiente.")

    if not os.path.exists(input_path):
        return _erro(f"Imagem não encontrada: {input_path}")

    try:
        imagem_b64, media_type = _imagem_para_base64(input_path)
    except Exception as e:
        return _erro(f"Falha ao codificar imagem: {e}")

    client = anthropic.Anthropic(api_key=api_key)

    log.info("Enviando imagem para Claude Vision (modo completo)...")
    try:
        response = client.messages.create(
            model="claude-opus-4-6",
            max_tokens=2048,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": imagem_b64
                            }
                        },
                        {
                            "type": "text",
                            "text": PROMPT_COMPLETO
                        }
                    ]
                }
            ]
        )
    except anthropic.APIError as e:
        return _erro(f"Erro na API Anthropic: {e}")

    texto_resposta = response.content[0].text.strip()

    # Remove possíveis blocos markdown
    if "```json" in texto_resposta:
        texto_resposta = texto_resposta.split("```json")[1].split("```")[0].strip()
    elif "```" in texto_resposta:
        texto_resposta = texto_resposta.split("```")[1].split("```")[0].strip()

    try:
        resultado_claude = json.loads(texto_resposta)
    except json.JSONDecodeError as e:
        return _erro(f"Resposta da API não é JSON válido: {e}\nTexto recebido: {texto_resposta[:200]}")

    # Mescla com gabarito se disponível
    gabarito = _carregar_gabarito(gabarito_path)
    resultado_final = {
        "origem": "claude_vision_completo",
        "respostas_detectadas": resultado_claude.get("respostas", {}),
        "num_questoes_detectadas": resultado_claude.get("num_questoes_detectadas", 0),
        "confianca": resultado_claude.get("confianca", 0.0),
        "observacoes": resultado_claude.get("observacoes", ""),
        "gabarito_disponivel": bool(gabarito)
    }

    with open(output_json, "w", encoding="utf-8") as f:
        json.dump(resultado_final, f, ensure_ascii=False, indent=2)

    log.info(f"Resultado salvo em: {output_json}")
    return _ok(resultado_final)


def fallback_parcial(input_path: str, questoes_ambiguas_json: str,
                     output_json: str) -> dict:
    """Claude resolve apenas as questões ambíguas identificadas pelo OpenCV."""
    if not ANTHROPIC_DISPONIVEL:
        return _erro("SDK Anthropic não instalado.")

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return _erro("ANTHROPIC_API_KEY não definida no ambiente.")

    try:
        questoes_ambiguas = json.loads(questoes_ambiguas_json)
    except json.JSONDecodeError:
        return _erro(f"JSON de questões ambíguas inválido: {questoes_ambiguas_json}")

    if not questoes_ambiguas:
        resultado = {"resolucoes": {}, "confianca": 1.0, "observacoes": "Sem ambiguidades."}
        with open(output_json, "w", encoding="utf-8") as f:
            json.dump(resultado, f, ensure_ascii=False, indent=2)
        return _ok(resultado)

    try:
        imagem_b64, media_type = _imagem_para_base64(input_path)
    except Exception as e:
        return _erro(f"Falha ao codificar imagem: {e}")

    prompt = PROMPT_PARCIAL_TEMPLATE.format(
        questoes_ambiguas=", ".join(str(q) for q in questoes_ambiguas)
    )

    client = anthropic.Anthropic(api_key=api_key)

    log.info(f"Enviando {len(questoes_ambiguas)} questão(ões) ambígua(s) para Claude Vision...")
    try:
        response = client.messages.create(
            model="claude-opus-4-6",
            max_tokens=1024,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": imagem_b64
                            }
                        },
                        {"type": "text", "text": prompt}
                    ]
                }
            ]
        )
    except anthropic.APIError as e:
        return _erro(f"Erro na API Anthropic: {e}")

    texto_resposta = response.content[0].text.strip()
    if "```json" in texto_resposta:
        texto_resposta = texto_resposta.split("```json")[1].split("```")[0].strip()
    elif "```" in texto_resposta:
        texto_resposta = texto_resposta.split("```")[1].split("```")[0].strip()

    try:
        resultado_claude = json.loads(texto_resposta)
    except json.JSONDecodeError as e:
        return _erro(f"Resposta da API não é JSON válido: {e}")

    resultado_final = {
        "origem": "claude_vision_parcial",
        "resolucoes": resultado_claude.get("resolucoes", {}),
        "confianca": resultado_claude.get("confianca", 0.0),
        "observacoes": resultado_claude.get("observacoes", ""),
        "questoes_resolvidas": list(resultado_claude.get("resolucoes", {}).keys())
    }

    with open(output_json, "w", encoding="utf-8") as f:
        json.dump(resultado_final, f, ensure_ascii=False, indent=2)

    log.info(f"Resolução de ambiguidades salva em: {output_json}")
    return _ok(resultado_final)


# ═══════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="Claude Vision Fallback para OMR")
    parser.add_argument("--input", required=True, help="Caminho da imagem")
    parser.add_argument("--modo", required=True, choices=["completo", "parcial"],
                        help="'completo' para fallback total, 'parcial' para resolver ambiguidades")
    parser.add_argument("--gabarito", default=None, help="Caminho do JSON de gabarito")
    parser.add_argument("--questoes-ambiguas", default="[]",
                        help="JSON com lista de números de questões ambíguas (modo parcial)")
    parser.add_argument("--output-json", default="/tmp/fallback_output.json")
    args = parser.parse_args()

    if args.modo == "completo":
        resultado = fallback_completo(args.input, args.output_json, args.gabarito)
    else:
        resultado = fallback_parcial(args.input, args.questoes_ambiguas, args.output_json)

    print(json.dumps(resultado, ensure_ascii=False, indent=2))
    sys.exit(0 if resultado.get("status") == "ok" else 1)


if __name__ == "__main__":
    main()
