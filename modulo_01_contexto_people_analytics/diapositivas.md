# Diapositivas — Módulo 1: Contexto Real de Analítica de Datos en People Analytics

> Instrucciones: Cada sección `## Slide X` es una diapositiva. El texto bajo "Notas del presentador" es para el speaker, no se muestra en pantalla.

---

## Slide 1 — Portada

**Google Cloud Platform y Vertex AI**
**para Analistas de Datos Avanzados**

Módulo 1: Contexto Real de Analítica de Datos en People Analytics

*[Logo GCP + Vertex AI]*

---

## Slide 2 — Agenda del día

| Bloque | Tema | Duración |
|--------|------|----------|
| 1 | El dato de personas: qué lo hace diferente | 20 min |
| 2 | Casos reales y aplicaciones | 25 min |
| 3 | Marco regulatorio y ético | 20 min |
| 4 | Organización y madurez | 15 min |
| 5 | Q&A y discusión | 30 min |

---

## Slide 3 — ¿Por qué People Analytics es diferente?

**Un dato de personas NO es un dato más.**

Tres dimensiones que lo distinguen:

- **Sensibilidad** → Un registro mal expuesto puede destruir carreras
- **Confidencialidad** → Datos que los propios empleados desconocen que se recopilan
- **Ética** → No todo lo legal es ético, no todo lo ético es legal

> Notas del presentador: Abrir con el ejemplo de la empresa que analizó patrones de Slack para predecir rotación. Preguntar a la audiencia si les parece legítimo.

---

## Slide 4 — El filtro de 4 capas

```
¿Es LEGAL?
    ↓ Sí
¿Es ÉTICO?
    ↓ Sí
¿Es ÚTIL?
    ↓ Sí
¿Es ACCIONABLE?
    ↓ Sí
→ Adelante
```

**Si no pasa los 4 filtros, no se hace.**

Pregunta clave: *"¿Cómo se sentiría el empleado si supiera exactamente qué estamos haciendo con sus datos?"*

> Notas del presentador: Hacer ejercicio interactivo. Pedir a alguien que nombre un dato que recopilan y pasarlo por los 4 filtros juntos.

---

## Slide 5 — Tipologías de datos en RRHH

| Tipo | Ejemplos | Reto |
|------|----------|------|
| **Estructurados** | Salario, antigüedad, departamento | Calidad y actualización |
| **Semiestructurados** | Evaluaciones (texto+rating), encuestas, CVs | Normalización |
| **Derivados** | Scores de riesgo, índices de engagement | Interpretabilidad |
| **Comportamentales** | Patrones de conexión, uso de herramientas | Privacidad |
| **Externos** | Benchmarks salariales, mercado laboral | Comparabilidad |

> Notas del presentador: Enfatizar que el mayor valor de ML (y de Vertex AI) está en datos semiestructurados y comportamentales. Un HRIS da reporting; Vertex AI da predicción.

---

## Slide 6 — Ciclo de vida del dato en People Analytics

```
Generación → Recopilación → Almacenamiento → Procesamiento → Análisis → Acción → Revisión
     ↑                                                                                |
     └────────────────────────────── Feedback loop ────────────────────────────────────┘
```

**Stack en GCP:**
- Ingesta: Cloud Data Fusion / Dataflow
- Almacenamiento: Cloud Storage + BigQuery
- Procesamiento: Vertex AI Workbench
- Análisis: Vertex AI AutoML / BigQuery ML
- Visualización: Looker Studio
- Monitoreo: Vertex AI Model Monitoring

> Notas del presentador: Recalcar que sin el feedback loop (fase 7), no hay mejora. Muchas organizaciones llegan hasta "Análisis" y no cierran el ciclo.

---

## Slide 7 — Caso 1: Predicción de rotación

**Problema:** Empresa +5.000 empleados, 18% rotación anual, ~30K€/baja

**Datos:** Antigüedad, cambios salariales, evaluaciones, distancia, promociones, encuestas

**Solución:** Vertex AI AutoML Tabular → Clasificación binaria (se va / no se va en 6 meses)

**Resultado:**
- Precisión: 78%
- Factor #1: tiempo desde última promoción (no el salario)
- RRHH hizo retención proactiva en 40% de los casos

⚠️ **Trampa:** Si solo aprendes de quienes se fueron, perpetúas sesgos históricos

> Notas del presentador: Este es el caso más común en People Analytics. Detenerse en la trampa del sesgo — si históricamente se van más mujeres post-maternidad, el modelo lo codifica como "señal".

---

## Slide 8 — Caso 2: Análisis de absentismo

**Problema:** Absentismo no justificado +25% post-pandemia

**Enfoque:** Clustering (segmentación) + forecasting (serie temporal)

