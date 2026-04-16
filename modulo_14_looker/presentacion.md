# Módulo 14: Looker como Capa de Consumo Analítico

## Información de la sesión
- **Sesión:** 10
- **Fecha:** Lunes 15 de Junio, 16:55–17:50
- **Duración:** ~55 minutos (sesión compartida con Módulo 13)
- **Prerequisitos:** Módulos 1–13 completados, dataset pa_gold operativo en BigQuery, acceso a instancia de Looker

---

## Tema 14.1: Modelado semántico en Looker

### Conceptos clave
- **Looker** se diferencia de otras herramientas de BI por su capa de **modelado semántico** en LookML: en lugar de escribir SQL en cada visualización, se define un modelo centralizado que describe las tablas, las relaciones, las dimensiones y las métricas, y todas las visualizaciones se construyen sobre este modelo.
- LookML actúa como una **capa de abstracción** entre BigQuery y los usuarios finales: los analistas de negocio exploran datos usando dimensiones y métricas definidas por el equipo de datos, sin necesidad de conocer la estructura de las tablas subyacentes.
- Los conceptos fundamentales de LookML son: **model** (conexión a base de datos y configuración), **explore** (punto de entrada para exploración), **view** (representación de una tabla o vista), **dimension** (atributo descriptivo) y **measure** (métrica calculada).

### Detalle técnico

**Estructura de un proyecto LookML para People Analytics:**

```
┌─────────────────────────────────────────────────────────────────┐
│           ESTRUCTURA DEL PROYECTO LOOKML                         │
│                                                                  │
│  people_analytics/                                               │
│  ├── models/                                                     │
│  │   └── people_analytics.model.lkml                            │
│  ├── views/                                                      │
│  │   ├── dim_empleado.view.lkml                                 │
│  │   ├── fact_rotacion.view.lkml                                │
│  │   ├── fact_metricas_mensuales.view.lkml                      │
│  │   ├── dim_departamento.view.lkml                             │
│  │   └── derived/                                                │
│  │       ├── dt_headcount_mensual.view.lkml                     │
│  │       └── dt_equidad_salarial.view.lkml                      │
│  ├── explores/                                                   │
│  │   ├── empleados.explore.lkml                                 │
│  │   ├── rotacion.explore.lkml                                  │
│  │   └── compensacion.explore.lkml                              │
│  ├── dashboards/                                                 │
│  │   ├── headcount_overview.dashboard.lookml                    │
│  │   ├── rotacion_mensual.dashboard.lookml                      │
│  │   └── equidad_salarial.dashboard.lookml                      │
│  └── tests/                                                      │
│      └── data_tests.lkml                                        │
└─────────────────────────────────────────────────────────────────┘
```

**Model: conexión y configuración global:**

```lookml
# models/people_analytics.model.lkml

connection: "pa-prod-bigquery"

# Persistencia de caché por defecto
persist_with: pa_datagroup

# Datagroup: controla cuándo se invalida la caché
datagroup: pa_datagroup {
  sql_trigger: SELECT MAX(fecha_snapshot) FROM `pa-prod.pa_gold.dim_empleado` ;;
  max_cache_age: "24 hours"
}

# Incluir todas las vistas y explores
include: "/views/**/*.view.lkml"
include: "/explores/**/*.explore.lkml"
include: "/dashboards/**/*.dashboard.lookml"
```

**View: dim_empleado (tabla de empleados):**

