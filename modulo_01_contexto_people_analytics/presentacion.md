# Módulo 1: Contexto Real de Analítica de Datos en People Analytics

## Información de la sesión
- **Duración total:** 2 horas (90 min contenido + 30 min Q&A)
- **Audiencia:** Analistas de datos avanzados
- **Plataforma:** Google Cloud Platform / Vertex AI

---

## BLOQUE 1: El dato de personas — qué lo hace diferente (20 min)

### 1.1 Particularidades del dato de personas (sensibilidad, confidencialidad y ética)

Los datos de personas no son "un dato más". Tienen tres características que los distinguen radicalmente de datos de ventas, logística o marketing:

**Sensibilidad inherente:**
- Un registro de salario mal expuesto puede destruir el clima laboral de un equipo entero.
- Un dato de salud mental filtrado puede arruinar la carrera de un empleado.
- Las categorías protegidas (género, etnia, discapacidad, orientación sexual) son datos de nivel especial bajo GDPR (Art. 9).

**Confidencialidad operativa:**
- En People Analytics trabajamos con datos que los propios empleados no saben que se recopilan (metadata de correo, patrones de conexión, tiempos de respuesta).
- La frontera entre "dato laboral legítimo" y "vigilancia" es difusa y depende del contexto.
- Ejemplo práctico: una empresa analizó patrones de uso de Slack para predecir rotación. Legalmente viable en algunos contextos, éticamente cuestionable siempre.

**Ética como capa adicional:**
- No todo lo legal es ético, no todo lo ético es legal.
- El framework que proponemos: **Legal → Ético → Útil → Accionable**. Si no pasa los cuatro filtros, no se hace.
- Pregunta clave antes de cualquier análisis: "¿Cómo se sentiría el empleado si supiera exactamente qué estamos haciendo con sus datos?"

> **Ejercicio para la audiencia:** Piensen en un dato de RRHH que recopilan hoy. ¿Pasa los 4 filtros?

---

### 1.2 Tipologías de datos en RRHH

| Tipo | Ejemplos | Fuente típica | Reto principal |
|------|----------|---------------|----------------|
| **Estructurados** | Salario, antigüedad, departamento, nivel jerárquico, fecha de nacimiento | HRIS (SAP SuccessFactors, Workday, Meta4) | Calidad y actualización |
| **Semiestructurados** | Evaluaciones de desempeño (texto + rating), encuestas de clima, CVs | Plataformas de talent management | Normalización y extracción |
| **Derivados** | Score de riesgo de fuga, índice de engagement, clusters de perfiles | Modelos analíticos propios | Interpretabilidad y sesgo |
| **Comportamentales** | Patrones de conexión, uso de herramientas, tiempos de respuesta | Logs de sistemas, metadata | Privacidad y consentimiento |
| **Externos** | Benchmarks salariales, datos de mercado laboral, tendencias sectoriales | Proveedores (Mercer, Glassdoor, LinkedIn) | Comparabilidad y coste |

**Punto clave para Vertex AI:** Los datos semiestructurados y comportamentales son donde más valor aporta el ML. Un HRIS te da reporting; Vertex AI te da predicción a partir de señales débiles combinadas.

---

### 1.3 Ciclo de vida del dato en People Analytics

```
[Generación] → [Recopilación] → [Almacenamiento] → [Procesamiento] → [Análisis] → [Acción] → [Revisión]
     ↑                                                                                              |
     └──────────────────────────── Feedback loop ────────────────────────────────────────────────────┘
```

**Fase 1 — Generación:**
- El dato nace en múltiples sistemas: HRIS, nómina, fichajes, encuestas, evaluaciones, LMS.
- Problema #1: silos. Cada sistema tiene su propia lógica de identificación del empleado.
- En GCP: esto se resuelve con una capa de integración en **BigQuery** como data warehouse central.

**Fase 2 — Recopilación e ingesta:**
- ETL/ELT desde fuentes diversas.
- En GCP: **Cloud Data Fusion**, **Dataflow**, o simplemente conectores nativos de BigQuery.
- Consideración crítica: el consentimiento. ¿El empleado sabe que estos datos se usan para analytics?