**Herramientas:** Vertex AI Workbench + BigQuery ML

**3 clusters descubiertos:**
1. 🗓️ Absentismo estacional (puentes, verano)
2. 👤 Absentismo asociado a manager específico
3. ⚡ Absentismo crónico pre-baja voluntaria

**Acción:** Intervención diferenciada por cluster

> Notas del presentador: El cluster 2 es el más interesante — demuestra cómo el dato revela problemas de liderazgo. Manejar con sensibilidad: no es "culpar al manager" sino entender patrones.

---

## Slide 9 — Caso 3: Evaluación de desempeño

**Problema:** Sesgo de "leniency" (todos 4/5) + sesgo de proximidad

**Enfoque:** NLP sobre texto de evaluaciones + detección de anomalías

**Herramienta:** Gemini en Vertex AI para análisis de texto

**Hallazgo:**
- Lenguaje diferencial: *"brillante"* para hombres vs. *"colaboradora"* para mujeres
- El texto de la evaluación predecía mejor la promoción futura que el rating numérico

> Notas del presentador: Este caso suele generar debate. El lenguaje que usamos revela sesgos inconscientes. Es un caso perfecto para LLMs.

---

## Slide 10 — Caso 4: Diversidad e inclusión

**Problema:** ¿Es equitativo nuestro proceso de selección?

**Enfoque:** Funnel de conversión por grupo + fairness metrics

**Herramienta:** Vertex AI Model Evaluation con métricas de equidad

**Hallazgo:** El modelo de scoring de CVs penalizaba gaps laborales → afectaba desproporcionadamente a mujeres y personas con discapacidad

**Métricas de equidad:**
- Equal Opportunity
- Demographic Parity
- Equalized Odds

> Notas del presentador: Conectar con el caso de Amazon que tuvo que retirar su herramienta de screening de CVs por sesgo de género. Es un caso muy conocido y relevante.

---

## Slide 11 — Riesgos habituales

| Riesgo | Ejemplo RRHH |
|--------|-------------|
| **Falsa causalidad** | "Quienes usan el gym rinden más" (¿o al revés?) |
| **Muestra pequeña** | Departamento de 8 personas → sin significancia |
| **Feedback loops** | Predices bajo desempeño → inviertes menos → se cumple |
| **Re-identificación** | "Mujer, 45-50, legal, Madrid" = una persona |
| **Proxy discrimination** | No usas género, pero "tiempo parcial" correlaciona 85% |
| **Survivor bias** | Solo analizas empleados actuales |

> Notas del presentador: Pasar rápido pero detenerse en feedback loops y proxy discrimination, que son los menos intuitivos.

---

## Slide 12 — Descriptiva → Predictiva → Prescriptiva

| | Descriptiva | Predictiva | Prescriptiva |
|--|-------------|-----------|--------------|
| **Pregunta** | ¿Qué pasó? | ¿Qué pasará? | ¿Qué hacer? |
| **Output** | Dashboards, KPIs | Scores, forecasting | Recomendaciones, alertas |
| **En GCP** | Looker Studio | Vertex AI AutoML | Vertex AI + reglas de negocio |
| **Riesgo** | Bajo | Medio | Alto |

⚠️ **A mayor prescripción, mayor escrutinio ético y legal**

> Notas del presentador: Un dashboard informativo tiene bajo riesgo. Un sistema que recomienda a quién promover debe pasar auditorías de sesgo.

---

## Slide 13 — GDPR: Artículos clave

| Artículo | Tema | Implicación |
|----------|------|-------------|
| Art. 5 | Principios | Minimización, limitación de finalidad |
| Art. 6 | Base legal | "Interés legítimo" no es comodín |
| Art. 9 | Datos especiales | Salud, etnia, afiliación → base reforzada |
| Art. 22 | Decisiones automatizadas | **Human-in-the-loop obligatorio** |
| Art. 35 | DPIA | Casi todo modelo predictivo sobre empleados la requiere |

> Notas del presentador: Detenerse en Art. 22 — un score de Vertex AI NO puede ser la única base para despido o no-promoción.

---

## Slide 14 — Checklist legal pre-proyecto

1. ☐ ¿Base legal para este tratamiento?
2. ☐ ¿Categorías especiales? → Base reforzada
3. ☐ ¿DPIA realizada?
4. ☐ ¿Empleados informados?
5. ☐ ¿Decisiones automatizadas? → Human-in-the-loop
6. ☐ ¿Minimización de datos cumplida?
7. ☐ ¿Política de retención definida?
8. ☐ ¿Datos adecuadamente protegidos?

**Si no puedes marcar todas → STOP. Primero resolver.**