```lookml
# views/dim_empleado.view.lkml

view: dim_empleado {
  sql_table_name: `pa-prod.pa_gold.dim_empleado` ;;

  # --- Dimensiones de identificación ---
  dimension: empleado_id_hash {
    type: string
    sql: ${TABLE}.empleado_id_hash ;;
    primary_key: yes
    hidden: yes
    description: "Identificador pseudonimizado del empleado (SHA256)"
  }

  # --- Dimensiones descriptivas ---
  dimension: departamento {
    type: string
    sql: ${TABLE}.departamento ;;
    description: "Departamento al que pertenece el empleado"
    drill_fields: [nivel, genero]
  }

  dimension: nivel {
    type: string
    sql: ${TABLE}.nivel ;;
    description: "Nivel profesional: Junior, Mid, Senior, Lead, Director"
    order_by_field: nivel_order
  }

  dimension: nivel_order {
    type: number
    sql: CASE ${nivel}
           WHEN 'Junior' THEN 1
           WHEN 'Mid' THEN 2
           WHEN 'Senior' THEN 3
           WHEN 'Lead' THEN 4
           WHEN 'Director' THEN 5
         END ;;
    hidden: yes
  }

  dimension: genero {
    type: string
    sql: ${TABLE}.genero ;;
    description: "Género del empleado"
  }

  dimension: centro_trabajo {
    type: string
    sql: ${TABLE}.ciudad ;;
    description: "Ciudad del centro de trabajo"
  }

  # --- Dimensiones numéricas ---
  dimension: antigüedad_meses {
    type: number
    sql: ${TABLE}.antigüedad_meses ;;
    description: "Meses de antigüedad en la empresa"
  }

  dimension: antigüedad_grupo {
    type: tier
    tiers: [0, 6, 12, 24, 36, 60]
    style: integer
    sql: ${antigüedad_meses} ;;
    description: "Rango de antigüedad en meses"
  }

  dimension: salario_bruto {
    type: number
    sql: ${TABLE}.salario_bruto ;;
    value_format_name: eur
    description: "Salario bruto anual en EUR - CONFIDENCIAL"
    # Requiere permiso especial para ver (access_filter o user_attribute)
  }

  dimension: rango_salarial {
    type: tier
    tiers: [20000, 30000, 40000, 50000, 60000, 80000, 100000]
    style: integer
    sql: ${salario_bruto} ;;
    description: "Rango salarial para análisis sin exposición individual"
  }

  dimension: rating_desempeno {
    type: number
    sql: ${TABLE}.rating_desempeno ;;
    description: "Rating de desempeño (1-5)"
  }

  dimension: score_clima {
    type: number
    sql: ${TABLE}.score_clima ;;
    description: "Puntuación de clima laboral (1-10)"
  }

  dimension: rotacion {
    type: yesno
    sql: ${TABLE}.rotacion = 1 ;;
    description: "¿El empleado ha causado baja?"
  }

  # --- Dimensiones de fecha ---
  dimension_group: fecha_snapshot {
    type: time
    timeframes: [date, week, month, quarter, year]
    sql: ${TABLE}.fecha_snapshot ;;
    description: "Fecha del snapshot de datos"
  }

  # --- Medidas (métricas) ---
  measure: headcount {
    type: count_distinct
    sql: ${empleado_id_hash} ;;
    description: "Número de empleados únicos"
    drill_fields: [departamento, nivel, genero, headcount]
  }

  measure: salario_medio {
    type: average
    sql: ${salario_bruto} ;;
    value_format_name: eur
    description: "Salario bruto medio"
  }

  measure: salario_mediana {
    type: median
    sql: ${salario_bruto} ;;
    value_format_name: eur
    description: "Mediana del salario bruto"
  }

  measure: rating_medio {
    type: average
    sql: ${rating_desempeno} ;;
    value_format_name: decimal_1
    description: "Rating de desempeño medio"
  }

  measure: clima_medio {
    type: average
    sql: ${score_clima} ;;
    value_format_name: decimal_1
    description: "Puntuación media de clima laboral"
  }

  measure: tasa_rotacion {
    type: number
    sql: 1.0 * ${total_bajas} / NULLIF(${headcount}, 0) ;;
    value_format_name: percent_1
    description: "Tasa de rotación = bajas / headcount"
  }

  measure: total_bajas {
    type: count_distinct
    sql: ${empleado_id_hash} ;;
    filters: [rotacion: "Yes"]
    description: "Número de empleados que han causado baja"
  }

  measure: antigüedad_media {
    type: average
    sql: ${antigüedad_meses} ;;
    value_format_name: decimal_0
    description: "Antigüedad media en meses"
  }
}
```

**Explore: punto de entrada para análisis de empleados:**

```lookml
# explores/empleados.explore.lkml

explore: dim_empleado {
  label: "Empleados"
  description: "Exploración de datos de empleados: headcount, rotación, compensación y clima"

  # Siempre filtrar por el snapshot más reciente por defecto
  sql_always_where: ${fecha_snapshot_date} = (
    SELECT MAX(fecha_snapshot)
    FROM `pa-prod.pa_gold.dim_empleado`
  ) ;;

  # Access filter: cada usuario solo ve su departamento
  # (se combina con user_attribute, ver tema 14.3)
  access_filter: {
    field: dim_empleado.departamento
    user_attribute: departamento_usuario
  }

  # Joins
  join: dim_departamento {
    type: left_outer
    relationship: many_to_one
    sql_on: ${dim_empleado.departamento} = ${dim_departamento.nombre} ;;
  }
}
```

### Aplicación en People Analytics
- El modelado semántico en LookML es una inversión inicial que paga dividendos a largo plazo: una vez definido, todos los dashboards, explorations y reportes usan las mismas definiciones de métricas, eliminando discrepancias ("mi headcount no coincide con el tuyo").
- Las **drill_fields** permiten que un usuario haga clic en un número de headcount y vea el desglose por departamento, nivel y género, sin necesidad de crear visualizaciones adicionales.
- El campo `nivel_order` es un patrón habitual en LookML: permite que los niveles se ordenen lógicamente (Junior < Mid < Senior) en lugar de alfabéticamente.

---

## Tema 14.2: Definición de métricas oficiales

### Conceptos clave
- Una de las mayores fuentes de conflicto en People Analytics es la definición de métricas: ¿qué incluye el "headcount"? ¿La tasa de rotación cuenta los despidos? ¿El salario medio incluye los bonus?
- Looker, a través de LookML, permite definir cada métrica **una sola vez** con su fórmula exacta y su descripción, garantizando que todos los dashboards y exploraciones usan la misma definición.
- Las **derived tables** (tablas derivadas) permiten pre-calcular métricas complejas que no se pueden expresar como simples agregaciones, creando una capa de métricas avanzadas sobre las tablas base.

### Detalle técnico

**Catálogo de métricas oficiales de People Analytics:**

| Métrica | Definición | Fórmula | Medida LookML |
|---------|-----------|---------|---------------|
| **Headcount** | Empleados activos en la fecha de snapshot | COUNT(DISTINCT empleado_id WHERE rotacion=0) | `headcount` |
| **Tasa de rotación** | % de bajas sobre headcount total | bajas / headcount * 100 | `tasa_rotacion` |
| **Salario medio** | Media aritmética del salario bruto anual | AVG(salario_bruto) | `salario_medio` |
| **Compa-ratio** | Ratio del salario individual vs mediana del mercado/nivel | salario / mediana_nivel | Derived table |
| **Índice de clima** | Media de score_clima (1-10) | AVG(score_clima) | `clima_medio` |
| **Antigüedad media** | Media de antigüedad en meses | AVG(antigüedad_meses) | `antigüedad_media` |
| **Gender pay gap** | Diferencia % del salario medio entre géneros | (avg_M - avg_F) / avg_M * 100 | Derived table |

