# Distribución de Contenido por Sesiones

## Google Cloud Platform y Vertex AI para Analistas de Datos Avanzados
**Duración total:** 25 horas | **Sesiones:** 12 | **Módulos:** 19

---

## Sesión 1 — Martes 14 de Abril (16:00–18:00)
**Tema 1: Contexto Real de Analítica de Datos en People Analytics**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 1.1 | Particularidades del dato de personas (sensibilidad, confidencialidad y ética) | 15 min |
| 1.2 | Tipologías de datos en RRHH: estructurados, semiestructurados y derivados | 10 min |
| 1.3 | Ciclo de vida del dato en People Analytics | 10 min |
| 1.4 | Casos reales: rotación, absentismo, desempeño y diversidad | 20 min |
| 1.5 | Riesgos habituales en el análisis de datos de empleados | 10 min |
| 1.6 | Relación entre analítica descriptiva, predictiva y prescriptiva | 10 min |
| 1.7 | Limitaciones legales y regulatorias (GDPR y normativa laboral) | 10 min |
| 1.8 | Sesgos algorítmicos en datos de personas | 10 min |
| 1.9 | Relación entre área de datos y RRHH | 5 min |
| 1.10 | Madurez analítica en departamentos de People Analytics | 10 min |
| — | **Notebook práctico:** Datos sintéticos, detección de sesgos, k-anonimidad, modelo de rotación | integrado |
| — | Q&A y discusión | 10 min |

---

## Sesión 2 — Lunes 20 de Abril (16:00–18:00)
**Tema 2: Arquitectura Actual de Datos en Google Cloud Platform**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 2.1 | Organización por proyectos en GCP para entornos analíticos | 10 min |
| 2.2 | Separación entre entornos: desarrollo, test y producción | 10 min |
| 2.3 | Arquitectura típica en People Analytics | 15 min |
| 2.4 | Integración de fuentes internas (HRIS, nómina, ATS) | 10 min |
| 2.5 | Ingesta segura de datos sensibles | 10 min |
| 2.6 | Data Lake vs Data Warehouse en GCP | 10 min |
| 2.7 | Flujo extremo a extremo desde origen hasta dashboard | 10 min |
| 2.8 | Gestión de identidades y accesos (IAM) | 10 min |
| 2.9 | Control de costes en arquitecturas analíticas | 5 min |
| 2.10 | Diseño orientado a escalabilidad y mantenibilidad | 5 min |
| 2.11 | BigLake para extender BigQuery a data lakes externos | 10 min |
| 2.12 | Analytics Hub para compartir datasets de forma segura | 5 min |
| — | **Notebook práctico:** Configuración de proyecto, autenticación, BigQuery client, Cloud Storage, primeras consultas | integrado |
| — | Q&A | 10 min |

---

## Sesión 3 — Lunes 27 de Abril (16:00–18:00)
**Tema 3: Ingesta de Datos en GCP + Tema 4: Pipelines Basados en Eventos**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 3.1 | Introducción a Pub/Sub como sistema de mensajería de GCP | 15 min |
| 3.2 | Integración con APIs externas y sistemas corporativos | 15 min |
| 3.3 | Arquitecturas de ingestión en tiempo real | 10 min |
| 3.4 | Comparación de costes y complejidad entre streaming y batch | 10 min |
| 4.1 | Arquitecturas event-driven en GCP | 10 min |
| 4.2 | Uso de Eventarc para reaccionar a eventos en Cloud Storage | 15 min |
| 4.3 | Automatización de pipelines de Dataflow | 10 min |
| 4.4 | Procesamiento batch basado en eventos | 10 min |
| 4.5 | Buenas prácticas para pipelines resilientes | 10 min |
| — | **Notebook práctico:** Pub/Sub publisher/subscriber, Eventarc triggers, pipeline event-driven | integrado |
| — | Q&A | 15 min |

---