> Notas del presentador: Imprimir esto y tenerlo visible en cada proyecto. Es la mejor herramienta anti-riesgo.

---

## Slide 15 — Sesgos algorítmicos

| Sesgo | Qué es | Ejemplo |
|-------|--------|---------|
| Histórico | Datos reflejan discriminación pasada | Menos promociones históricas a mujeres |
| Representación | Grupos infrarrepresentados | Pocos datos de personas con discapacidad |
| Medición | Variables miden diferente por grupo | "Horas en oficina" penaliza teletrabajo |
| Agregación | Un modelo para poblaciones heterogéneas | Oficina ≠ fábrica |
| Evaluación | El criterio de éxito está sesgado | Ratings de managers sesgados |

**Detectar en Vertex AI:** Model Evaluation (fairness slicing) + What-If Tool + Feature Attributions

> Notas del presentador: El mensaje clave es que los sesgos no son un error del modelo sino una herencia de los datos. Hay que buscarlos activamente.

---

## Slide 16 — Mitigación de sesgos: 4 niveles

```
PRE-PROCESAMIENTO          IN-PROCESAMIENTO         POST-PROCESAMIENTO        ORGANIZACIONAL
Eliminar features          Regularización           Ajustar umbrales          Comité de ética
sensibles y proxies        por equidad              por grupo                 de datos
```

**No es suficiente con uno solo. Se necesita un enfoque multi-capa.**

> Notas del presentador: Analogía con seguridad — no pones solo un firewall, pones defensa en profundidad. Con sesgos es igual.

---

## Slide 17 — Modelos organizativos Data ↔ RRHH

| Modelo | Descripción | Mejor para |
|--------|-------------|------------|
| Centralizado | Data sirve a todos | Organizaciones pequeñas |
| Embebido | Analistas dentro de RRHH | Velocidad, cercanía |
| Hub & Spoke | Centro de excelencia + embebidos | Balance (recomendado) |
| Federado | Plataforma self-service | Alta madurez |

**Recomendación:** Hub & Spoke con plataforma compartida en GCP

> Notas del presentador: Preguntar a la audiencia qué modelo tienen y qué problemas encuentran. Suele generar buena discusión.

---

## Slide 18 — Madurez analítica: 5 niveles

```
5. TRANSFORMACIONAL  → ML en producción, MLOps, comité de ética
4. AVANZADO          → Modelos predictivos validados, BigQuery integrado
3. PROACTIVO         → Análisis ad-hoc, primeros notebooks en Vertex AI
2. REACTIVO          → Reporting operativo, Excel, datos en silos
1. OPERACIONAL       → Solo nómina y fichajes
```

**¿Dónde está tu organización?**

> Notas del presentador: Hacer el assessment rápido (10 preguntas sí/no) con la audiencia. Genera autoconciencia y motivación.

---

## Slide 19 — Assessment rápido (ejercicio interactivo)

Responde Sí o No:
1. ¿Data warehouse centralizado para RRHH?
2. ¿Cruce de 3+ fuentes?
3. ¿Análisis más allá de reporting mensual?
4. ¿Al menos un modelo predictivo en uso?
5. ¿Resultados influyen en decisiones de RRHH?
6. ¿Governance de datos definido?
7. ¿DPIAs para proyectos analíticos?
8. ¿Comité de ética de datos?
9. ¿Medís impacto post-intervención?
10. ¿MLOps o pipelines automatizados?

**0-2:** Nivel 1-2 | **3-5:** Nivel 3 | **6-8:** Nivel 4 | **9-10:** Nivel 5

> Notas del presentador: Pedir que levanten la mano por niveles. Normalizar que la mayoría esté en nivel 2-3; el curso está diseñado para subir de nivel.

---

## Slide 20 — Ideas clave del módulo

1. Los datos de personas requieren un estándar ético y legal **superior**
2. El valor real: combinar datos estructurados con señales débiles
3. GDPR es un **framework**, no un obstáculo
4. Los sesgos son una **feature** de los datos históricos — hay que buscarlos
5. La tecnología es el medio; sin contexto y governance, es ruido

---

## Slide 21 — Preview: Módulo 2

**Lo que viene:**
- Configuración del entorno en GCP
- BigQuery como base de datos analítica
- Primeros pasos en Vertex AI Workbench
- Notebook práctico con datos sintéticos de People Analytics

*¡Manos al teclado!*

---

## Slide 22 — Q&A

**Preguntas para la discusión:**

- ¿Qué nivel de madurez analítica tenéis?
- ¿Habéis tenido un "incidente de datos" con datos de empleados?
- ¿Cómo gestionáis el equilibrio insight vs. privacidad?
- ¿Qué caso de uso os parece más accionable para empezar?

*30 minutos de discusión abierta*