**Derived table para equidad salarial (gender pay gap):**

```lookml
# views/derived/dt_equidad_salarial.view.lkml

view: dt_equidad_salarial {
  derived_table: {
    sql:
      SELECT
        departamento,
        nivel,
        AVG(CASE WHEN genero = 'Hombre' THEN salario_bruto END) AS salario_medio_hombres,
        AVG(CASE WHEN genero = 'Mujer' THEN salario_bruto END) AS salario_medio_mujeres,
        COUNT(CASE WHEN genero = 'Hombre' THEN 1 END) AS n_hombres,
        COUNT(CASE WHEN genero = 'Mujer' THEN 1 END) AS n_mujeres,
        SAFE_DIVIDE(
          AVG(CASE WHEN genero = 'Hombre' THEN salario_bruto END) -
          AVG(CASE WHEN genero = 'Mujer' THEN salario_bruto END),
          AVG(CASE WHEN genero = 'Hombre' THEN salario_bruto END)
        ) * 100 AS gender_pay_gap_pct
      FROM `pa-prod.pa_gold.dim_empleado`
      WHERE fecha_snapshot = (SELECT MAX(fecha_snapshot) FROM `pa-prod.pa_gold.dim_empleado`)
        AND rotacion = 0
      GROUP BY departamento, nivel
      HAVING COUNT(*) >= 5
    ;;
    datagroup_trigger: pa_datagroup
  }

  dimension: departamento {
    type: string
    sql: ${TABLE}.departamento ;;
  }

  dimension: nivel {
    type: string
    sql: ${TABLE}.nivel ;;
  }

  measure: gender_pay_gap {
    type: average
    sql: ${TABLE}.gender_pay_gap_pct ;;
    value_format_name: decimal_1
    description: "Brecha salarial de género (%). Positivo = hombres cobran más."
    html:
      {% if value > 5 %}
        <span style="color: red;">{{ rendered_value }}%</span>
      {% elsif value > 0 %}
        <span style="color: orange;">{{ rendered_value }}%</span>
      {% else %}
        <span style="color: green;">{{ rendered_value }}%</span>
      {% endif %}
    ;;
  }

  measure: salario_medio_hombres {
    type: average
    sql: ${TABLE}.salario_medio_hombres ;;
    value_format_name: eur
  }

  measure: salario_medio_mujeres {
    type: average
    sql: ${TABLE}.salario_medio_mujeres ;;
    value_format_name: eur
  }
}
```

### Aplicación en People Analytics
- El **gender pay gap** es una métrica cada vez más regulada en España (Real Decreto 902/2020 de igualdad retributiva). Tener su definición exacta en LookML garantiza que todos los informes usan la misma fórmula y que cumple con los requisitos legales.
- Las derived tables se recalculan según el `datagroup_trigger`: cuando los datos de empleados se actualizan (nuevo snapshot), la derived table se regenera automáticamente.
- Cada medida incluye un campo `description` que documenta su definición exacta. Los usuarios pueden ver esta descripción al pasar el ratón sobre la métrica en la interfaz de Looker.

---

## Tema 14.3: Control de acceso a dashboards

### Conceptos clave
- Looker tiene un sistema de permisos granular basado en **model sets** (qué modelos puede ver un usuario), **permission sets** (qué acciones puede realizar) y **roles** (combinación de model sets + permission sets).
- Los **access filters** permiten que un mismo dashboard muestre datos diferentes a cada usuario según sus atributos (departamento, nivel de acceso, etc.).
- Este sistema se complementa con la seguridad de BigQuery (row-level, column-level) para crear una defensa en profundidad.

### Detalle técnico

**Configuración de roles en Looker:**

| Rol | Model Set | Permission Set | Usuarios |
|-----|-----------|----------------|----------|
| **PA Admin** | Todos los modelos | Admin completo | Equipo de datos (2-3 personas) |
| **PA Analyst** | people_analytics | Explore + crear looks + dashboards | Analistas de RRHH |
| **PA HRBP** | people_analytics | Explore (limitado) + ver dashboards | HRBPs |
| **PA Director** | people_analytics | Solo ver dashboards | Director RRHH, CFO |
| **PA Finance** | people_analytics_finance | Solo ver dashboards de compensación | Finance |

**Configurar access filters con user attributes:**

```lookml
# En el explore, el access_filter limita los datos según el departamento del usuario
explore: dim_empleado {
  # ... (configuración anterior)

  # Cada HRBP tiene asignado un user_attribute "departamento_usuario"
  # que se configura en Looker Admin → Users → User Attributes
  access_filter: {
    field: dim_empleado.departamento
    user_attribute: departamento_usuario
  }
}

# User attributes configurados en Looker Admin:
# ┌──────────────────────┬──────────────────────────┐
# │ Usuario              │ departamento_usuario      │
# ├──────────────────────┼──────────────────────────┤
# │ maria.garcia@        │ Marketing                │
# │ carlos.lopez@        │ Tecnología               │
# │ ana.martinez@        │ Finanzas                 │
# │ directora.rrhh@      │ _ALL_ (ve todo)          │
# └──────────────────────┴──────────────────────────┘
```

**Restringir campos sensibles por grupo:**

```lookml
# En la view dim_empleado, ocultar salario a ciertos grupos

dimension: salario_bruto {
  type: number
  sql: ${TABLE}.salario_bruto ;;
  value_format_name: eur
  description: "Salario bruto anual - CONFIDENCIAL"

  # Solo visible para usuarios con acceso a compensación
  required_access_grants: [puede_ver_salarios]
}

# Definir el access grant
access_grant: puede_ver_salarios {
  user_attribute: acceso_compensacion
  allowed_values: ["si"]
}
```