**Fase 3 — Almacenamiento:**
- Datos crudos vs. datos procesados vs. datos anonimizados.
- En GCP: **Cloud Storage** (data lake) + **BigQuery** (data warehouse).
- Regla de oro: nunca mezclar datos identificables con datos analíticos en el mismo dataset.

**Fase 4 — Procesamiento:**
- Limpieza, normalización, feature engineering.
- En GCP: **Dataprep by Trifacta**, **BigQuery SQL**, **Vertex AI Workbench** (notebooks).
- Aquí es donde se aplican las reglas de anonimización y pseudonimización.

**Fase 5 — Análisis:**
- Desde dashboards descriptivos hasta modelos predictivos.
- En GCP: **Looker/Looker Studio** (descriptivo) + **Vertex AI** (predictivo/prescriptivo).

**Fase 6 — Acción:**
- El análisis sin acción es un coste, no una inversión.
- El output debe ser accionable por RRHH: alertas, recomendaciones, scores.

**Fase 7 — Revisión:**
- ¿El modelo sigue siendo preciso? ¿Han cambiado los patrones? ¿Hay drift?
- En GCP: **Vertex AI Model Monitoring**.

---

## BLOQUE 2: Casos reales y aplicaciones (25 min)

### 2.1 Casos reales: rotación, absentismo, desempeño y diversidad

#### Caso 1: Predicción de rotación voluntaria
- **El problema:** Una empresa de +5.000 empleados perdía el 18% anual. Cada baja costaba ~30K€ en reemplazo.
- **Los datos:** Antigüedad, último cambio salarial, evaluación de desempeño, distancia al centro de trabajo, histórico de promociones, respuestas de encuesta de clima.
- **El enfoque:** Modelo de clasificación binaria (se va / no se va en los próximos 6 meses).
- **En Vertex AI:** AutoML Tabular con los datos en BigQuery. Feature importance reveló que el factor #1 no era el salario, sino el tiempo desde la última promoción.
- **El resultado:** Precisión del 78%. RRHH pudo hacer retención proactiva en el 40% de los casos.
- **La trampa:** Si solo predices rotación de perfiles que ya se fueron antes, perpetúas sesgos (ej: si históricamente se van más mujeres después de maternidad, el modelo aprende eso como "señal").

#### Caso 2: Análisis de absentismo
- **El problema:** Absentismo no justificado subió un 25% post-pandemia.
- **Los datos:** Registros de fichaje, bajas médicas, calendario de vacaciones, datos de equipo, encuestas de bienestar.
- **El enfoque:** Segmentación (clustering) para identificar patrones + serie temporal para predecir picos.
- **En Vertex AI:** Notebooks en Workbench con scikit-learn para clustering + BigQuery ML para forecasting.
- **Hallazgo clave:** Tres clusters claros: (1) absentismo estacional, (2) absentismo asociado a manager específico, (3) absentismo crónico pre-baja voluntaria.
- **Acción:** Intervención diferenciada por cluster.

#### Caso 3: Evaluación de desempeño y calibración
- **El problema:** Las evaluaciones de desempeño tenían un sesgo de "leniency" (todos eran 4/5) y sesgo de proximidad (mejor rating a los más cercanos al manager).
- **Los datos:** Ratings históricos, texto de evaluaciones, datos del evaluador, composición del equipo.
- **El enfoque:** NLP para analizar el texto de las evaluaciones + detección de anomalías en los ratings.
- **En Vertex AI:** Gemini para analizar texto de evaluaciones y detectar patrones de lenguaje diferencial (ej: "brillante" para hombres vs. "colaboradora" para mujeres).
- **Hallazgo clave:** El lenguaje usado en las evaluaciones predecía mejor la promoción futura que el propio rating numérico.