## Sesión 4 — Lunes 4 de Mayo (16:00–18:00)
**Tema 5: Orquestación Profesional de Pipelines**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 5.1 | Conceptos de orquestación de flujos de datos | 15 min |
| 5.2 | Google Cloud Workflows para automatizaciones ligeras | 20 min |
| 5.3 | Cloud Composer (Managed Airflow) para pipelines complejos | 25 min |
| 5.4 | Comparación entre Workflows y Composer | 15 min |
| 5.5 | Integración con Eventarc y Cloud Scheduler | 15 min |
| — | **Notebook práctico:** Definición de Workflows YAML, DAG en Composer, Cloud Scheduler cron | integrado |
| — | Q&A | 10 min |

---

## Sesión 5 — Lunes 11 de Mayo (16:00–18:00)
**Tema 6: Buenas Prácticas de BigQuery para Ingenieros de Datos**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 6.1 | Modelado de datasets en entornos productivos | 10 min |
| 6.2 | Particionado y clustering eficiente | 15 min |
| 6.3 | Control de costes por consulta | 10 min |
| 6.4 | Optimización de rendimiento en tablas grandes | 10 min |
| 6.5 | Gestión de permisos a nivel dataset y tabla | 10 min |
| 6.6 | Uso de tablas intermedias y capas semánticas | 10 min |
| 6.7 | Estrategias de versionado de tablas | 5 min |
| 6.8 | Gestión de datos históricos y snapshots | 5 min |
| 6.9 | Prácticas de documentación técnica | 5 min |
| 6.10 | Revisión y auditoría de consultas críticas | 5 min |
| 6.11 | Stored Procedures para encapsular lógica compleja | 10 min |
| 6.12 | User Defined Functions (UDFs) reutilizables | 5 min |
| 6.13 | Uso de Procedural Language en BigQuery | 5 min |
| — | **Notebook práctico:** Particionado, clustering, INFORMATION_SCHEMA, Stored Procedures, UDFs | integrado |
| — | Q&A | 10 min |

---

## Sesión 6 — Lunes 18 de Mayo (16:00–18:00)
**Tema 7: SQL Avanzado Aplicado a People Analytics**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 7.1 | Window functions aplicadas a rotación y cohortes | 15 min |
| 7.2 | Cálculo de métricas temporales complejas | 10 min |
| 7.3 | Subqueries y CTEs estructurados profesionalmente | 10 min |
| 7.4 | Modelado de métricas de headcount y FTE | 10 min |
| 7.5 | Análisis longitudinal de empleados | 10 min |
| 7.6 | Identificación de patrones de salida | 10 min |
| 7.7 | Segmentación avanzada por variables demográficas | 10 min |
| 7.8 | Optimización de consultas complejas | 10 min |
| 7.9 | Estandarización de lógica de negocio en SQL | 10 min |
| 7.10 | Validación de resultados y control de calidad | 10 min |
| — | **Notebook práctico:** Window functions sobre dataset de empleados, CTEs de cohortes, métricas de headcount | integrado |
| — | Q&A | 15 min |

---

## Sesión 7 — Lunes 25 de Mayo (16:00–18:00)
**Tema 8: Dataform como Capa de Transformación Profesional**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 8.1 | Principios de transformación ELT en GCP | 10 min |
| 8.2 | Estructuración de repositorios en Dataform | 10 min |
| 8.3 | Definición de modelos declarativos | 10 min |
| 8.4 | Gestión de dependencias entre tablas | 10 min |
| 8.5 | Tests automáticos de calidad del dato | 10 min |
| 8.6 | Documentación integrada de transformaciones | 5 min |
| 8.7 | Control de entornos en Dataform | 5 min |
| 8.8 | Integración con BigQuery | 10 min |
| 8.9 | Flujo de despliegue controlado | 5 min |
| 8.10 | Buenas prácticas de modularidad y mantenibilidad | 5 min |
| 8.11 | Modelado dimensional (modelo estrella y snowflake) | 10 min |
| 8.12 | Implementación de Slowly Changing Dimensions (SCD2) | 10 min |
| 8.13 | Gestión de la evolución histórica del dato de empleado | 5 min |
| — | **Notebook práctico:** Estructura de proyecto Dataform, modelos SQLX, assertions, SCD2 | integrado |
| — | Q&A | 15 min |