### Aplicación en People Analytics
- El patrón de **access filter por departamento** es el más utilizado en People Analytics: permite tener un único dashboard de headcount/rotación que automáticamente filtra los datos según el departamento del usuario conectado.
- Los **access grants** para campos de compensación garantizan que solo Comp & Ben y el Director de RRHH ven los salarios individuales en Looker, incluso si el modelo incluye esa dimensión.
- La configuración de roles se gestiona centralmente por el equipo de datos, no por los usuarios finales. Esto evita que un HRBP se otorgue a sí mismo permisos de exploración que no debería tener.

---

## Tema 14.4: Exploración self-service controlada

### Conceptos clave
- El valor real de Looker se materializa cuando los usuarios de negocio pueden explorar los datos por sí mismos, sin depender del equipo de datos para cada pregunta.
- El reto es equilibrar la **autonomía** del usuario (que pueda responder sus propias preguntas) con el **control** (que no acceda a datos sensibles ni genere consultas costosas).
- Las restricciones a nivel de campo, las exploraciones pre-configuradas y los filtros obligatorios permiten ofrecer self-service dentro de límites seguros.

### Detalle técnico

**Niveles de self-service en Looker:**

```
┌─────────────────────────────────────────────────────────────────┐
│           NIVELES DE SELF-SERVICE EN LOOKER                      │
│                                                                  │
│  Nivel 1: SOLO VER (rol PA Director)                            │
│  ├── Puede abrir dashboards predefinidos                        │
│  ├── Puede aplicar filtros de dashboard                         │
│  └── NO puede explorar datos ni crear looks                     │
│                                                                  │
│  Nivel 2: EXPLORAR (rol PA HRBP)                                │
│  ├── Puede explorar dentro del explore predefinido              │
│  ├── Puede añadir/quitar dimensiones y métricas                 │
│  ├── Puede crear gráficos y guardar looks personales            │
│  ├── Filtrado automático por departamento (access filter)       │
│  └── NO puede ver campos de compensación (access grant)         │
│                                                                  │
│  Nivel 3: ANALIZAR (rol PA Analyst)                             │
│  ├── Acceso completo al explore (incluyendo compensación)       │
│  ├── Puede crear dashboards y compartirlos                      │
│  ├── Puede usar SQL Runner para consultas ad-hoc                │
│  └── NO puede modificar el modelo LookML                        │
│                                                                  │
│  Nivel 4: MODELAR (rol PA Admin)                                │
│  ├── Acceso completo a LookML IDE                               │
│  ├── Puede modificar modelos, vistas y explores                 │
│  └── Responsable de la gobernanza del modelo                    │
└─────────────────────────────────────────────────────────────────┘
```

**Explore con filtros obligatorios:**

```lookml
# Explore con restricciones para HRBP
explore: dim_empleado {
  label: "Empleados"

  # Filtro obligatorio: siempre deben seleccionar un departamento
  always_filter: {
    filters: [dim_empleado.departamento: ""]
  }

  # Limitar las dimensiones visibles para ciertos roles
  # (las medidas de compensación están protegidas por access_grant)

  # Limitar el número de filas descargables
  # Se configura en Admin → Connections → Max query row limit
}
```

### Aplicación en People Analytics
- El self-service controlado reduce el backlog del equipo de datos en un 40-60% según la experiencia de organizaciones maduras: los HRBP pueden responder preguntas como "¿cuál es el headcount por nivel en mi departamento?" sin crear un ticket.
- El **always_filter** por departamento garantiza que las consultas son eficientes (BigQuery no escanea todos los departamentos) y seguras (combinado con access filter, refuerza la restricción).
- Es importante **formar a los HRBP** en el uso del explore: una sesión de 1 hora de "Looker para RRHH" con ejemplos reales genera adopción inmediata.

---

## Tema 14.5: Gobernanza de métricas corporativas

### Conceptos clave
- Un catálogo de métricas es la documentación centralizada de todas las métricas oficiales de People Analytics: su definición, fórmula, owner, fuente de datos y última revisión.
- LookML sirve como "código fuente" de las definiciones de métricas, pero el catálogo debe ser accesible también para usuarios no técnicos (en una wiki, Confluence o en el propio Looker).
- La gobernanza de métricas incluye un proceso de aprobación para nuevas métricas, un ciclo de revisión periódica y un proceso de deprecación para métricas que ya no se usan.

### Detalle técnico

**Estructura del catálogo de métricas:**

| Campo | Descripción | Ejemplo |
|-------|-------------|---------|
| **Nombre** | Nombre oficial de la métrica | Tasa de rotación voluntaria |
| **Definición** | Descripción clara y sin ambigüedad | % de empleados que causan baja voluntaria respecto al headcount total, en un período dado |
| **Fórmula** | Expresión matemática exacta | (bajas voluntarias / headcount inicio período) * 100 |
| **Granularidad** | Nivel de detalle mínimo publicable | Departamento (mínimo 5 personas) |
| **Fuente** | Tabla/vista de BigQuery | `pa-prod.pa_gold.fact_rotacion` |
| **LookML** | Medida en el modelo | `dim_empleado.tasa_rotacion` |
| **Owner** | Persona responsable de la definición | Responsable de Comp & Ben |
| **Frecuencia** | Con qué frecuencia se actualiza | Mensual (1er día hábil) |
| **Última revisión** | Fecha de la última validación | 2026-03-01 |

**Implementar el catálogo en LookML con descripciones:**

