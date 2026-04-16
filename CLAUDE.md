# CLAUDE.md — Curso Vertex AI People Analytics

## Project Overview

Advanced course for data engineers and technical analysts working with Google Cloud Platform and Vertex AI, focused on best practices, data governance, and secure analytical exploitation in People Analytics environments. Provided by **Imagina Formacion**.

- **Duration**: 25 hours across 12 sessions
- **Audience**: Data engineers and technical analysts managing sensitive people data in GCP
- **Language**: All content in **Spanish** (GCP service names and Python/SQL keywords remain in English)
- **Domain**: People Analytics — HR data with GDPR, ethics, and bias considerations

## Session Schedule

| Session | Date | Time |
|---------|------|------|
| 1 | Tuesday April 14, 2026 | 16:00–18:00 |
| 2 | Monday April 20 | 16:00–18:00 |
| 3 | Monday April 27 | 16:00–18:00 |
| 4 | Monday May 4 | 16:00–18:00 |
| 5 | Monday May 11 | 16:00–18:00 |
| 6 | Monday May 18 | 16:00–18:00 |
| 7 | Monday May 25 | 16:00–18:00 |
| 8 | Monday June 1 | 16:00–18:00 |
| 9 | Monday June 8 | 16:00–18:00 |
| 10 | Monday June 15 | 16:00–18:00 |
| 11 | Monday June 22 | 16:00–18:30 |
| 12 | Monday June 29 | 16:00–18:30 |

## Full Syllabus (19 Modules)

### Module 1 — Contexto Real de Analitica de Datos en People Analytics
Sensitivity/confidentiality/ethics of people data, HR data typologies (structured, semi-structured, derived), data lifecycle, real cases (turnover, absenteeism, performance, diversity), risks in employee data analysis, descriptive/predictive/prescriptive analytics, GDPR and labor law, algorithmic bias, data-HR relationship, analytics maturity.

### Module 2 — Arquitectura Actual de Datos en Google Cloud Platform
GCP project organization, dev/test/prod environment separation, typical PA architecture, internal source integration (HRIS, payroll, ATS), secure sensitive data ingestion, Data Lake vs Data Warehouse in GCP, end-to-end flow to dashboard, IAM, cost control, scalability/maintainability design, **BigLake** (extend BQ to external data lakes), **Analytics Hub** (secure dataset sharing).

### Module 3 — Ingesta de Datos en GCP
Pub/Sub as GCP messaging system, external API and corporate system integration, real-time ingestion architectures, cost/complexity comparison streaming vs batch.

### Module 4 — Pipelines Basados en Eventos
Event-driven architectures in GCP, Eventarc reacting to Cloud Storage events, Dataflow pipeline automation, event-based batch processing, resilient pipeline best practices.

### Module 5 — Orquestacion Profesional de Pipelines
Data flow orchestration concepts, Google Cloud Workflows (lightweight), Cloud Composer / Managed Airflow (complex pipelines), Workflows vs Composer comparison, integration with Eventarc and Cloud Scheduler.

### Module 6 — Buenas Practicas de BigQuery para Ingenieros de Datos
Production dataset modeling, partitioning and clustering, cost control per query, performance optimization, dataset/table permissions, intermediate tables and semantic layers, table versioning, historical data and snapshots, technical documentation, query auditing, **Stored Procedures**, **UDFs**, **Procedural Language in BigQuery**.

### Module 7 — SQL Avanzado Aplicado a People Analytics
Window functions for turnover/cohorts, complex temporal metrics, subqueries and structured CTEs, headcount/FTE metrics, longitudinal employee analysis, exit pattern identification, demographic segmentation, query optimization, business logic standardization in SQL, result validation and QA.

### Module 8 — Dataform como Capa de Transformacion Profesional
ELT transformation principles in GCP, Dataform repository structure, declarative model definitions, dependency management, automated data quality tests, integrated documentation, environment control, BigQuery integration, controlled deployment, modularity/maintainability, **dimensional modeling** (star/snowflake), **SCD2** (Slowly Changing Dimensions), historical employee data evolution. Also covers: serverless functions intro, PA automation cases, event-based triggers, BigQuery integration, periodic load automation, error handling, structured logging, function permissions, execution monitoring, secure automation best practices.

### Module 9 — Integracion Real con GitHub
Version control in data projects, analytical repo structure, branching and Git flow, PR and SQL code review, Dataform transformation versioning, basic CI/CD integration, repo documentation, production change management, modification auditing, collaborative best practices.

### Module 10 — Backups y Recuperacion de Datos en GCP
BigQuery backup strategies, snapshots and temporal recovery, critical dataset export, backup automation, data retention policies, accidental deletion recovery, environment-separated backups, periodic restore testing, backup storage security, operational continuity plan.