---

## Sesión 8 — Lunes 1 de Junio (16:00–18:00)
**Tema 9: Integración Real con GitHub + Tema 10: Backups y Recuperación de Datos en GCP**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 9.1 | Control de versiones en proyectos de datos | 10 min |
| 9.2 | Estructura de repositorios analíticos | 10 min |
| 9.3 | Ramas y flujos de trabajo (Git flow) | 10 min |
| 9.4 | Pull requests y revisión de código SQL | 10 min |
| 9.5 | Versionado de transformaciones en Dataform | 5 min |
| 9.6 | Integración CI/CD básica | 10 min |
| 9.7 | Documentación en repositorio | 5 min |
| 10.1 | Estrategias de backup en BigQuery (snapshots, time travel) | 10 min |
| 10.2 | Exportación de datasets críticos y automatización | 10 min |
| 10.3 | Políticas de retención de datos | 5 min |
| 10.4 | Recuperación ante borrado accidental | 10 min |
| 10.5 | Plan de continuidad operativa | 5 min |
| — | **Notebook práctico:** Git workflow, Dataform-GitHub, BQ snapshots, time travel restore | integrado |
| — | Q&A | 10 min |

---

## Sesión 9 — Lunes 8 de Junio (16:00–18:00)
**Tema 11: Gobierno del Dato y Seguridad + Tema 12: Estrategia de FinOps**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 11.1 | Principios de data governance en RRHH | 10 min |
| 11.2 | Gestión de accesos con IAM (column-level y row-level security) | 10 min |
| 11.3 | Enmascaramiento de datos sensibles y clasificación | 10 min |
| 11.4 | Auditoría de accesos y consultas | 10 min |
| 11.5 | Cumplimiento de GDPR en GCP y gestión de consentimientos | 10 min |
| 11.6 | Cloud DLP / Sensitive Data Protection y Secret Manager | 10 min |
| 12.1 | Modelos de pricing de BigQuery (On Demand vs Editions) | 10 min |
| 12.2 | Reservations, slots y INFORMATION_SCHEMA para costes | 10 min |
| 12.3 | Optimización de costes (almacenamiento lógico vs físico, BI Engine) | 10 min |
| 12.4 | Dashboards de FinOps y alertas automáticas | 10 min |
| — | **Notebook práctico:** IAM policies, row-level security, DLP inspection, INFORMATION_SCHEMA cost queries | integrado |
| — | Q&A | 10 min |

---

## Sesión 10 — Lunes 15 de Junio (16:00–18:00)
**Tema 13: Google Sheets desde BigQuery + Tema 14: Looker como Capa de Consumo**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 13.1 | Conexión segura entre BigQuery y Sheets (Connected Sheets) | 10 min |
| 13.2 | Extracción controlada de datos sensibles y limitación por usuario | 10 min |
| 13.3 | Actualización automática, versionado y gobernanza de hojas | 10 min |
| 13.4 | Buenas prácticas para evitar fugas de información | 10 min |
| 14.1 | Modelado semántico en Looker y definición de métricas oficiales | 15 min |
| 14.2 | Control de acceso y exploración self-service controlada | 10 min |
| 14.3 | Versionado de modelos LookML y gestión de entornos | 10 min |
| 14.4 | Optimización de rendimiento y publicación segura de dashboards | 10 min |
| 14.5 | Comunicación de insights a negocio | 10 min |
| — | **Notebook práctico:** Connected Sheets setup, LookML model ejemplo, dashboard de rotación | integrado |
| — | Q&A | 15 min |

---