```lookml
# Cada medida incluye una descripción detallada que sirve como documentación

measure: tasa_rotacion_voluntaria {
  type: number
  sql: SAFE_DIVIDE(
    ${total_bajas_voluntarias},
    ${headcount_inicio_periodo}
  ) ;;
  value_format_name: percent_1
  description: "Tasa de rotación voluntaria: porcentaje de empleados que causan baja voluntaria
    respecto al headcount al inicio del período. Excluye despidos, jubilaciones y finalizaciones
    de contrato temporal. Granularidad mínima: departamento con >= 5 empleados.
    Owner: Comp & Ben. Revisada: 2026-03-01."
  label: "Tasa de rotación voluntaria (%)"
  group_label: "Métricas de rotación"
}

measure: tasa_rotacion_involuntaria {
  type: number
  sql: SAFE_DIVIDE(
    ${total_bajas_involuntarias},
    ${headcount_inicio_periodo}
  ) ;;
  value_format_name: percent_1
  description: "Tasa de rotación involuntaria: porcentaje de empleados desvinculados
    por decisión de la empresa. Incluye despidos y no renovaciones.
    Owner: Relaciones Laborales. Revisada: 2026-03-01."
  label: "Tasa de rotación involuntaria (%)"
  group_label: "Métricas de rotación"
}
```

### Aplicación en People Analytics
- El catálogo de métricas elimina la discusión más frecuente en las reuniones de dirección: "estos números no coinciden con los míos". Si todos usan la métrica definida en Looker, los números son siempre los mismos.
- La revisión periódica es importante: una métrica definida hace dos años puede ya no reflejar la realidad del negocio (ej: si la empresa pasó de contratos indefinidos a muchos temporales, la definición de "rotación" puede necesitar actualizarse).
- El **group_label** en LookML organiza las métricas en categorías lógicas que facilitan la navegación en el explore.

---

## Tema 14.6: Versionado de modelos LookML

### Conceptos clave
- LookML es código, y como tal, se gestiona con **control de versiones Git**. Looker tiene un IDE integrado que se conecta a un repositorio Git (GitHub, GitLab, Bitbucket) donde se almacena el modelo.
- El flujo de trabajo recomendado es: **rama de desarrollo** → **pull request** → **revisión por pares** → **merge a main** → **despliegue a producción**.
- Este flujo garantiza que los cambios en las definiciones de métricas, explores y dashboards pasen por una revisión antes de afectar a los usuarios finales.

### Detalle técnico

**Flujo de versionado en Looker:**

```
┌─────────────────────────────────────────────────────────────────┐
│           FLUJO DE TRABAJO GIT EN LOOKER                         │
│                                                                  │
│  1. DESARROLLO                                                   │
│     └── Analista activa "Development Mode" en Looker            │
│         → Se crea rama automática: dev-maria-garcia              │
│         → Los cambios son visibles SOLO para ese analista       │
│                                                                  │
│  2. CAMBIO                                                       │
│     └── Modifica una view o measure en el LookML IDE            │
│         → Looker valida la sintaxis en tiempo real               │
│         → El analista prueba el cambio en su explore personal   │
│                                                                  │
│  3. COMMIT + PR                                                  │
│     └── Commit del cambio → Push → Crear Pull Request           │
│         → Asignar revisor: otro miembro del equipo de datos     │
│                                                                  │
│  4. REVISIÓN                                                     │
│     └── El revisor verifica:                                    │
│         - ¿La definición de la métrica es correcta?             │
│         - ¿La descripción está actualizada?                     │
│         - ¿El cambio rompe algún dashboard existente?           │
│         - ¿Los permisos (access grants) son correctos?          │
│                                                                  │
│  5. MERGE + DEPLOY                                               │
│     └── Merge a main → Deploy automático a producción           │
│         → Todos los usuarios ven el cambio inmediatamente       │
│                                                                  │
│  6. VALIDACIÓN                                                   │
│     └── Content Validator: verifica que los dashboards           │
│         y looks existentes siguen funcionando                    │
└─────────────────────────────────────────────────────────────────┘
```

**Buenas prácticas de versionado:**

```lookml
# Cada cambio significativo debe documentarse con comentarios

# CHANGELOG:
# 2026-06-10 - maria.garcia@ - Añadida métrica gender_pay_gap
#   Motivo: Requisito del Real Decreto 902/2020
#   PR: #47
# 2026-05-15 - carlos.lopez@ - Añadido access_grant para compensación
#   Motivo: Restricción de acceso a salarios individuales
#   PR: #42
# 2026-04-20 - maria.garcia@ - Modelo inicial de People Analytics
#   PR: #1
```

### Aplicación en People Analytics
- El versionado de LookML es especialmente importante cuando las definiciones de métricas tienen implicaciones legales: si la fórmula del gender pay gap se modifica, el historial de Git documenta exactamente qué cambió, cuándo y por decisión de quién.
- La revisión de código en PR es una oportunidad para que el equipo valide las definiciones: "esta tasa de rotación incluye los contratos temporales, ¿debería incluirlos?"
- El **Content Validator** de Looker es una red de seguridad: después de cada merge, valida automáticamente que todos los dashboards y looks siguen referenciando dimensiones y medidas que existen.

---

## Tema 14.7: Optimización de rendimiento

### Conceptos clave
- El rendimiento de Looker depende de la eficiencia de las consultas SQL que genera contra BigQuery. Las **Persistent Derived Tables (PDTs)**, la **caché** y los **datagroups** son las herramientas principales para optimizar.
- Un PDT es una derived table que se materializa en BigQuery (se escribe como tabla real) en lugar de ejecutarse como subquery cada vez. Esto es ideal para cálculos complejos que no cambian frecuentemente.
- Los **datagroups** controlan cuándo se invalida la caché y cuándo se regeneran los PDTs, permitiendo alinear la frescura de los datos con la frecuencia de actualización de los pipelines.