### Module 11 — Gobierno del Dato y Seguridad en People Analytics
Data governance principles in HR, IAM access management, column-level and row-level security, sensitive data masking, confidential information classification, access/query auditing, data minimization, GDPR compliance in GCP, consent management, data responsibility culture, **Cloud DLP (Sensitive Data Protection)**, automatic PII detection, **Secret Manager** for credentials and API keys.

### Module 12 — Estrategia de FinOps y Control de Costes
BigQuery pricing models (On Demand vs Editions), Reservations and slot management, cost analysis via INFORMATION_SCHEMA, BigQuery/Dataform API integration for cost control, query/storage cost optimization, logical vs physical storage differences, **BI Engine** for dashboard acceleration, custom FinOps dashboards, automatic cost spike alerts.

### Module 13 — Uso Profesional de Google Sheets desde BigQuery
Secure BQ-Sheets connection, controlled sensitive data extraction, per-user access limitation, Connected Sheets, automatic data refresh, version control in shared sheets, best practices to prevent data leaks, exported data validation, collaborative use with HR, connected sheets governance.

### Module 14 — Looker como Capa de Consumo Analitico
Semantic modeling in Looker, official metric definition, dashboard access control, controlled self-service exploration, corporate metric governance, LookML model versioning, performance optimization, environment management, secure dashboard publishing, business insight communication.

### Module 15 — Vertex AI Aplicado a Datos de Personas
Vertex AI architecture in GCP, BigQuery integration, sensitive dataset preparation, responsible model training, employee data bias evaluation, model interpretability, notebook access control, ML environment separation, technical model documentation, ethical use of HR predictions, **BigQuery ML** for People Analytics, **Explainable AI (XAI)** in BigQuery ML.

### Module 16 — Uso de IA Generativa en Flujos Analiticos
Automatic insight generation, textual explanation of complex metrics, automatic dashboard summaries, assisted technical documentation, SQL generation from natural language, generated code validation, responsible use with anonymized data, BigQuery integration, data leak risk evaluation, human supervision best practices.

### Module 17 — Observabilidad y Control de Flujos de Datos
Structured logging in GCP, BigQuery job monitoring, load failure alerts, execution time control, bottleneck identification, transformation auditing, data quality metrics, end-to-end traceability, internal control panels, continuous improvement strategies, **Log Sinks** to BigQuery/Pub/Sub, log-based metrics, automatic pipeline failure alerts.

### Module 18 — Estandarizacion y Madurez del Equipo de Datos
Development standards, naming conventions, mandatory documentation, peer technical review, technical debt management, analytics maturity roadmap, clear role separation, continuous team training, operational risk assessment, responsible data-driven culture.

### Module 19 — Proyecto Final
Real People Analytics case definition, GCP architecture design, BigQuery modeling and transformation, Dataform implementation with version control, Cloud Functions automation, governance and security implementation, Looker integration, Vertex AI application, complete technical documentation, executive results presentation.

## Course Objectives

1. Design robust GCP data architectures adapted to People Analytics with sensitive data
2. Optimize data modeling, transformation and exploitation via BigQuery, advanced SQL, and Dataform in production environments
3. Implement version control, GitHub integration, and backup strategies for traceability, recovery, and maintainability
4. Apply data governance, security, and regulatory compliance in people data treatment within GCP
5. Use Vertex AI and generative AI responsibly and at scale to enrich analytics and support data-driven decisions

## Prerequisites

- Experience as data analyst, GCP fundamentals, Git, advanced SQL, BigQuery and Looker foundations
- Dedicated GCP project (non-production) with Cloud Billing enabled
- Enabled APIs: BigQuery, Dataform, Cloud Storage, Pub/Sub, Eventarc, Workflows, Cloud Scheduler, Cloud Composer, Cloud Functions, Vertex AI, Vertex AI Workbench/Notebooks, Cloud Logging, Cloud Monitoring, Secret Manager, Sensitive Data Protection, Looker, BigLake, BigQuery Sharing, and when applicable: Cloud Build, Artifact Registry, Cloud Run
- IAM roles (min. privilege): BigQuery Job User, Data Editor/Viewer, Dataform Editor/Admin, Cloud Functions Developer, Service Account User, Pub/Sub Editor, Eventarc Developer, Workflows Editor, Notebooks Admin, Logs Viewer, Monitoring Viewer/Editor
- Service accounts and Dataform-GitHub connection pre-configured
- Hardware: 8 cores, 32 GB RAM, 100 GB free disk, stable connection, no firewall/proxy blocks
- Environment and sample datasets validated and accessible to instructor at least 1 week before start

## Current Files