## Sesión 11 — Lunes 22 de Junio (16:00–18:30)
**Tema 15: Vertex AI Aplicado a Datos de Personas + Tema 16: IA Generativa en Flujos Analíticos**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 15.1 | Arquitectura de Vertex AI en GCP e integración con BigQuery | 10 min |
| 15.2 | Preparación de datasets sensibles para ML | 10 min |
| 15.3 | Entrenamiento responsable de modelos (AutoML Tabular) | 15 min |
| 15.4 | Evaluación de sesgos en datos de empleados (fairness metrics) | 15 min |
| 15.5 | Interpretabilidad: Feature Attributions y What-If Tool | 10 min |
| 15.6 | BigQuery ML aplicado a People Analytics | 15 min |
| 15.7 | Explainable AI (XAI) en BigQuery ML | 10 min |
| 15.8 | Control de acceso a notebooks y separación de entornos ML | 10 min |
| 16.1 | Generación automática de insights y explicación de métricas | 15 min |
| 16.2 | Generación de SQL desde lenguaje natural con Gemini | 10 min |
| 16.3 | Documentación técnica asistida y resumen de dashboards | 10 min |
| 16.4 | Uso responsable con datos anonimizados y supervisión humana | 10 min |
| — | **Notebook práctico:** BigQuery ML (modelo de rotación), Vertex AI AutoML, fairness slicing, Gemini para SQL/insights | integrado |
| — | Q&A | 10 min |

---

## Sesión 12 — Lunes 29 de Junio (16:00–18:30)
**Tema 17: Observabilidad + Tema 18: Estandarización + Tema 19: Proyecto Final**

| Tema | Contenido | Tiempo estimado |
|------|-----------|-----------------|
| 17.1 | Logging estructurado y monitorización de jobs de BigQuery | 10 min |
| 17.2 | Alertas, Log Sinks y log-based metrics | 10 min |
| 17.3 | Trazabilidad end-to-end y métricas de calidad del dato | 10 min |
| 18.1 | Estándares de desarrollo, nomenclatura y documentación | 10 min |
| 18.2 | Revisión técnica, deuda técnica y roadmap de madurez | 10 min |
| 18.3 | Cultura data-driven responsable | 5 min |
| — | *Pausa (5 min)* | 5 min |
| 19.1 | Definición de caso real y diseño de arquitectura GCP | 15 min |
| 19.2 | Implementación guiada: BigQuery + Dataform + automatización | 20 min |
| 19.3 | Gobierno, seguridad e integración con Looker y Vertex AI | 15 min |
| 19.4 | Documentación técnica y presentación ejecutiva de resultados | 10 min |
| — | **Cierre del curso, feedback y siguientes pasos** | 10 min |

---

## Resumen visual

```
Sesión  1  │ M1  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  Contexto PA
Sesión  2  │ M2  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  Arquitectura GCP
Sesión  3  │ M3  ░░░░░░░░░░░░░░░░░░  M4  ░░░░░░░░░░░░░░░░  Ingesta + Eventos
Sesión  4  │ M5  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  Orquestación
Sesión  5  │ M6  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  BigQuery Pro
Sesión  6  │ M7  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  SQL Avanzado
Sesión  7  │ M8  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  Dataform
Sesión  8  │ M9  ░░░░░░░░░░░░░░░░░░  M10 ░░░░░░░░░░░░░░░░  GitHub + Backups
Sesión  9  │ M11 ░░░░░░░░░░░░░░░░░░  M12 ░░░░░░░░░░░░░░░░  Gobierno + FinOps
Sesión 10  │ M13 ░░░░░░░░░░░░░░░░░░  M14 ░░░░░░░░░░░░░░░░  Sheets + Looker
Sesión 11  │ M15 ░░░░░░░░░░░░░░░░░░░░░░░░  M16 ░░░░░░░░░░  Vertex AI + GenAI
Sesión 12  │ M17 ░░░░░░░  M18 ░░░░░░░  M19 ░░░░░░░░░░░░░░  Obs + Std + Proyecto
```