### Detalle técnico

**PDT para métricas de headcount mensual:**

```lookml
# views/derived/dt_headcount_mensual.view.lkml

view: dt_headcount_mensual {
  derived_table: {
    sql:
      SELECT
        DATE_TRUNC(fecha_snapshot, MONTH) AS mes,
        departamento,
        nivel,
        genero,
        COUNT(DISTINCT empleado_id_hash) AS headcount,
        COUNT(DISTINCT CASE WHEN rotacion = 1 THEN empleado_id_hash END) AS bajas,
        AVG(salario_bruto) AS salario_medio,
        AVG(rating_desempeno) AS rating_medio,
        AVG(score_clima) AS clima_medio,
        AVG(antigüedad_meses) AS antigüedad_media
      FROM `pa-prod.pa_gold.dim_empleado`
      GROUP BY mes, departamento, nivel, genero
    ;;
    datagroup_trigger: pa_datagroup
    # La PDT se regenera cuando pa_datagroup detecta un nuevo snapshot
    # Esto ocurre típicamente una vez al día, a las ~3:00 AM

    # Particionado y clustering de la PDT en BigQuery
    partition_keys: ["mes"]
    cluster_keys: ["departamento", "nivel"]
  }

  dimension_group: mes {
    type: time
    timeframes: [month, quarter, year]
    sql: ${TABLE}.mes ;;
    description: "Mes del reporte"
  }

  dimension: departamento {
    type: string
    sql: ${TABLE}.departamento ;;
  }

  dimension: nivel {
    type: string
    sql: ${TABLE}.nivel ;;
  }

  dimension: genero {
    type: string
    sql: ${TABLE}.genero ;;
  }

  measure: headcount {
    type: sum
    sql: ${TABLE}.headcount ;;
    description: "Headcount total (pre-agregado mensualmente)"
  }

  measure: tasa_rotacion {
    type: number
    sql: SAFE_DIVIDE(SUM(${TABLE}.bajas), SUM(${TABLE}.headcount)) ;;
    value_format_name: percent_1
    description: "Tasa de rotación mensual"
  }

  measure: salario_medio {
    type: average
    sql: ${TABLE}.salario_medio ;;
    value_format_name: eur
  }
}
```

**Configuración de caché con datagroups:**

```lookml
# En el model file

# Datagroup principal: se invalida cuando hay nuevos datos de empleados
datagroup: pa_datagroup {
  sql_trigger: SELECT MAX(fecha_snapshot) FROM `pa-prod.pa_gold.dim_empleado` ;;
  max_cache_age: "24 hours"
  description: "Se invalida cuando hay un nuevo snapshot de empleados"
}

# Datagroup para métricas financieras (actualización mensual)
datagroup: pa_finanzas_datagroup {
  sql_trigger: SELECT MAX(mes) FROM `pa-prod.pa_gold.fact_costes_personal` ;;
  max_cache_age: "168 hours"  # 7 días
  description: "Se invalida cuando se cierran los costes del mes"
}
```

### Aplicación en People Analytics
- Las PDTs con `partition_keys` y `cluster_keys` se crean como tablas particionadas y clusterizadas en BigQuery, optimizando tanto el rendimiento como el coste de las consultas que Looker genera sobre ellas.
- El patrón recomendado es: tablas base en `pa_gold` (gestionadas por Dataform) + PDTs en Looker para agregaciones específicas de dashboards. Esto separa la responsabilidad: Dataform transforma, Looker agrega.
- La caché de 24 horas es adecuada para la mayoría de métricas de PA (los datos se actualizan diariamente). Para dashboards que necesiten datos intradiarios (ej: seguimiento de una campaña de contratación), se puede reducir el `max_cache_age`.

---

## Tema 14.8: Gestión de entornos

### Conceptos clave
- Looker tiene un concepto de **Development Mode** que permite a los desarrolladores probar cambios en LookML sin afectar a los usuarios de producción.
- Para entornos más complejos, se pueden configurar múltiples conexiones (desarrollo, staging, producción) que apuntan a diferentes proyectos de BigQuery.
- La gestión de entornos garantiza que los cambios se prueban completamente antes de llegar a producción, reduciendo el riesgo de errores en dashboards críticos.

### Detalle técnico

**Configuración multi-entorno:**