#### Caso 4: Diversidad e inclusión
- **El problema:** La empresa quería medir si su proceso de selección era equitativo.
- **Los datos:** CVs anonimizados, resultados de entrevistas, datos demográficos (con consentimiento explícito), datos de progresión.
- **El enfoque:** Análisis de funnel de conversión por grupo demográfico + fairness metrics en el modelo de scoring de candidatos.
- **En Vertex AI:** Vertex AI Model Evaluation con métricas de equidad (equal opportunity, demographic parity).
- **Hallazgo clave:** El modelo de scoring de CVs penalizaba inconscientemente gaps laborales, afectando desproporcionadamente a mujeres y personas con discapacidad.
- **Acción:** Re-entrenamiento del modelo eliminando features proxy de categorías protegidas.

---

### 2.2 Riesgos habituales en el análisis de datos de empleados

| Riesgo | Descripción | Mitigación |
|--------|-------------|------------|
| **Falsa causalidad** | "Los que usan el gym corporativo rinden más" → ¿O es que los high performers tienen más tiempo/energía? | Diseño experimental, variables de control |
| **Tamaño muestral** | Departamentos pequeños = conclusiones estadísticamente insignificantes | Umbrales mínimos de n, técnicas bayesianas |
| **Feedback loops** | El modelo predice bajo desempeño → se invierte menos en esa persona → bajo desempeño real | Monitorización de impacto post-intervención |
| **Re-identificación** | "Mujer, 45-50 años, departamento legal, Madrid" = solo hay una persona | k-anonimidad, differential privacy |
| **Proxy discrimination** | No usas género, pero usas "tiempo parcial" que correlaciona al 85% con género | Análisis de correlaciones entre features y categorías protegidas |
| **Survivor bias** | Solo analizas empleados actuales, no los que ya se fueron | Incluir datos históricos de bajas |

---

## BLOQUE 3: Marco regulatorio y ético (20 min)

### 3.1 Relación entre analítica descriptiva, predictiva y prescriptiva

```
DESCRIPTIVA          PREDICTIVA              PRESCRIPTIVA
"¿Qué pasó?"        "¿Qué pasará?"          "¿Qué debemos hacer?"

Dashboards           Modelos ML              Sistemas de recomendación
KPIs                 Scores de riesgo        Alertas automatizadas
Reporting            Forecasting             Optimización

Looker Studio        Vertex AI AutoML        Vertex AI + reglas de negocio
BigQuery             BigQuery ML             Pipelines end-to-end

Riesgo bajo          Riesgo medio            Riesgo alto
(informar)           (predecir)              (decidir/recomendar)
```

**Regla práctica:** Cuanto más prescriptivo es el sistema, más escrutinio ético y legal necesita. Un dashboard de rotación es informativo; un sistema que recomienda a quién promover es prescriptivo y debe pasar auditorías de sesgo.

---

### 3.2 Limitaciones legales y regulatorias (GDPR y normativa laboral)

**GDPR — Artículos clave para People Analytics:**

- **Art. 5:** Principios de tratamiento. Licitud, lealtad, transparencia, limitación de finalidad, minimización de datos.
- **Art. 6:** Bases legales. En el contexto laboral, el "interés legítimo" del empleador es la base más común, pero NO es un comodín.
- **Art. 9:** Categorías especiales (salud, etnia, afiliación sindical...). Requieren base legal reforzada.
- **Art. 22:** Decisiones automatizadas. Los empleados tienen derecho a no ser objeto de decisiones basadas únicamente en tratamiento automatizado que les afecten significativamente.
  - **Implicación práctica:** Un modelo de Vertex AI que genere un score de riesgo de rotación NO puede ser la única base para una decisión de despido o no-promoción. Siempre debe haber intervención humana significativa ("human in the loop").
- **Art. 35:** Evaluación de impacto (DPIA). Obligatoria cuando el tratamiento puede entrañar un alto riesgo para los derechos de los empleados. Casi cualquier modelo predictivo sobre empleados requiere DPIA.

**Normativa laboral española (contexto adicional):**
- Estatuto de los Trabajadores, Art. 20.3: El empleador puede adoptar medidas de vigilancia y control, pero con proporcionalidad.
- LOPDGDD (Ley Orgánica 3/2018): Complementa GDPR en España.
- Criterio AEPD: Los empleados deben ser informados de forma clara y accesible sobre qué analytics se realizan.