| File | Maps to | Description |
|------|---------|-------------|
| `modulo1_contenido_sesion.md` | Module 1 | Full lecture notes — 5 blocks, 2h session |
| `modulo1_diapositivas.md` | Module 1 | 22-slide deck with presenter notes |
| `modulo1_notebook_vertexai.ipynb` | Module 1 | Hands-on: synthetic data (2,000 employees), bias injection, detection, k-anonymity, rotation model, fairness check |
| `modulo2_libro_gcp.html` | Module 2 | Interactive HTML book (12 chapters): GCP project setup, BigQuery, Cloud Storage, schemas, data loading, SQL for PA, ETL medallion pipeline, external tables, production patterns, Vertex AI bridge |
| `test.ipynb` | Module 2 | Scratch notebook testing BigQuery/GCS connectivity via service account |
| `README.md` | — | Setup instructions and course overview (covers Module 1 only, needs update) |
| `.env` | — | Environment variable template (placeholders, no real credentials) |
| `requirements.txt` | — | Incomplete — only contains `google` |

## Synthetic Dataset

The Module 1 notebook generates `people_analytics_sintetico.csv` with ~2,000 employees:

**Fields**: `empleado_id`, `departamento` (8 depts), `nivel` (Junior→Director), `ciudad` (6 cities), `genero`, `edad`, `antiguedad_meses`, `salario_bruto`, `meses_sin_promocion`, `rating_desempeno` (1-5), `distancia_km`, `score_clima` (1-10), `dias_absentismo`, `horas_formacion`, `rotacion` (0/1)

**Intentional biases introduced**:
- 7% gender pay gap (controlled by level)
- Glass ceiling: 40% of women in Director/Lead reassigned to Senior
- Women get more months without promotion (x1.3)
- Rating bias: 25% of women with rating 5 reduced to 4

**Target variable**: `rotacion` — weighted probability from `meses_sin_promocion` (0.30), `score_clima` (0.25), `salario_bruto` (0.15), `horas_formacion` (0.10), `distancia_km` (0.10), `dias_absentismo` (0.10)

## Tech Stack

### Python Dependencies (actual)
`pandas`, `numpy`, `matplotlib`, `seaborn`, `scikit-learn`, `faker`, `scipy`, `google-cloud-aiplatform`, `google-cloud-bigquery`, `google-cloud-storage`, `google-oauth2`

### GCP Services (full course scope)
**Data**: BigQuery, Cloud Storage, BigLake, Analytics Hub, Connected Sheets
**Ingestion**: Pub/Sub, Cloud Data Fusion, Dataflow
**Transformation**: Dataform, BigQuery (Stored Procs, UDFs, Procedural Language)
**Orchestration**: Cloud Workflows, Cloud Composer (Airflow), Cloud Scheduler, Eventarc
**Compute**: Cloud Functions, Cloud Run
**ML/AI**: Vertex AI (AutoML Tabular, Workbench, Model Evaluation, Model Monitoring, Explainability), BigQuery ML, Gemini (generative AI)
**Visualization**: Looker (LookML), Looker Studio, BI Engine
**Security**: IAM, Secret Manager, Cloud DLP / Sensitive Data Protection, column/row-level security
**Observability**: Cloud Logging, Cloud Monitoring, Log Sinks
**CI/CD**: Cloud Build, Artifact Registry, GitHub integration
**Cost**: Reservations, INFORMATION_SCHEMA cost analysis, BI Engine

### Architecture Patterns
- **Medallion**: Bronze (raw) → Silver (clean) → Gold (business metrics)
- **Idempotent ETL**: DELETE-before-INSERT on date partitions
- **Event-driven pipelines**: Eventarc + Cloud Functions/Workflows
- **Dimensional modeling**: Star/snowflake schemas, SCD2
- **Service Account auth**: JSON credentials, never personal accounts
- **IAM least privilege**: Specific roles per service
- **Region**: `europe-west1` (Madrid) or `EU` multi-region for GDPR

### Regulatory Framework
- **GDPR**: Art. 5 (principles), Art. 6 (legal basis), Art. 9 (special categories), Art. 22 (automated decisions — human-in-the-loop mandatory), Art. 35 (DPIA)
- **Spanish law**: LOPDGDD, Estatuto de los Trabajadores Art. 20.3
- **Ethics filter**: Legal → Ethical → Useful → Actionable

## Environment Variables (.env template)

```
GCP_PROJECT_ID = ...
BQ_DATASET = ...
GCS_BUCKET_NAME = ...
GCS_DATA_PREFIX = ...
GCP_REGION = ...
LOGGING_FORMAT = ...
LOGGING_LEVEL = ...
```

## Working Conventions

- `np.random.seed(42)` for reproducibility
- Module 1 runs fully local (no GCP needed)
- Module 2+ requires GCP project access
- No git repository initialized in this project
- The HTML book (`modulo2_libro_gcp.html`) is a self-contained single-page app with dark theme, sidebar TOC, copy-to-clipboard, and responsive layout