```
┌─────────────────────────────────────────────────────────────────┐
│           ENTORNOS EN LOOKER                                     │
│                                                                  │
│  DEVELOPMENT MODE (per-developer)                                │
│  ├── Rama Git: dev-<nombre-desarrollador>                       │
│  ├── Conexión BQ: pa-dev (proyecto pa-dev)                      │
│  ├── Visible solo para el desarrollador                         │
│  └── Cambios en LookML se prueban aquí primero                  │
│                                                                  │
│  STAGING (rama staging, post-PR)                                 │
│  ├── Rama Git: staging                                           │
│  ├── Conexión BQ: pa-staging (proyecto pa-staging)               │
│  ├── Visible para el equipo de datos                             │
│  └── Validación final antes de producción                        │
│                                                                  │
│  PRODUCCIÓN (rama main)                                          │
│  ├── Rama Git: main                                              │
│  ├── Conexión BQ: pa-prod (proyecto pa-prod)                    │
│  ├── Visible para todos los usuarios                             │
│  └── Solo se actualiza via merge aprobado                        │
│                                                                  │
│  Para equipos pequeños de PA, Development Mode + Production      │
│  suele ser suficiente (sin staging intermedio).                  │
└─────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- Para la mayoría de equipos de PA (2-5 personas), el flujo **Development Mode → PR → Production** es suficiente. Solo equipos grandes con múltiples desarrolladores de LookML necesitan un entorno de staging.
- Es importante que la conexión de desarrollo apunte a un proyecto de BigQuery con datos de prueba (no producción), evitando que las consultas de desarrollo consuman slots de producción o accedan a datos reales.
- El **Content Validator** se ejecuta automáticamente al hacer merge a main, verificando que los dashboards de producción no se rompen con los cambios.

---

## Tema 14.9: Publicación segura de dashboards

### Conceptos clave
- Los dashboards de Looker pueden publicarse de múltiples formas: dentro de la plataforma (spaces/folders), vía **embedding** (incrustados en otras aplicaciones), mediante **envíos programados** (email/Slack) y como **exportaciones** (PDF, CSV).
- Cada método de publicación tiene implicaciones de seguridad diferentes: un dashboard embebido en una intranet hereda la autenticación de la intranet, un envío por email genera un archivo estático que puede reenviarse.
- La política de publicación debe definir qué método se permite para cada nivel de clasificación de datos.

### Detalle técnico

**Matriz de publicación por clasificación:**

| Método de publicación | Público | Interno | Confidencial | Restringido |
|-----------------------|---------|---------|--------------|-------------|
| **Dashboard en Looker** | Permitido | Permitido | Permitido (con access filter) | Prohibido |
| **Embedding (iframe)** | Permitido | Con SSO | Prohibido | Prohibido |
| **Envío por email** | Permitido | Solo dominio interno | Prohibido | Prohibido |
| **Envío por Slack** | Permitido | Canal privado | Prohibido | Prohibido |
| **Exportación PDF** | Permitido | Con marca de agua | Prohibido | Prohibido |
| **Exportación CSV** | Permitido | Con aprobación | Prohibido | Prohibido |

**Configurar envío programado de dashboard:**

```
┌─────────────────────────────────────────────────────────────────┐
│        ENVÍO PROGRAMADO — INFORME MENSUAL DE ROTACIÓN           │
│                                                                  │
│  Dashboard: "Rotación Mensual por Departamento"                 │
│                                                                  │
│  Programación:                                                   │
│  ├── Frecuencia: Mensual, día 2 a las 09:00                    │
│  ├── Formato: PDF (inline en email)                             │
│  ├── Destinatarios: directora.rrhh@empresa.com,                │
│  │                  comite.direccion@empresa.com                │
│  ├── Filtros aplicados: último mes cerrado                      │
│  └── Condición: solo enviar si tasa_rotacion > 10%              │
│                                                                  │
│  Seguridad:                                                      │
│  ├── El PDF se genera con los datos que el destinatario         │
│  │   tendría acceso si abriera el dashboard directamente        │
│  ├── Se registra en el log de actividad de Looker               │
│  └── NO se permite el reenvío a direcciones externas            │
└─────────────────────────────────────────────────────────────────┘
```

**Embedding seguro con SSO:**

```lookml
# Para incrustar un dashboard en la intranet de RRHH
# se usa Looker Embedded con SSO (Single Sign-On)

# La URL de embedding incluye un token firmado que contiene:
# - user_email (identidad del usuario)
# - user_attributes (departamento, acceso_compensacion, etc.)
# - permissions (qué puede hacer)
# - session_length (duración de la sesión)

# El servidor de la intranet genera la URL firmada:
# https://empresa.looker.com/embed/dashboards/1?
#   embed_domain=https://intranet.empresa.com
#   &nonce=abc123
#   &signature=sha256_signature
```

### Aplicación en People Analytics
- El envío programado con **condición** es muy potente: "solo enviar el informe de rotación si la tasa supera el 10%" evita saturar a los directivos con informes cuando no hay nada destacable, y les alerta cuando sí hay un problema.
- El embedding en la intranet de RRHH es la forma más fluida de distribuir dashboards: los HRBP no necesitan aprender otra herramienta, acceden al dashboard desde la aplicación que ya usan.
- Las **exportaciones CSV** son el mayor riesgo de seguridad: un CSV con datos de empleados descargado al portátil del HRBP es un dato fuera de control. Se recomienda desactivar la exportación CSV para dashboards con datos confidenciales.

---

## Tema 14.10: Comunicación de insights a negocio

### Conceptos clave
- Un dashboard técnicamente perfecto pero incomprensible para RRHH es un dashboard inútil. La comunicación de insights es el último paso y el más importante: traducir datos en decisiones.
- Los principios de diseño de dashboards para audiencia de RRHH son: **simplicidad** (pocas métricas pero las correctas), **contexto** (siempre comparar con período anterior o con benchmark), **accionabilidad** (cada insight debe sugerir una acción) y **narración** (contar una historia, no mostrar números sueltos).
- Looker permite añadir **text tiles** con markdown para contextualizar los datos y guiar la interpretación.

### Detalle técnico

**Principios de diseño de dashboards de PA:**

```
┌─────────────────────────────────────────────────────────────────┐
│        DASHBOARD DESIGN PRINCIPLES PARA PEOPLE ANALYTICS        │
│                                                                  │
│  1. JERARQUÍA VISUAL (de arriba a abajo)                        │
│     ├── KPIs principales (headcount, rotación, clima)           │
│     ├── Tendencias temporales (gráficos de línea)               │
│     ├── Desglose por dimensión (barras/tablas)                  │
│     └── Detalle (drill-down disponible)                         │
│                                                                  │
│  2. CONTEXTO EN CADA MÉTRICA                                    │
│     ├── Valor actual + variación vs mes anterior                │
│     ├── Semáforo: verde/amarillo/rojo según umbral              │
│     └── Benchmark: comparar con media de la empresa             │
│                                                                  │
│  3. ACCIONABILIDAD                                               │
│     ├── Si rotación > 15%: destacar en rojo + nota explicativa  │
│     ├── Si clima < 6: alertar al manager del departamento       │
│     └── Si gender pay gap > 5%: flag para Comp & Ben            │
│                                                                  │
│  4. AUDIENCIA                                                    │
│     ├── Director RRHH: 3-5 KPIs, vista de empresa               │
│     ├── HRBP: desglose de su departamento, tendencias           │
│     └── Manager de línea: su equipo, comparado con media        │
│                                                                  │
│  5. LENGUAJE                                                     │
│     ├── Usar términos de RRHH, no de datos                      │
│     ├── "152 personas" no "152 COUNT DISTINCT empleado_id"      │
│     └── Añadir texto explicativo en tiles de markdown           │
└─────────────────────────────────────────────────────────────────┘
```

**Ejemplo de dashboard de rotación en LookML:**

```lookml
# dashboards/rotacion_mensual.dashboard.lookml