**Checklist legal antes de lanzar un proyecto de People Analytics:**
1. ☐ ¿Tenemos base legal para este tratamiento? (Art. 6 GDPR)
2. ☐ ¿Tratamos categorías especiales? Si sí, ¿tenemos base reforzada? (Art. 9)
3. ☐ ¿Hemos realizado una DPIA? (Art. 35)
4. ☐ ¿Los empleados están informados? (Art. 13/14)
5. ☐ ¿Hay decisiones automatizadas? Si sí, ¿hay human-in-the-loop? (Art. 22)
6. ☐ ¿Cumplimos minimización de datos? ¿Realmente necesitamos todas estas variables?
7. ☐ ¿Tenemos política de retención definida?
8. ☐ ¿Los datos están adecuadamente protegidos? (cifrado, accesos, auditoría)

---

### 3.3 Sesgos algorítmicos en datos de personas

**Tipos de sesgo en People Analytics:**

| Sesgo | Descripción | Ejemplo en RRHH |
|-------|-------------|-----------------|
| **Sesgo histórico** | Los datos reflejan discriminación pasada | Si históricamente se promocionó menos a mujeres, el modelo aprende que "ser mujer" correlaciona con "no promoción" |
| **Sesgo de representación** | Grupos infrarrepresentados en los datos de entrenamiento | Pocos datos de empleados con discapacidad → predicciones menos fiables para ese grupo |
| **Sesgo de medición** | Las variables miden cosas diferentes para diferentes grupos | "Horas en oficina" como proxy de productividad penaliza a quienes teletrabajan (desproporcionadamente, cuidadores) |
| **Sesgo de agregación** | Un modelo único para poblaciones heterogéneas | Un modelo de engagement entrenado en oficinas centrales no funciona para fábricas |
| **Sesgo de evaluación** | El propio criterio de éxito está sesgado | Si "buen desempeño" se define por ratings de managers y los managers tienen sesgos, el modelo hereda esos sesgos |

**Cómo detectar sesgos en Vertex AI:**
- **Vertex AI Model Evaluation:** Métricas de fairness por grupo (sliced evaluation).
- **What-If Tool:** Exploración interactiva de cómo cambian las predicciones al modificar features sensibles.
- **Explainability (Feature Attributions):** Si "género" o proxies de género tienen alta importancia → red flag.

**Cómo mitigar:**
1. **Pre-procesamiento:** Eliminar features sensibles y proxies fuertes.
2. **In-procesamiento:** Regularización por equidad durante el entrenamiento.
3. **Post-procesamiento:** Ajustar umbrales de decisión por grupo para igualar tasas de error.
4. **Organizacional:** Comité de ética de datos que revise antes del despliegue.

---

## BLOQUE 4: Organización y madurez (15 min)

### 4.1 Relación entre área de datos y RRHH

**El problema clásico:**
- Data team: "RRHH no sabe formular preguntas analíticas"
- RRHH: "Data no entiende el contexto del negocio"

**Modelos organizativos:**

| Modelo | Descripción | Pros | Contras |
|--------|-------------|------|---------|
| **Centralizado** | Equipo de data sirve a todos los departamentos, incluido RRHH | Consistencia metodológica, economías de escala | Lejanía del contexto de negocio, cola de priorización |
| **Embebido** | Analistas dentro del equipo de RRHH | Cercanía al problema, velocidad | Aislamiento técnico, estándares divergentes |
| **Hub & Spoke** | Centro de excelencia + analistas embebidos | Balance entre estándar y cercanía | Complejidad organizativa, doble reporting |
| **Federado con plataforma** | Plataforma self-service (ej: Vertex AI Workbench) + comunidad de práctica | Escalabilidad, autonomía | Requiere madurez analítica mínima, governance |

**Recomendación para arrancar:** Hub & Spoke con plataforma compartida en GCP. El centro de excelencia define estándares, pipelines base y governance. Los analistas embebidos en RRHH usan Vertex AI Workbench con templates predefinidos.

