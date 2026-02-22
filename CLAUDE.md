# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SimuladoApp v2 is a Django-based educational platform where teachers create exam simulations (simulados) with multiple question versions, generate PDFs, and track student performance. The platform is in Brazilian Portuguese (pt-br).

**Stack**: Django 4.2+, Python 3.12, MySQL (utf8mb4), Django REST Framework, WeasyPrint/ReportLab for PDFs, CKEditor for rich text, django-allauth for Google OAuth.

## Development Commands

```bash
# Run development server
python manage.py runserver

# Database migrations
python manage.py makemigrations
python manage.py migrate

# Run tests
python manage.py test
python manage.py test accounts        # Single app
python manage.py test accounts.tests.TestLogin  # Single test class

# Collect static files (required after CSS/JS changes in production mode)
python manage.py collectstatic --noinput

# Create superuser
python manage.py createsuperuser

# Django shell
python manage.py shell

# Populate test data
python scripts/populate_test_data_v2.py
```

## Architecture

### Django Apps

- **accounts** — Custom email-based user model (`CustomUser`), profile management, email verification, Google OAuth. Auth uses email, not username (`USERNAME_FIELD = 'email'`).
- **questions** — Core business logic. Questions (Questao), exams (Simulado), answer key versions (VersaoGabarito), results (Resultado). The `views.py` is the largest file (~2875 lines) handling dashboard, CRUD, PDF generation, and versioning.
- **classes** — Teacher class/group management, student enrollment, performance tracking.
- **api** — REST API for mobile apps using DRF. ViewSets for classes, students, questions, simulados. JWT + Token + Session auth.
- **creditos** — Credit/payment system with Mercado Pago and Google Play integration.

### Key Architectural Concepts

- **Multi-version answer keys**: Each simulado can generate 5 shuffled versions (VersaoGabarito) with different answer orderings, each identified by UUID.
- **PDF generation**: Heavy operation using WeasyPrint/ReportLab. Has dedicated settings (`PDF_GENERATION_SETTINGS`) with timeouts and worker limits. Templates in `questions/templates/questions/simulado_pdf.html`.
- **Dual model issue**: `Resultado` and `DetalhesResposta` models exist in both `questions` and `api` apps (redundant).
- **Custom user model**: `accounts.CustomUser` extends `AbstractUser`. Associated `Profile` model (OneToOne) holds avatar, school, bio. Profile auto-created via signal.
- **CKEditor**: Two toolbar configs — `default` (full, for question enunciados) and `alternativas` (minimal, for answer alternatives).

### URL Structure

| Prefix | App | Description |
|--------|-----|-------------|
| `/` | questions | Homepage, dashboard, question/simulado CRUD |
| `/accounts/` | accounts + allauth | Auth, registration, profile, Google OAuth |
| `/api/` | api | REST API (JWT at `/api/token/`) |
| `/classes/` | classes | Class management |
| `/creditos/` | creditos | Credit system |
| `/admin/` | django.contrib.admin | Admin panel |
| `/ckeditor/` | ckeditor_uploader | CKEditor file uploads |

### Configuration

- Environment variables via `.env` (python-decouple + python-dotenv)
- Custom user model: `AUTH_USER_MODEL = 'accounts.CustomUser'`
- Login redirects to `questions:questions_dashboard`
- Static files served by WhiteNoise (`CompressedManifestStaticFilesStorage`)
- Media uploads go to `media/` (questoes, avatars, capas, uploads subdirs)
- Max 45 questions per simulado (`SIMULADO_MAX_QUESTOES = 45`)
- Max image size: 5MB

### Deployment

Deploys to Render.com via `nixpacks.toml`. Production uses Gunicorn. System deps include `wkhtmltopdf` and Cairo/Pango libraries for PDF rendering.

## Workflow Rules

### Role: Builder Only

Claude is the **builder/developer**. Claude writes code, implements features, and makes changes. Claude does NOT investigate, debug, or test.

### When there is a bug or problem:
- **DO NOT** read files to investigate or search for the root cause.
- **DO** provide a checklist/roadmap of:
  - Where the problem likely is (file paths and line numbers if possible)
  - Which files should be analyzed
  - What to look for in each file
- The user will analyze those files externally and provide results back to Claude.

### After implementing a feature or change:
- **DO NOT** run the dev server, tests, or any command to verify the implementation.
- **DO** provide a checklist of what was implemented and what the user should verify manually, for example:
  - [ ] Page X should now show Y
  - [ ] Button Z should trigger action W
  - [ ] Style change A should be visible on page B
- The user will test and report back with results or screenshots.

---

## Skills Disponíveis

Skills são Procedimentos Operacionais Padrão (SOP) que o Claude deve seguir à risca quando acionados.
Ao reconhecer uma das frases de gatilho abaixo, leia o SKILL.md correspondente **antes de qualquer outra ação**.

### OMR Scanner — Leitura e Correção Automática de Gabaritos

**Localização:** `skills/omr-scanner/SKILL.md`

**Quando acionar — frases de gatilho:**
- "escanear gabarito" / "scan answer sheet" / "ler folha de respostas"
- "corrigir prova automaticamente" / "grade bubble sheet"
- "pipeline OMR" / "optical mark recognition" / "leitura óptica"
- "processar gabarito" / "cartão resposta" / "cartão de respostas"
- "detectar bolhas marcadas em imagem de prova"

**O que faz:**
Pipeline determinístico OpenCV (pré-processamento → detecção de documento → transformação de perspectiva → detecção de bolhas → classificação) com fallback automático para Claude Vision API em casos de falha ou ambiguidade. Gera `resultado_final.json` com nota, acertos, erros e imagem anotada.

**Scripts disponíveis em `skills/omr-scanner/scripts/`:**

| Script | Função |
|--------|--------|
| `processamento_imagem.py` | Pipeline OpenCV completo (modos: preprocessar, detectar_documento, perspectiva, detectar_bolhas, classificar) |
| `claude_vision_fallback.py` | Fallback Claude Vision (modo completo ou parcial para ambiguidades) |
| `metricas_acuracia.py` | Pontuação final, mesclagem de resultados e geração de imagem anotada |

**Referências em `skills/omr-scanner/references/`:**

| Arquivo | Conteúdo |
|---------|----------|
| `configuracoes_normalizacao.json` | Parâmetros CLAHE, Canny, thresholds OpenCV |
| `gabarito_exemplo.json` | Template de gabarito (substitua pelo gabarito real) |
| `resposta_api_exemplo.json` | Formatos esperados da Claude Vision API |

**Pré-requisitos:**
```bash
pip install opencv-python-headless imutils numpy anthropic Pillow
export ANTHROPIC_API_KEY="sk-ant-..."
```

**Grau de liberdade: BAIXO** — Siga as etapas do SKILL.md em sequência estrita. Não pule passos.