- dashboard: rotacion_mensual
  title: "Rotación Mensual — People Analytics"
  layout: newspaper
  preferred_viewer: dashboards-next

  filters:
    - name: periodo
      title: "Período"
      type: date_filter
      default_value: "6 months"

  elements:
    # KPI 1: Tasa de rotación actual
    - title: "Tasa de rotación"
      name: kpi_rotacion
      model: people_analytics
      explore: dt_headcount_mensual
      type: single_value
      fields: [dt_headcount_mensual.tasa_rotacion]
      filters:
        dt_headcount_mensual.mes_month: "last month"
      note_state: expanded
      note_text: "Porcentaje de bajas sobre headcount total. Objetivo: < 12%"
      conditional_formatting:
        - type: along a scale...
          value: 0.12
          palette:
            name: Red to Green
          bold: true

    # KPI 2: Headcount actual
    - title: "Headcount"
      name: kpi_headcount
      model: people_analytics
      explore: dt_headcount_mensual
      type: single_value
      fields: [dt_headcount_mensual.headcount]
      filters:
        dt_headcount_mensual.mes_month: "last month"
      note_text: "Empleados activos al cierre del mes"

    # Gráfico: Tendencia de rotación (6 meses)
    - title: "Tendencia de rotación"
      name: trend_rotacion
      model: people_analytics
      explore: dt_headcount_mensual
      type: looker_line
      fields: [dt_headcount_mensual.mes_month, dt_headcount_mensual.tasa_rotacion]
      sorts: [dt_headcount_mensual.mes_month]
      listen:
        periodo: dt_headcount_mensual.mes_month

    # Tabla: Rotación por departamento
    - title: "Rotación por departamento"
      name: tabla_rotacion_depto
      model: people_analytics
      explore: dt_headcount_mensual
      type: looker_grid
      fields: [
        dt_headcount_mensual.departamento,
        dt_headcount_mensual.headcount,
        dt_headcount_mensual.tasa_rotacion
      ]
      filters:
        dt_headcount_mensual.mes_month: "last month"
      sorts: [dt_headcount_mensual.tasa_rotacion desc]

    # Texto explicativo
    - title: ""
      name: nota_contexto
      type: text
      body_text: |
        **Nota metodológica:** La tasa de rotación incluye bajas voluntarias e involuntarias.
        Los departamentos con menos de 5 empleados se excluyen por política de k-anonimidad.
        Datos actualizados diariamente a las 03:00 AM. Fuente: pa-prod.pa_gold.dim_empleado.
```

### Aplicación en People Analytics
- El **note_text** en cada KPI es fundamental: cuando el Director de RRHH presenta el dashboard al comité de dirección, necesita poder explicar rápidamente qué significa cada número y cuál es el objetivo.
- El **conditional formatting** (semáforo rojo/verde) convierte un número abstracto en una señal clara: "rotación al 18% = rojo = hay un problema que requiere acción".
- Los dashboards de PA deben diseñarse con la participación de los stakeholders de RRHH, no solo del equipo de datos. Una sesión de co-diseño donde el HRBP describe las preguntas que necesita responder y el equipo de datos propone las visualizaciones adecuadas produce los mejores resultados.

---

## Resumen del módulo

```
┌────────────────────────────────────────────────────────────────┐
│          LOOKER — CAPACIDADES IMPLEMENTADAS                      │
│                                                                  │
│  MODELADO           │  SEGURIDAD            │  RENDIMIENTO      │
│  ────────           │  ──────────           │  ────────────     │
│  Views + dimensions │  Model/permission sets│  PDTs particionadas│
│  Measures oficiales │  Access filters       │  Datagroups/caché │
│  Derived tables     │  Access grants        │  BI Engine        │
│  Explores           │  User attributes      │  Materialized VW  │
│                     │  SSO embedding        │                   │
│                                                                  │
│  GOBERNANZA          │  COMUNICACIÓN                             │
│  ──────────          │  ─────────────                            │
│  Git + PR workflow   │  Dashboards orientados a acción           │
│  Content Validator   │  Envíos programados con condiciones       │
│  Catálogo métricas   │  Semáforos y contexto en cada KPI         │
│  Multi-entorno       │  Diseño co-creado con RRHH               │
└────────────────────────────────────────────────────────────────┘
```

---

## Próximo módulo

**Módulo 15: Vertex AI Aplicado a Datos de Personas** — Pasamos de la visualización al machine learning: modelos predictivos de rotación, detección de sesgos y explicabilidad, usando BigQuery ML y Vertex AI con datos de People Analytics.