**Claves para una buena colaboración:**
1. **Diccionario de datos compartido** — ¿Qué significa exactamente "rotación"? ¿Incluye jubilaciones? ¿Y despidos?
2. **SLAs de datos** — ¿Con qué frecuencia se actualiza cada fuente?
3. **Proceso de demanda** — ¿Cómo pide RRHH un análisis? ¿Cómo se prioriza?
4. **Feedback post-acción** — ¿Funcionó la intervención basada en el análisis? Sin este loop, no hay mejora.

---

### 4.2 Madurez analítica en departamentos de People Analytics

**Modelo de madurez en 5 niveles:**

```
Nivel 5: TRANSFORMACIONAL
   → People Analytics dirige decisiones estratégicas de negocio
   → Modelos prescriptivos en producción
   → Vertex AI pipelines automatizados, MLOps completo
   → Comité de ética de datos activo

Nivel 4: AVANZADO
   → Modelos predictivos validados y en uso
   → Integración de datos multi-fuente en BigQuery
   → Vertex AI para experimentación y algunos modelos en producción
   → DPIA realizadas, governance definido

Nivel 3: PROACTIVO
   → Análisis ad-hoc con cierta sofisticación (regresiones, clusters)
   → Data warehouse parcialmente integrado
   → Primeros experimentos en Vertex AI Workbench
   → Conciencia de sesgos y privacidad

Nivel 2: REACTIVO
   → Reporting operativo (headcount, rotación, absentismo)
   → Datos en silos, extracciones manuales
   → Excel/Sheets como herramienta principal
   → Cumplimiento GDPR básico

Nivel 1: OPERACIONAL
   → Solo datos administrativos (nómina, fichajes)
   → Sin análisis, solo registro
   → Cero infraestructura analítica
```

**Assessment rápido — ¿En qué nivel está tu organización?**

| Pregunta | Sí = +1 punto |
|----------|---------------|
| ¿Tenéis un data warehouse centralizado para datos de RRHH? | |
| ¿Podéis cruzar datos de al menos 3 fuentes diferentes? | |
| ¿Hacéis análisis más allá de reporting mensual? | |
| ¿Tenéis al menos un modelo predictivo en uso? | |
| ¿Los resultados analíticos influyen en decisiones de RRHH? | |
| ¿Tenéis un proceso de governance de datos definido? | |
| ¿Realizáis DPIAs para proyectos analíticos? | |
| ¿Tenéis un comité de ética de datos o similar? | |
| ¿Medís el impacto de las intervenciones basadas en datos? | |
| ¿Tenéis MLOps o pipelines automatizados? | |

- **0-2 puntos:** Nivel 1-2 (Operacional/Reactivo)
- **3-5 puntos:** Nivel 3 (Proactivo)
- **6-8 puntos:** Nivel 4 (Avanzado)
- **9-10 puntos:** Nivel 5 (Transformacional)

---

## BLOQUE 5: Cierre y Q&A (30 min)

### Resumen de ideas clave
1. Los datos de personas requieren un estándar ético y legal superior a otros datos de negocio.
2. El valor real está en combinar datos estructurados con señales débiles (texto, comportamiento).
3. GDPR no es un obstáculo sino un framework — si lo cumples, tu analytics es más robusto.
4. Los sesgos no son un bug, son una feature de los datos históricos. Hay que detectarlos activamente.
5. La tecnología (Vertex AI) es el medio, no el fin. Sin contexto de negocio y governance, es ruido.

### Preguntas guía para la discusión
- ¿Qué nivel de madurez analítica tenéis en vuestro departamento?
- ¿Habéis tenido algún "incidente de datos" con datos de empleados?
- ¿Cómo gestionáis el equilibrio entre insight y privacidad?
- ¿Qué caso de uso os parece más accionable para empezar?

### Preview del Módulo 2
En el siguiente módulo entraremos directamente en GCP: configuración de entorno, BigQuery como base, y primeros pasos en Vertex AI Workbench con datos reales (sintéticos) de People Analytics.

---

## Recursos adicionales
- Google Cloud: [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- AEPD: Guía sobre protección de datos en relaciones laborales
- Paper: "Fairness and Machine Learning" (Barocas, Hardt, Narayanan)
- Libro: "People Analytics in the Era of Big Data" (Isson & Harriott)
- Framework: "Responsible AI practices" de Google
