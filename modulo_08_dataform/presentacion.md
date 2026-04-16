# Módulo 8: Dataform como Capa de Transformación Profesional

## Información de la sesión
- **Sesión:** 7
- **Fecha:** Lunes 25 de Mayo, 16:00–18:00
- **Duración:** 2 horas (sesión completa)
- **Prerequisitos:** Módulos 1–7 completados, SQL avanzado en BigQuery

---

## Tema 8.1: Principios de transformación ELT en GCP

### Conceptos clave
- **ETL** (Extract-Transform-Load) transforma los datos antes de cargarlos en el destino. **ELT** (Extract-Load-Transform) carga primero los datos crudos y transforma dentro del destino (BigQuery).
- En GCP, la arquitectura ELT es la opción natural: BigQuery actúa como motor de almacenamiento y transformación simultáneamente, eliminando la necesidad de herramientas intermedias de transformación.
- **Dataform** es la herramienta nativa de GCP para orquestar transformaciones ELT dentro de BigQuery. Fue adquirida por Google en 2020 e integrada en la consola de GCP.
- La filosofía ELT se alinea con el enfoque "medallion" (bronze/silver/gold): los datos crudos se cargan en bronze, y las transformaciones a silver y gold se definen declarativamente en Dataform.

### Detalle técnico

**Comparación ETL vs. ELT:**

| Aspecto | ETL | ELT |
|---------|-----|-----|
| **Dónde se transforma** | En servidor intermedio (Spark, Airflow) | En el destino (BigQuery) |
| **Motor de cómputo** | Cluster externo | Motor nativo de BigQuery |
| **Escalabilidad** | Depende del cluster | Escala automáticamente |
| **Coste** | Cluster + almacenamiento intermedio | Solo BigQuery (pay-per-query) |
| **Lenguaje** | Python, Scala, etc. | SQL (SQLX en Dataform) |
| **Complejidad operativa** | Alta (infraestructura de ETL) | Baja (serverless) |
| **Latencia** | Mayor (pasos intermedios) | Menor (transformación directa) |
| **Ideal para** | Transformaciones complejas (ML) | Transformaciones SQL-céntricas |

**Arquitectura ELT con Dataform en el proyecto de People Analytics:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FLUJO ELT COMPLETO                          │
│                                                                     │
│  FUENTES               INGESTA           TRANSFORMACIÓN    CONSUMO  │
│                                          (Dataform)                 │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────┐   ┌───────┐ │
│  │ SAP HCM  │───>│  Cloud       │───>│  pa_bronze    │   │Looker │ │
│  │ Workday  │    │  Functions   │    │  (raw data)   │   │Studio │ │
│  │ Sheets   │    │  Pub/Sub     │    └──────┬────────┘   └───┬───┘ │
│  │ CSV/API  │    │  Dataflow    │           │                │     │
│  └──────────┘    └──────────────┘    ┌──────▼────────┐       │     │
│                                      │  pa_silver    │       │     │
│                                      │  (clean)      │       │     │
│                                      └──────┬────────┘       │     │
│                                      ┌──────▼────────┐       │     │
│                                      │  pa_gold      │───────┘     │
│                                      │  (business)   │             │
│                                      └───────────────┘             │
└─────────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- **Simplicidad operativa:** Los equipos de People Analytics suelen ser pequeños (2-5 personas). ELT con Dataform permite mantener toda la lógica en SQL sin necesidad de ingenieros de datos especializados en Python/Spark.
- **Iteración rápida:** Cuando HR pide una nueva métrica, el analista la define en SQL y Dataform la despliega automáticamente.
- **Trazabilidad completa:** Cada transformación está versionada en GitHub y documentada dentro del propio Dataform.

---

## Tema 8.2: Estructuración de repositorios en Dataform

### Conceptos clave
- Un **repositorio de Dataform** tiene una estructura de directorios estándar que separa definiciones (modelos), includes (código reutilizable) y configuración.
- La organización del repositorio refleja la arquitectura de datos: separar por capa (bronze/silver/gold) o por dominio.
- Los archivos de configuración (`dataform.json`, `package.json`) definen el entorno, el proyecto de GCP y las dependencias.

### Detalle técnico

**Estructura de repositorio recomendada para People Analytics:**

```
people-analytics-dataform/
├── dataform.json                    # Configuración principal
├── package.json                     # Dependencias (Dataform core)
├── definitions/                     # Modelos SQLX
│   ├── bronze/                      # Capa bronze (staging)
│   │   ├── stg_empleados.sqlx
│   │   ├── stg_evaluaciones.sqlx
│   │   ├── stg_movimientos.sqlx
│   │   └── stg_nomina.sqlx
│   ├── silver/                      # Capa silver (limpieza)
│   │   ├── silver_empleados.sqlx
│   │   ├── silver_evaluaciones.sqlx
│   │   ├── silver_movimientos.sqlx
│   │   └── silver_nomina.sqlx
│   ├── gold/                        # Capa gold (negocio)
│   │   ├── dimensions/
│   │   │   ├── dim_empleado.sqlx
│   │   │   ├── dim_departamento.sqlx
│   │   │   └── dim_tiempo.sqlx
│   │   ├── facts/
│   │   │   ├── fact_rotacion.sqlx
│   │   │   ├── fact_evaluaciones.sqlx
│   │   │   └── fact_headcount.sqlx
│   │   └── metrics/
│   │       ├── gold_tasa_rotacion_mensual.sqlx
│   │       ├── gold_brecha_salarial.sqlx
│   │       └── gold_headcount_mensual.sqlx
│   └── assertions/                  # Tests de calidad
│       ├── assert_empleados_sin_duplicados.sqlx
│       ├── assert_salarios_rango_valido.sqlx
│       └── assert_integridad_referencial.sqlx
├── includes/                        # Código reutilizable
│   ├── constants.js                 # Constantes (departamentos válidos, etc.)
│   ├── helpers.js                   # Funciones auxiliares
│   └── quality_checks.js           # Macros de validación
└── .gitignore
```

**Archivo `dataform.json`:**

```json
{
    "defaultSchema": "pa_dataform",
    "assertionSchema": "pa_dataform_assertions",
    "warehouse": "bigquery",
    "defaultDatabase": "pa-prod",
    "defaultLocation": "EU",
    "vars": {
        "env": "prod",
        "fecha_corte": "2025-04-01"
    }
}
```

**Archivo `package.json`:**

```json
{
    "name": "people-analytics-dataform",
    "dependencies": {
        "@dataform/core": "2.9.0"
    }
}
```

### Aplicación en People Analytics
- **Onboarding rápido:** Un nuevo analista puede entender toda la arquitectura de transformación mirando la estructura de directorios.
- **Separación de responsabilidades:** Los modelos bronze los mantiene el equipo de ingeniería; silver y gold, el equipo de analytics.
- **Escalabilidad:** Añadir un nuevo dominio (e.g., formación) es tan simple como crear nuevos archivos SQLX en las carpetas correspondientes.

---

## Tema 8.3: Definición de modelos declarativos

### Conceptos clave
- En Dataform, un **modelo** es un archivo `.sqlx` que define una transformación SQL de forma declarativa: se especifica qué se quiere obtener, no cómo ejecutarlo.
- Cada modelo tiene un bloque `config {}` que define el tipo de salida (table, view, incremental), el schema de destino, las dependencias y las assertions.
- La función `ref()` es el mecanismo fundamental para referenciar otras tablas/modelos, creando un grafo de dependencias automático.
- Los tipos de modelo son: `table` (tabla materializada), `view` (vista), `incremental` (tabla que se actualiza incrementalmente) y `operations` (SQL arbitrario).

### Detalle técnico

**Ejemplo 1 — Modelo de tipo tabla (silver_empleados):**

```sqlx
-- definitions/silver/silver_empleados.sqlx

config {
    type: "table",
    schema: "pa_silver",
    description: "Tabla de empleados limpia y normalizada. Cada fila es un empleado en un snapshot mensual.",
    tags: ["silver", "empleados", "mensual"],
    bigquery: {
        partitionBy: "fecha_snapshot",
        clusterBy: ["departamento", "nivel", "ciudad"],
        requirePartitionFilter: true,
        partitionExpirationDays: 730,
        labels: {
            dominio: "people_analytics",
            capa: "silver"
        }
    },
    columns: {
        empleado_id: "Identificador único del empleado",
        fecha_snapshot: "Fecha del snapshot mensual (primer día del mes)",
        departamento: "Departamento organizativo normalizado",
        nivel: "Nivel jerárquico: Junior, Mid, Senior, Lead, Manager, Director",
        genero: "Género del empleado: Hombre, Mujer, No binario",
        salario_bruto: "Salario bruto anual en euros",
        rotacion: "TRUE si el empleado causó baja en este snapshot"
    },
    assertions: {
        uniqueKey: ["empleado_id", "fecha_snapshot"],
        nonNull: ["empleado_id", "fecha_snapshot", "departamento", "nivel", "salario_bruto"]
    }
}

SELECT
    TRIM(empleado_id) AS empleado_id,
    fecha_snapshot,
    -- Normalización de departamento
    CASE
        WHEN UPPER(departamento) IN ('TI', 'IT', 'TECNOLOGIA', 'TECH') THEN 'Tecnología'
        WHEN UPPER(departamento) IN ('MKT', 'MARKETING') THEN 'Marketing'
        WHEN UPPER(departamento) IN ('VENTAS', 'SALES', 'COMERCIAL') THEN 'Ventas'
        WHEN UPPER(departamento) IN ('RRHH', 'HR', 'RECURSOS_HUMANOS') THEN 'RRHH'
        WHEN UPPER(departamento) IN ('FINANZAS', 'FINANCE', 'FIN') THEN 'Finanzas'
        WHEN UPPER(departamento) IN ('OPS', 'OPERACIONES', 'OPERATIONS') THEN 'Operaciones'
        WHEN UPPER(departamento) IN ('LEGAL', 'JURIDICO') THEN 'Legal'
        WHEN UPPER(departamento) IN ('DIRECCION', 'EXECUTIVE', 'C-SUITE') THEN 'Dirección'
        ELSE INITCAP(departamento)
    END AS departamento,
    -- Normalización de nivel
    CASE
        WHEN UPPER(nivel) IN ('JR', 'JUNIOR', 'ENTRY') THEN 'Junior'
        WHEN UPPER(nivel) IN ('MID', 'MIDDLE', 'INTERMEDIO') THEN 'Mid'
        WHEN UPPER(nivel) IN ('SR', 'SENIOR') THEN 'Senior'
        WHEN UPPER(nivel) IN ('LEAD', 'TEAM_LEAD', 'TECH_LEAD') THEN 'Lead'
        WHEN UPPER(nivel) IN ('MGR', 'MANAGER', 'RESPONSABLE') THEN 'Manager'
        WHEN UPPER(nivel) IN ('DIR', 'DIRECTOR') THEN 'Director'
        ELSE INITCAP(nivel)
    END AS nivel,
    genero,
    ciudad,
    edad,
    antiguedad_meses,
    salario_bruto,
    jornada,
    rating_desempeno,
    score_clima,
    dias_absentismo,
    horas_formacion,
    meses_sin_promocion,
    rotacion,
    fecha_baja,
    fecha_ingreso,
    estado_laboral
FROM ${ref("stg_empleados")}
WHERE empleado_id IS NOT NULL
    AND fecha_snapshot IS NOT NULL
```

**Ejemplo 2 — Modelo de tipo vista (métricas gold):**

```sqlx
-- definitions/gold/metrics/gold_tasa_rotacion_mensual.sqlx

config {
    type: "view",
    schema: "pa_gold",
    description: "Tasa de rotación mensual por departamento. Incluye rotación voluntaria e involuntaria.",
    tags: ["gold", "metricas", "rotacion"],
    columns: {
        fecha_snapshot: "Mes de reporte",
        departamento: "Departamento organizativo",
        headcount_activo: "Headcount activo al inicio del mes",
        bajas_voluntarias: "Bajas voluntarias en el mes",
        tasa_vol_pct: "Tasa de rotación voluntaria (%)"
    }
}

WITH headcount AS (
    SELECT
        fecha_snapshot,
        departamento,
        COUNT(DISTINCT empleado_id) AS headcount_activo
    FROM ${ref("silver_empleados")}
    WHERE rotacion = FALSE
        AND estado_laboral NOT IN ('BAJA_TEMPORAL', 'EXCEDENCIA')
    GROUP BY fecha_snapshot, departamento
),

bajas AS (
    SELECT
        DATE_TRUNC(fecha_baja, MONTH) AS mes_baja,
        departamento,
        CASE
            WHEN motivo_baja IN ('RENUNCIA', 'MEJOR_OFERTA', 'MOTIVOS_PERSONALES') THEN 'VOLUNTARIA'
            ELSE 'INVOLUNTARIA'
        END AS tipo_rotacion,
        COUNT(DISTINCT empleado_id) AS num_bajas
    FROM ${ref("silver_empleados")}
    WHERE rotacion = TRUE
        AND fecha_baja IS NOT NULL
    GROUP BY 1, 2, 3
)

SELECT
    h.fecha_snapshot,
    h.departamento,
    h.headcount_activo,
    COALESCE(bv.num_bajas, 0) AS bajas_voluntarias,
    COALESCE(bi.num_bajas, 0) AS bajas_involuntarias,
    COALESCE(bv.num_bajas, 0) + COALESCE(bi.num_bajas, 0) AS bajas_totales,
    ROUND(SAFE_DIVIDE(COALESCE(bv.num_bajas, 0), h.headcount_activo) * 100, 2) AS tasa_vol_pct,
    ROUND(SAFE_DIVIDE(
        COALESCE(bv.num_bajas, 0) + COALESCE(bi.num_bajas, 0),
        h.headcount_activo
    ) * 100, 2) AS tasa_total_pct
FROM headcount h
LEFT JOIN bajas bv
    ON h.fecha_snapshot = bv.mes_baja AND h.departamento = bv.departamento AND bv.tipo_rotacion = 'VOLUNTARIA'
LEFT JOIN bajas bi
    ON h.fecha_snapshot = bi.mes_baja AND h.departamento = bi.departamento AND bi.tipo_rotacion = 'INVOLUNTARIA'
```

**Ejemplo 3 — Modelo incremental (historial de eventos):**

```sqlx
-- definitions/silver/silver_eventos_empleado.sqlx

config {
    type: "incremental",
    schema: "pa_silver",
    description: "Registro incremental de eventos de empleado. Solo inserta nuevos eventos.",
    tags: ["silver", "eventos", "incremental"],
    bigquery: {
        partitionBy: "fecha_evento",
        clusterBy: ["empleado_id", "tipo_evento"]
    },
    uniqueKey: ["evento_id"],
    assertions: {
        uniqueKey: ["evento_id"],
        nonNull: ["evento_id", "empleado_id", "tipo_evento", "fecha_evento"]
    }
}

SELECT
    evento_id,
    empleado_id,
    tipo_evento,
    fecha_evento,
    detalle,
    CURRENT_TIMESTAMP() AS fecha_procesamiento
FROM ${ref("stg_eventos")}

${ when(incremental(),
    `WHERE fecha_evento > (SELECT MAX(fecha_evento) FROM ${self()})`) }
```

### Aplicación en People Analytics
- **Declarativo vs. imperativo:** El analista define el "qué" (tabla silver limpia) y Dataform se encarga del "cómo" (CREATE TABLE, INSERT, dependencias).
- **Documentación viva:** Las descripciones de columnas en el bloque `config` se sincronizan automáticamente con BigQuery metadata.
- **Incrementalidad para eventos:** Las tablas de eventos (cambios, movimientos, evaluaciones) crecen continuamente. El tipo `incremental` evita reprocesar todo el histórico cada vez.

---

## Tema 8.4: Gestión de dependencias entre tablas

### Conceptos clave
- La función `ref("nombre_modelo")` en Dataform crea una **dependencia explícita** entre modelos. Dataform construye automáticamente un **grafo dirigido acíclico (DAG)** de dependencias.
- El DAG determina el **orden de ejecución**: los modelos se ejecutan en orden topológico, asegurando que las fuentes estén listas antes que los destinos.
- Las dependencias también pueden declararse explícitamente en el bloque `config` con `dependencies: ["modelo_a", "modelo_b"]`.
- Visualizar el DAG es fundamental para entender el flujo de datos y detectar cuellos de botella.

### Detalle técnico

**Grafo de dependencias del proyecto People Analytics:**

```
                    stg_empleados ──────────────────┐
                         │                           │
                         ▼                           │
                  silver_empleados ────────┐         │
                    │    │    │            │         │
                    │    │    │            ▼         │
                    │    │    │     dim_empleado     │
                    │    │    │            │         │
                    │    │    ▼            │         │
                    │    │  fact_rotacion ─┤         │
                    │    │                 │         │
                    │    ▼                 ▼         │
                    │  fact_headcount   gold_tasa    │
                    │                  _rotacion     │
                    │                  _mensual      │
                    ▼                                │
              gold_brecha_salarial                   │
                                                     │
    stg_evaluaciones ────────────────────────────────┤
         │                                           │
         ▼                                           │
  silver_evaluaciones ───────────────┐               │
         │                           │               │
         ▼                           ▼               │
  fact_evaluaciones            dim_tiempo            │
                                     ▲               │
    stg_nomina ──────────────────────┤               │
         │                           │               │
         ▼                           │               │
    silver_nomina                    │               │
                                     │               │
    stg_movimientos ─────────────────┘               │
         │                                           │
         ▼                                           │
  silver_movimientos ────────────────────────────────┘
```

**Declaración de dependencias en SQLX:**

```sqlx
-- definitions/gold/facts/fact_rotacion.sqlx

config {
    type: "table",
    schema: "pa_gold",
    description: "Tabla de hechos de rotación. Una fila por baja registrada.",
    tags: ["gold", "facts", "rotacion"],
    -- Dependencias implícitas via ref()
    -- Dependencias explícitas adicionales (para modelos no referenciados en SQL)
    dependencies: ["assert_empleados_sin_duplicados"]
}

SELECT
    e.empleado_id,
    e.fecha_baja AS fecha_rotacion,
    e.departamento,
    e.nivel,
    e.genero,
    e.antiguedad_meses AS antiguedad_al_salir,
    e.salario_bruto AS salario_al_salir,
    e.motivo_baja,
    d.departamento_id,
    t.tiempo_id,
    -- Métricas derivadas
    CASE
        WHEN e.motivo_baja IN ('RENUNCIA', 'MEJOR_OFERTA', 'MOTIVOS_PERSONALES') THEN TRUE
        ELSE FALSE
    END AS es_voluntaria,
    e.rating_desempeno AS ultimo_rating,
    e.score_clima AS ultimo_clima
FROM ${ref("silver_empleados")} e
LEFT JOIN ${ref("dim_departamento")} d ON e.departamento = d.nombre_departamento
LEFT JOIN ${ref("dim_tiempo")} t ON e.fecha_baja = t.fecha
WHERE e.rotacion = TRUE
    AND e.fecha_baja IS NOT NULL
```

**Control del orden de ejecución:**

```sqlx
-- Se puede forzar que un modelo espere a otro aunque no lo referencie
config {
    type: "table",
    schema: "pa_gold",
    dependencies: [
        "silver_empleados",        -- Espera a que silver esté listo
        "silver_evaluaciones",     -- Espera a evaluaciones también
        "assert_salarios_rango"    -- Espera a que pase la validación
    ]
}
```

### Aplicación en People Analytics
- **Ejecución ordenada:** Garantiza que `dim_empleado` se actualice antes que `fact_rotacion`, evitando datos inconsistentes.
- **Ejecución selectiva:** Se puede ejecutar solo un subgrafo (e.g., solo los modelos gold) sin reejecutar todo.
- **Debugging visual:** El DAG permite identificar rápidamente por qué una tabla tiene datos incorrectos: basta con seguir las dependencias upstream.
- **Paralelismo automático:** Dataform ejecuta en paralelo los modelos que no tienen dependencias entre sí, reduciendo el tiempo total.

---

## Tema 8.5: Tests automáticos de calidad del dato

### Conceptos clave
- Las **assertions** en Dataform son consultas SQL que validan la calidad de los datos. Si una assertion devuelve filas, indica un fallo de calidad.
- Dataform ofrece assertions integradas en el bloque `config` (uniqueKey, nonNull, rowConditions) y assertions personalizadas como archivos SQLX separados.
- Las assertions se ejecutan después del modelo al que están asociadas, actuando como "tests unitarios" del dato.
- Los resultados de las assertions se almacenan en un schema dedicado (e.g., `pa_dataform_assertions`) para auditoría.

### Detalle técnico

**Assertions integradas en el bloque config:**

```sqlx
-- Dentro de cualquier modelo SQLX:
config {
    type: "table",
    schema: "pa_silver",
    assertions: {
        // Clave primaria compuesta: no puede haber duplicados
        uniqueKey: ["empleado_id", "fecha_snapshot"],
        // Campos que nunca pueden ser nulos
        nonNull: [
            "empleado_id",
            "fecha_snapshot",
            "departamento",
            "nivel",
            "salario_bruto"
        ],
        // Condiciones que cada fila debe cumplir
        rowConditions: [
            "salario_bruto > 0 AND salario_bruto < 1000000",
            "edad >= 18 AND edad <= 70",
            "rating_desempeno BETWEEN 1 AND 5",
            "antiguedad_meses >= 0"
        ]
    }
}
```

**Assertion personalizada — Integridad referencial:**

```sqlx
-- definitions/assertions/assert_integridad_referencial.sqlx

config {
    type: "assertion",
    description: "Verifica que todos los empleados en movimientos existen en silver_empleados",
    tags: ["calidad", "integridad"]
}

-- Esta consulta debe devolver 0 filas para pasar
SELECT DISTINCT
    m.empleado_id
FROM ${ref("silver_movimientos")} m
LEFT JOIN ${ref("silver_empleados")} e
    ON m.empleado_id = e.empleado_id
WHERE e.empleado_id IS NULL
```

**Assertion personalizada — Consistencia temporal:**

```sqlx
-- definitions/assertions/assert_headcount_consistente.sqlx

config {
    type: "assertion",
    description: "Alerta si el headcount varía más del 10% entre meses consecutivos",
    tags: ["calidad", "consistencia"]
}

WITH headcount_mensual AS (
    SELECT
        fecha_snapshot,
        COUNT(DISTINCT empleado_id) AS headcount
    FROM ${ref("silver_empleados")}
    WHERE rotacion = FALSE
    GROUP BY fecha_snapshot
),
variaciones AS (
    SELECT
        fecha_snapshot,
        headcount,
        LAG(headcount) OVER (ORDER BY fecha_snapshot) AS hc_anterior,
        SAFE_DIVIDE(
            ABS(headcount - LAG(headcount) OVER (ORDER BY fecha_snapshot)),
            LAG(headcount) OVER (ORDER BY fecha_snapshot)
        ) AS variacion_pct
    FROM headcount_mensual
)
SELECT
    fecha_snapshot,
    headcount,
    hc_anterior,
    ROUND(variacion_pct * 100, 2) AS variacion_pct
FROM variaciones
WHERE variacion_pct > 0.10
```

**Assertion personalizada — Completitud de departamentos:**

```sqlx
-- definitions/assertions/assert_departamentos_completos.sqlx

config {
    type: "assertion",
    description: "Verifica que todos los departamentos esperados están presentes en cada snapshot",
    tags: ["calidad", "completitud"],
    dependencies: ["silver_empleados"]
}

WITH departamentos_esperados AS (
    SELECT departamento FROM UNNEST([
        'Tecnología', 'Marketing', 'Ventas', 'RRHH',
        'Finanzas', 'Operaciones', 'Legal', 'Dirección'
    ]) AS departamento
),
ultimo_snapshot AS (
    SELECT MAX(fecha_snapshot) AS fecha FROM ${ref("silver_empleados")}
),
departamentos_presentes AS (
    SELECT DISTINCT departamento
    FROM ${ref("silver_empleados")}
    WHERE fecha_snapshot = (SELECT fecha FROM ultimo_snapshot)
        AND rotacion = FALSE
)
SELECT
    de.departamento AS departamento_faltante
FROM departamentos_esperados de
LEFT JOIN departamentos_presentes dp ON de.departamento = dp.departamento
WHERE dp.departamento IS NULL
```

### Aplicación en People Analytics
- **Datos de confianza:** Las métricas de HR (brecha salarial, rotación) llegan a la dirección. Un error no detectado puede tener consecuencias legales o reputacionales.
- **Detección automática:** Las assertions se ejecutan en cada pipeline run. Si fallan, el pipeline se detiene antes de publicar datos incorrectos.
- **Documentación de reglas:** Las assertions codifican las reglas de negocio ("un empleado no puede tener salario negativo") de forma ejecutable y auditable.
- **Cumplimiento regulatorio:** Las auditorías de datos exigen evidencia de controles de calidad. Las assertions en Dataform proporcionan esta evidencia.

---

## Tema 8.6: Documentación integrada de transformaciones

### Conceptos clave
- Dataform permite documentar modelos, columnas y transformaciones **dentro del propio código SQLX**, eliminando la necesidad de documentación externa que se desactualiza.
- La documentación se sincroniza automáticamente con los metadatos de BigQuery, haciéndola visible desde la consola de GCP, Looker, y herramientas de catálogo.
- Los **tags** permiten clasificar modelos por dominio, capa, frecuencia o responsable, facilitando la ejecución selectiva y el filtrado.
- Las **descriptions** de columnas aparecen como tooltips en BigQuery y en herramientas de BI.

### Detalle técnico

**Documentación completa de un modelo:**

```sqlx
-- definitions/gold/dimensions/dim_empleado.sqlx

config {
    type: "table",
    schema: "pa_gold",
    description: `
        Dimensión de empleado para el modelo dimensional de People Analytics.
        Contiene los atributos actuales de cada empleado activo.
        
        Frecuencia de actualización: Mensual (primer lunes del mes)
        Responsable: Equipo de People Analytics
        Fuentes: silver_empleados (última foto)
        
        Notas:
        - Solo incluye empleados activos (rotacion = FALSE)
        - Los campos de SCD2 (valid_from, valid_to) se gestionan en dim_empleado_historico
        - El campo empleado_key es un surrogate key generado por hash
    `,
    tags: ["gold", "dimension", "empleados", "mensual", "critico"],
    columns: {
        empleado_key: "Surrogate key (hash SHA256 de empleado_id + fecha_snapshot)",
        empleado_id: "Identificador natural del empleado en el sistema fuente (SAP/Workday)",
        nombre_completo: "Nombre y apellidos del empleado (anonimizado en entorno de desarrollo)",
        departamento: "Departamento organizativo actual. Valores: Tecnología, Marketing, Ventas, RRHH, Finanzas, Operaciones, Legal, Dirección",
        nivel: "Nivel jerárquico actual. Valores: Junior, Mid, Senior, Lead, Manager, Director",
        genero: "Género del empleado. Valores: Hombre, Mujer, No binario",
        ciudad: "Ciudad de trabajo principal",
        fecha_ingreso: "Fecha de incorporación a la empresa (formato DATE)",
        antiguedad_anos: "Antigüedad calculada en años con 2 decimales",
        rango_antiguedad: "Clasificación de antigüedad: 0-6m, 6-12m, 1-2a, 2-5a, 5-10a, 10+a",
        salario_bruto: "Salario bruto anual en euros",
        jornada: "Tipo de jornada: COMPLETA, PARCIAL_80, PARCIAL_50, PARCIAL_25",
        fte: "Full-Time Equivalent: 1.0, 0.8, 0.5 o 0.25 según jornada",
        es_activo: "TRUE si el empleado está activo en la fecha de snapshot"
    }
}

SELECT
    TO_HEX(SHA256(CONCAT(empleado_id, CAST(fecha_snapshot AS STRING)))) AS empleado_key,
    empleado_id,
    nombre_completo,
    departamento,
    nivel,
    genero,
    ciudad,
    fecha_ingreso,
    ROUND(DATE_DIFF(fecha_snapshot, fecha_ingreso, DAY) / 365.25, 2) AS antiguedad_anos,
    CASE
        WHEN antiguedad_meses < 6 THEN '0-6 meses'
        WHEN antiguedad_meses < 12 THEN '6-12 meses'
        WHEN antiguedad_meses < 24 THEN '1-2 años'
        WHEN antiguedad_meses < 60 THEN '2-5 años'
        WHEN antiguedad_meses < 120 THEN '5-10 años'
        ELSE '10+ años'
    END AS rango_antiguedad,
    salario_bruto,
    jornada,
    CASE
        WHEN jornada = 'COMPLETA' THEN 1.0
        WHEN jornada = 'PARCIAL_80' THEN 0.8
        WHEN jornada = 'PARCIAL_50' THEN 0.5
        WHEN jornada = 'PARCIAL_25' THEN 0.25
        ELSE 1.0
    END AS fte,
    TRUE AS es_activo
FROM ${ref("silver_empleados")}
WHERE fecha_snapshot = (SELECT MAX(fecha_snapshot) FROM ${ref("silver_empleados")})
    AND rotacion = FALSE
    AND estado_laboral NOT IN ('BAJA_TEMPORAL', 'EXCEDENCIA')
```

### Aplicación en People Analytics
- **Self-service analytics:** Los business partners de HR pueden explorar las tablas gold en BigQuery y entender cada campo sin preguntar al equipo de datos.
- **Catálogo de datos:** Las descripciones alimentan automáticamente herramientas de Data Catalog, cumpliendo con los requisitos de gobernanza.
- **Auditoría:** Los auditores pueden verificar las definiciones de negocio directamente en el código versionado.

---

## Tema 8.7: Control de entornos en Dataform

### Conceptos clave
- En un proyecto profesional es necesario separar al menos dos entornos: **desarrollo (dev)** y **producción (prod)**.
- Dataform permite configurar entornos que modifican el schema de destino, el proyecto de GCP o las variables de configuración.
- En desarrollo, las tablas se crean en schemas separados (e.g., `pa_silver_dev`) para no contaminar producción.
- Las variables de entorno (`${dataform.projectConfig.vars}`) permiten parametrizar las consultas según el entorno.

### Detalle técnico

**Configuración de entornos en `dataform.json`:**

```json
{
    "defaultSchema": "pa_dataform",
    "assertionSchema": "pa_dataform_assertions",
    "warehouse": "bigquery",
    "defaultDatabase": "pa-prod",
    "defaultLocation": "EU",
    "vars": {
        "env": "prod",
        "fecha_corte": "2025-04-01",
        "min_headcount_reporte": "5"
    }
}
```

**Uso de variables de entorno en SQLX:**

```sqlx
-- definitions/silver/silver_empleados.sqlx

config {
    type: "table",
    // El schema cambia según el entorno
    schema: dataform.projectConfig.vars.env === "prod" ? "pa_silver" : "pa_silver_dev",
    description: "Tabla silver de empleados"
}

SELECT *
FROM ${ref("stg_empleados")}
WHERE fecha_snapshot <= CAST('${dataform.projectConfig.vars.fecha_corte}' AS DATE)
```

**Override de entorno para desarrollo (línea de comandos):**

```bash
# Ejecutar en modo desarrollo con schema diferente
dataform run \
    --vars='{"env":"dev","fecha_corte":"2025-03-01"}' \
    --default-schema=pa_dataform_dev \
    --default-database=pa-dev

# Ejecutar solo un tag específico
dataform run --tags=silver --tags=empleados

# Ejecutar un modelo específico y sus dependencias
dataform run --include-deps --actions=silver_empleados
```

**Configuración de workflow en la consola de GCP:**

```
Dataform > Repositorio > Workflow Configurations:

Entorno PRODUCCIÓN:
  - Release Config: "prod-release"
  - Schema suffix: "" (sin sufijo)
  - Database: pa-prod
  - Variables: env=prod, fecha_corte=<automática>
  - Schedule: Cada primer lunes del mes a las 06:00 CET

Entorno DESARROLLO:
  - Release Config: "dev-release"  
  - Schema suffix: "_dev"
  - Database: pa-dev
  - Variables: env=dev
  - Schedule: Manual (on-demand)
```

### Aplicación en People Analytics
- **Desarrollo seguro:** Los analistas pueden probar cambios en SQL sin riesgo de modificar las tablas que alimentan los dashboards de producción.
- **Validación pre-deploy:** Antes de mergear a main, se ejecuta el pipeline completo en dev para verificar que todo funciona correctamente.
- **Datos de prueba:** En dev se puede usar un subconjunto de datos (solo 3 meses vs. 2 años) para acelerar las iteraciones.

---

## Tema 8.8: Integración con BigQuery

### Conceptos clave
- Dataform es un servicio nativo de GCP que se ejecuta directamente sobre BigQuery. No hay servidores intermedios: Dataform genera SQL y lo envía a BigQuery para su ejecución.
- La **compilación** convierte los archivos SQLX en SQL puro de BigQuery, resolviendo las funciones `ref()` y las variables.
- La **ejecución** (workflow invocation) envía el SQL compilado a BigQuery en el orden definido por el DAG.
- La programación (scheduling) se configura directamente en la consola de Dataform o mediante Cloud Scheduler.

### Detalle técnico

**Proceso de compilación y ejecución:**

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   SQLX Files     │────>│   Compilación    │────>│   SQL puro BQ    │
│  (ref, config)   │     │  (resolución de  │     │  (CREATE TABLE,  │
│                  │     │   dependencias)  │     │   INSERT, etc.)  │
└──────────────────┘     └──────────────────┘     └────────┬─────────┘
                                                           │
                                                           ▼
                                                  ┌──────────────────┐
                                                  │   BigQuery       │
                                                  │   (ejecución     │
                                                  │    del SQL)      │
                                                  └──────────────────┘
```

**Ejemplo de SQL compilado:**

```sql
-- ANTES (SQLX): ${ref("silver_empleados")}
-- DESPUÉS (SQL compilado): `pa-prod.pa_silver.silver_empleados`

-- El modelo gold_tasa_rotacion_mensual.sqlx se compila a:
CREATE OR REPLACE VIEW `pa-prod.pa_gold.gold_tasa_rotacion_mensual` AS
WITH headcount AS (
    SELECT
        fecha_snapshot,
        departamento,
        COUNT(DISTINCT empleado_id) AS headcount_activo
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE rotacion = FALSE
    GROUP BY fecha_snapshot, departamento
),
-- ... resto del SQL sin ninguna referencia a Dataform
```

**Programación de ejecución:**

```sql
-- Opción 1: Desde la consola de Dataform
-- Dataform > Repository > Workflow Configurations > Schedule
-- Cron: 0 6 1 * *  (primer día de cada mes a las 06:00)

-- Opción 2: Desde Cloud Scheduler + Dataform API
-- POST https://dataform.googleapis.com/v1beta1/projects/{project}/
--   locations/{location}/repositories/{repo}/
--   workflowInvocations
```

**Monitorización de ejecuciones:**

```sql
-- Verificar que la última ejecución fue exitosa
-- En la consola de Dataform > Workflow Invocations
-- O mediante la API:
-- GET /v1beta1/projects/{project}/locations/{location}/
--   repositories/{repo}/workflowInvocations

-- También verificar en BigQuery los metadatos:
SELECT
    table_id,
    TIMESTAMP_MILLIS(last_modified_time) AS ultima_modificacion,
    row_count,
    ROUND(size_bytes / 1024 / 1024, 2) AS size_mb
FROM `pa-prod.pa_silver.__TABLES__`
WHERE table_id LIKE 'silver_%'
ORDER BY last_modified_time DESC;
```

### Aplicación en People Analytics
- **Automatización mensual:** Los reportes de People Analytics se generan automáticamente el primer lunes del mes, sin intervención manual.
- **Monitorización:** Si una ejecución falla (e.g., assertion no pasa), el equipo recibe una alerta y puede investigar antes de que los stakeholders vean datos incorrectos.
- **Coste predecible:** Cada ejecución de Dataform genera consultas en BigQuery con bytes escaneados conocidos, lo que permite estimar el coste mensual.

---

## Tema 8.9: Flujo de despliegue controlado

### Conceptos clave
- En Dataform, el flujo de despliegue sigue el ciclo: **desarrollo local -> commit -> compilación -> revisión -> ejecución en producción**.
- Los **compilation results** son el output de la fase de compilación: el SQL final que se va a ejecutar. Permiten revisar exactamente qué cambios se van a aplicar antes de ejecutarlos.
- Las **workflow invocations** son las ejecuciones reales del pipeline. Cada invocación tiene un estado (RUNNING, SUCCEEDED, FAILED) y un log detallado.
- El flujo de despliegue debe integrarse con el control de versiones (GitHub) para garantizar que solo código revisado llega a producción.

### Detalle técnico

**Flujo de despliegue completo:**

```
┌──────────┐    ┌──────────┐    ┌───────────┐    ┌──────────┐    ┌──────────┐
│  Develop │───>│  Commit  │───>│  Pull     │───>│  Merge   │───>│ Auto     │
│  & Test  │    │  to      │    │  Request  │    │  to      │    │ Deploy   │
│  (dev)   │    │  branch  │    │  + Review │    │  main    │    │ (prod)   │
└──────────┘    └──────────┘    └───────────┘    └──────────┘    └──────────┘
     │                                                                │
     ▼                                                                ▼
  Dataform                                                      Dataform
  run (dev)                                                     run (prod)
  schema:                                                       schema:
  _dev                                                          (sin sufijo)
```

**Compilation result — verificar antes de ejecutar:**

```bash
# Compilar sin ejecutar para revisar el SQL generado
dataform compile

# Salida esperada:
# Compiled successfully.
# Actions:
#   stg_empleados (table) -> pa_bronze.stg_empleados
#   silver_empleados (table) -> pa_silver.silver_empleados
#   dim_empleado (table) -> pa_gold.dim_empleado
#   fact_rotacion (table) -> pa_gold.fact_rotacion
#   gold_tasa_rotacion_mensual (view) -> pa_gold.gold_tasa_rotacion_mensual
#   assert_empleados_sin_duplicados (assertion)
#   assert_salarios_rango_valido (assertion)
# 
# Dependency graph:
#   stg_empleados -> silver_empleados -> dim_empleado
#   stg_empleados -> silver_empleados -> fact_rotacion
#   ...

# Ver el SQL generado para un modelo específico
dataform compile --json | jq '.tables[] | select(.name == "silver_empleados") | .query'
```

**Ejecución con dry-run:**

```bash
# Ejecutar en modo dry-run (no ejecuta, solo muestra qué haría)
dataform run --dry-run

# Ejecutar solo modelos modificados desde la última ejecución
dataform run --changed-since-last-run

# Ejecutar con full refresh (recrea todas las tablas)
dataform run --full-refresh
```

### Aplicación en People Analytics
- **Sin sorpresas:** El equipo puede revisar exactamente qué SQL se va a ejecutar antes de afectar las tablas de producción.
- **Rollback controlado:** Si una ejecución introduce un error, se puede volver al commit anterior en GitHub y reejecutar.
- **Auditoría de cambios:** Cada cambio en la lógica de transformación queda registrado en un commit de Git con autor, fecha y descripción.

---

## Tema 8.10: Buenas prácticas de modularidad y mantenibilidad

### Conceptos clave
- La **modularidad** en Dataform se consigue mediante archivos `includes/` que contienen funciones JavaScript y fragmentos SQL reutilizables.
- Los **macros** permiten generar SQL dinámicamente, evitando duplicación de lógica entre modelos.
- Las **constantes** centralizan valores de referencia (listas de departamentos válidos, umbrales, etc.) en un solo archivo.
- La regla DRY (Don't Repeat Yourself) aplica al SQL analítico igual que al código de software.

### Detalle técnico

**Archivo de constantes (includes/constants.js):**

```javascript
// includes/constants.js

const DEPARTAMENTOS_VALIDOS = [
    'Tecnología', 'Marketing', 'Ventas', 'RRHH',
    'Finanzas', 'Operaciones', 'Legal', 'Dirección'
];

const NIVELES_JERARQUICOS = [
    'Junior', 'Mid', 'Senior', 'Lead', 'Manager', 'Director'
];

const MOTIVOS_BAJA_VOLUNTARIA = [
    'RENUNCIA', 'MEJOR_OFERTA', 'MOTIVOS_PERSONALES',
    'CAMBIO_SECTOR', 'EMPRENDIMIENTO'
];

const MOTIVOS_BAJA_INVOLUNTARIA = [
    'DESPIDO_DISCIPLINARIO', 'ERE', 'FIN_CONTRATO',
    'NO_SUPERA_PRUEBA'
];

const UMBRALES = {
    salario_min: 15000,
    salario_max: 500000,
    edad_min: 18,
    edad_max: 70,
    rating_min: 1,
    rating_max: 5,
    variacion_headcount_max_pct: 10,
    min_grupo_reporte: 5
};

module.exports = {
    DEPARTAMENTOS_VALIDOS,
    NIVELES_JERARQUICOS,
    MOTIVOS_BAJA_VOLUNTARIA,
    MOTIVOS_BAJA_INVOLUNTARIA,
    UMBRALES
};
```

**Archivo de helpers (includes/helpers.js):**

```javascript
// includes/helpers.js

// Macro: Generar CASE WHEN para clasificar tipo de rotación
function tipoRotacion(columna_motivo) {
    return `
    CASE
        WHEN ${columna_motivo} IN ('RENUNCIA', 'MEJOR_OFERTA', 'MOTIVOS_PERSONALES',
                                    'CAMBIO_SECTOR', 'EMPRENDIMIENTO') THEN 'VOLUNTARIA'
        WHEN ${columna_motivo} IN ('DESPIDO_DISCIPLINARIO', 'ERE', 'FIN_CONTRATO',
                                    'NO_SUPERA_PRUEBA') THEN 'INVOLUNTARIA'
        WHEN ${columna_motivo} IN ('JUBILACION', 'FALLECIMIENTO', 'INCAPACIDAD') THEN 'NATURAL'
        ELSE 'SIN_CLASIFICAR'
    END`;
}

// Macro: Calcular FTE según jornada
function calculoFTE(columna_jornada) {
    return `
    CASE
        WHEN ${columna_jornada} = 'COMPLETA' THEN 1.0
        WHEN ${columna_jornada} = 'PARCIAL_80' THEN 0.8
        WHEN ${columna_jornada} = 'PARCIAL_50' THEN 0.5
        WHEN ${columna_jornada} = 'PARCIAL_25' THEN 0.25
        ELSE 1.0
    END`;
}

// Macro: Generar rango de antigüedad
function rangoAntiguedad(columna_meses) {
    return `
    CASE
        WHEN ${columna_meses} < 6 THEN '01. < 6 meses'
        WHEN ${columna_meses} < 12 THEN '02. 6-12 meses'
        WHEN ${columna_meses} < 24 THEN '03. 1-2 años'
        WHEN ${columna_meses} < 60 THEN '04. 2-5 años'
        WHEN ${columna_meses} < 120 THEN '05. 5-10 años'
        ELSE '06. 10+ años'
    END`;
}

// Macro: Generar assertion de rango válido
function assertRango(tabla_ref, columna, min_val, max_val) {
    return `
    SELECT ${columna}
    FROM ${tabla_ref}
    WHERE ${columna} < ${min_val} OR ${columna} > ${max_val}`;
}

module.exports = {
    tipoRotacion,
    calculoFTE,
    rangoAntiguedad,
    assertRango
};
```

**Uso de macros en modelos SQLX:**

```sqlx
-- definitions/gold/facts/fact_rotacion.sqlx

config {
    type: "table",
    schema: "pa_gold"
}

-- Importar helpers
js {
    const { tipoRotacion, calculoFTE } = require("includes/helpers");
}

SELECT
    empleado_id,
    fecha_baja,
    departamento,
    nivel,
    genero,
    salario_bruto,
    -- Usar macro para tipo de rotación (definido una sola vez)
    ${tipoRotacion("motivo_baja")} AS tipo_rotacion,
    -- Usar macro para FTE
    ${calculoFTE("jornada")} AS fte_al_salir,
    antiguedad_meses
FROM ${ref("silver_empleados")}
WHERE rotacion = TRUE
    AND fecha_baja IS NOT NULL
```

### Aplicación en People Analytics
- **Consistencia garantizada:** Si la definición de "rotación voluntaria" cambia, se modifica en un solo lugar (`helpers.js`) y se propaga a todos los modelos automáticamente.
- **Onboarding acelerado:** Un nuevo analista que necesita clasificar rotación no tiene que inventar su propio CASE WHEN: importa el macro y listo.
- **Reducción de errores:** La duplicación de lógica es la principal fuente de inconsistencias en reportes. Los macros eliminan esta duplicación.

---

## Tema 8.11: Modelado dimensional — modelo estrella y snowflake

### Conceptos clave
- El **modelo dimensional** (estrella/snowflake) organiza los datos en **tablas de hechos** (facts) y **tablas de dimensiones** (dims) para optimizar consultas analíticas.
- Las **tablas de hechos** contienen métricas numéricas y claves foráneas a las dimensiones. Ejemplo: `fact_rotacion`, `fact_evaluaciones`, `fact_headcount`.
- Las **tablas de dimensiones** contienen atributos descriptivos. Ejemplo: `dim_empleado`, `dim_departamento`, `dim_tiempo`.
- El **modelo estrella** tiene dimensiones directamente conectadas a los hechos. El **modelo snowflake** normaliza las dimensiones en sub-dimensiones.
- En People Analytics, el modelo estrella es generalmente preferible por su simplicidad y rendimiento en BigQuery.

### Detalle técnico

**Diagrama del modelo dimensional de People Analytics:**

```
                    ┌───────────────────┐
                    │   dim_tiempo      │
                    │───────────────────│
                    │ tiempo_id (PK)    │
                    │ fecha             │
                    │ año               │
                    │ trimestre         │
                    │ mes               │
                    │ semana            │
                    │ dia_semana        │
                    │ es_fin_mes        │
                    │ es_fin_trimestre  │
                    └────────┬──────────┘
                             │
    ┌───────────────────┐    │    ┌───────────────────┐
    │  dim_empleado     │    │    │ dim_departamento   │
    │───────────────────│    │    │───────────────────│
    │ empleado_key (PK) │    │    │ departamento_id(PK)│
    │ empleado_id       │    │    │ nombre             │
    │ nombre_completo   │    │    │ responsable        │
    │ genero            │    │    │ centro_coste       │
    │ ciudad            │    │    │ division           │
    │ fecha_ingreso     │    │    │ num_posiciones     │
    │ nivel             │    │    └──────────┬─────────┘
    │ rango_antiguedad  │    │               │
    │ fte               │    │               │
    └────────┬──────────┘    │               │
             │               │               │
             │    ┌──────────┴───────────────┤
             │    │     fact_rotacion         │
             ├────│──────────────────────────│
             │    │ empleado_key (FK)        │
             │    │ departamento_id (FK)     │
             │    │ tiempo_id (FK)           │
             │    │ es_voluntaria            │
             │    │ antiguedad_al_salir      │
             │    │ salario_al_salir         │
             │    │ ultimo_rating            │
             │    │ ultimo_clima             │
             │    └──────────────────────────┘
             │
             │    ┌──────────────────────────┐
             │    │   fact_evaluaciones       │
             ├────│──────────────────────────│
             │    │ empleado_key (FK)        │
             │    │ departamento_id (FK)     │
             │    │ tiempo_id (FK)           │
             │    │ rating                   │
             │    │ score_clima              │
             │    │ horas_formacion          │
             │    │ dias_absentismo          │
             │    └──────────────────────────┘
             │
             │    ┌──────────────────────────┐
             │    │   fact_headcount          │
             └────│──────────────────────────│
                  │ empleado_key (FK)        │
                  │ departamento_id (FK)     │
                  │ tiempo_id (FK)           │
                  │ headcount                │
                  │ fte                      │
                  │ salario_bruto            │
                  │ es_nuevo_ingreso         │
                  │ es_baja                  │
                  └──────────────────────────┘
```

**Implementación de dim_departamento en Dataform:**

```sqlx
-- definitions/gold/dimensions/dim_departamento.sqlx

config {
    type: "table",
    schema: "pa_gold",
    description: "Dimensión de departamento. Incluye jerarquía organizativa y metadatos.",
    tags: ["gold", "dimension", "departamento"],
    columns: {
        departamento_id: "Surrogate key numérico auto-generado",
        nombre_departamento: "Nombre normalizado del departamento",
        responsable: "Nombre del director del departamento",
        centro_coste: "Código del centro de coste asociado",
        division: "División organizativa superior",
        num_posiciones_aprobadas: "Número de posiciones aprobadas en presupuesto"
    },
    assertions: {
        uniqueKey: ["departamento_id"],
        nonNull: ["departamento_id", "nombre_departamento"]
    }
}

SELECT
    ROW_NUMBER() OVER (ORDER BY nombre_departamento) AS departamento_id,
    nombre_departamento,
    responsable,
    centro_coste,
    division,
    num_posiciones_aprobadas
FROM (
    SELECT DISTINCT
        departamento AS nombre_departamento,
        FIRST_VALUE(responsable_depto) OVER (
            PARTITION BY departamento ORDER BY fecha_snapshot DESC
        ) AS responsable,
        FIRST_VALUE(centro_coste) OVER (
            PARTITION BY departamento ORDER BY fecha_snapshot DESC
        ) AS centro_coste,
        FIRST_VALUE(division) OVER (
            PARTITION BY departamento ORDER BY fecha_snapshot DESC
        ) AS division,
        FIRST_VALUE(posiciones_aprobadas) OVER (
            PARTITION BY departamento ORDER BY fecha_snapshot DESC
        ) AS num_posiciones_aprobadas
    FROM ${ref("silver_empleados")}
    WHERE fecha_snapshot = (SELECT MAX(fecha_snapshot) FROM ${ref("silver_empleados")})
)
```

**Implementación de dim_tiempo:**

```sqlx
-- definitions/gold/dimensions/dim_tiempo.sqlx

config {
    type: "table",
    schema: "pa_gold",
    description: "Dimensión de tiempo. Cubre el rango completo de fechas del proyecto.",
    tags: ["gold", "dimension", "tiempo"],
    assertions: {
        uniqueKey: ["tiempo_id"],
        nonNull: ["tiempo_id", "fecha"]
    }
}

-- Generar todas las fechas desde 2020-01-01 hasta 2026-12-31
SELECT
    ROW_NUMBER() OVER (ORDER BY fecha) AS tiempo_id,
    fecha,
    EXTRACT(YEAR FROM fecha) AS anio,
    EXTRACT(QUARTER FROM fecha) AS trimestre,
    EXTRACT(MONTH FROM fecha) AS mes,
    FORMAT_DATE('%B', fecha) AS nombre_mes,
    FORMAT_DATE('%Y-Q%Q', fecha) AS anio_trimestre,
    FORMAT_DATE('%Y-%m', fecha) AS anio_mes,
    EXTRACT(ISOWEEK FROM fecha) AS semana_iso,
    EXTRACT(DAYOFWEEK FROM fecha) AS dia_semana,
    FORMAT_DATE('%A', fecha) AS nombre_dia,
    CASE WHEN fecha = LAST_DAY(fecha, MONTH) THEN TRUE ELSE FALSE END AS es_fin_mes,
    CASE WHEN fecha = LAST_DAY(fecha, QUARTER) THEN TRUE ELSE FALSE END AS es_fin_trimestre,
    CASE WHEN fecha = LAST_DAY(fecha, YEAR) THEN TRUE ELSE FALSE END AS es_fin_anio,
    CASE WHEN EXTRACT(DAYOFWEEK FROM fecha) IN (1, 7) THEN TRUE ELSE FALSE END AS es_fin_semana
FROM UNNEST(
    GENERATE_DATE_ARRAY('2020-01-01', '2026-12-31', INTERVAL 1 DAY)
) AS fecha
```

### Aplicación en People Analytics
- **Rendimiento en BI:** Looker y Data Studio funcionan de forma óptima sobre modelos dimensionales. Los JOINs estrella son los más eficientes para consultas ad-hoc.
- **Análisis multidimensional:** Los usuarios de negocio pueden "cortar" las métricas por cualquier combinación de dimensiones (departamento + género + antigüedad) sin consultas complejas.
- **Consistencia de agregaciones:** Las tablas de hechos garantizan que todos los reportes usen las mismas métricas base.

---

## Tema 8.12: Implementación de Slowly Changing Dimensions SCD2

### Conceptos clave
- Las **Slowly Changing Dimensions (SCD)** gestionan cómo se almacenan los cambios históricos en las dimensiones. El tipo más común es **SCD2**.
- **SCD1** sobrescribe el valor anterior (pierde historia). **SCD2** añade una nueva fila con validez temporal (conserva historia completa).
- En SCD2, cada registro tiene `valid_from`, `valid_to` e `is_current`. El registro activo tiene `is_current = TRUE` y `valid_to = '9999-12-31'`.
- La implementación en BigQuery/Dataform usa sentencias `MERGE` para detectar cambios e insertar nuevas versiones.

### Detalle técnico

**Estructura de una dimensión SCD2:**

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `empleado_key` | STRING | Surrogate key (hash de empleado_id + valid_from) |
| `empleado_id` | STRING | Clave natural (del sistema fuente) |
| `nombre_completo` | STRING | Nombre actual |
| `departamento` | STRING | Departamento en esta versión |
| `nivel` | STRING | Nivel en esta versión |
| `salario_bruto` | INT64 | Salario en esta versión |
| `valid_from` | DATE | Fecha de inicio de validez |
| `valid_to` | DATE | Fecha de fin de validez ('9999-12-31' si es actual) |
| `is_current` | BOOL | TRUE si es la versión vigente |

**Implementación SCD2 en Dataform con MERGE:**

```sqlx
-- definitions/gold/dimensions/dim_empleado_historico.sqlx

config {
    type: "operations",
    schema: "pa_gold",
    description: "Dimensión de empleado con SCD2. Mantiene historial completo de cambios.",
    tags: ["gold", "dimension", "scd2", "empleados"],
    hasOutput: true
}

-- Paso 1: Crear la tabla si no existe
CREATE TABLE IF NOT EXISTS `pa-prod.pa_gold.dim_empleado_historico` (
    empleado_key STRING NOT NULL,
    empleado_id STRING NOT NULL,
    nombre_completo STRING,
    departamento STRING,
    nivel STRING,
    genero STRING,
    ciudad STRING,
    salario_bruto INT64,
    jornada STRING,
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL DEFAULT '9999-12-31',
    is_current BOOL NOT NULL DEFAULT TRUE
);

---

-- Paso 2: Cerrar registros que han cambiado
MERGE `pa-prod.pa_gold.dim_empleado_historico` AS target
USING (
    -- Fuente: empleados del último snapshot
    SELECT
        empleado_id,
        nombre_completo,
        departamento,
        nivel,
        genero,
        ciudad,
        salario_bruto,
        jornada,
        fecha_snapshot
    FROM ${ref("silver_empleados")}
    WHERE fecha_snapshot = (SELECT MAX(fecha_snapshot) FROM ${ref("silver_empleados")})
        AND rotacion = FALSE
) AS source
ON target.empleado_id = source.empleado_id AND target.is_current = TRUE

-- Caso 1: Empleado existe y ha cambiado algún atributo -> cerrar versión anterior
WHEN MATCHED AND (
    target.departamento != source.departamento
    OR target.nivel != source.nivel
    OR target.salario_bruto != source.salario_bruto
    OR target.ciudad != source.ciudad
    OR target.jornada != source.jornada
)
THEN UPDATE SET
    valid_to = DATE_SUB(source.fecha_snapshot, INTERVAL 1 DAY),
    is_current = FALSE

-- Caso 2: Empleado no existe en la dimensión -> insertar como nuevo
WHEN NOT MATCHED BY TARGET
THEN INSERT (
    empleado_key, empleado_id, nombre_completo, departamento, nivel,
    genero, ciudad, salario_bruto, jornada, valid_from, valid_to, is_current
)
VALUES (
    TO_HEX(SHA256(CONCAT(source.empleado_id, CAST(source.fecha_snapshot AS STRING)))),
    source.empleado_id, source.nombre_completo, source.departamento, source.nivel,
    source.genero, source.ciudad, source.salario_bruto, source.jornada,
    source.fecha_snapshot, DATE '9999-12-31', TRUE
);

---

-- Paso 3: Insertar nuevas versiones para los registros que se cerraron
INSERT INTO `pa-prod.pa_gold.dim_empleado_historico` (
    empleado_key, empleado_id, nombre_completo, departamento, nivel,
    genero, ciudad, salario_bruto, jornada, valid_from, valid_to, is_current
)
SELECT
    TO_HEX(SHA256(CONCAT(s.empleado_id, CAST(s.fecha_snapshot AS STRING)))),
    s.empleado_id, s.nombre_completo, s.departamento, s.nivel,
    s.genero, s.ciudad, s.salario_bruto, s.jornada,
    s.fecha_snapshot, DATE '9999-12-31', TRUE
FROM ${ref("silver_empleados")} s
INNER JOIN `pa-prod.pa_gold.dim_empleado_historico` h
    ON s.empleado_id = h.empleado_id
    AND h.is_current = FALSE
    AND h.valid_to = DATE_SUB(s.fecha_snapshot, INTERVAL 1 DAY)
WHERE s.fecha_snapshot = (SELECT MAX(fecha_snapshot) FROM ${ref("silver_empleados")})
    AND s.rotacion = FALSE
    AND NOT EXISTS (
        SELECT 1 FROM `pa-prod.pa_gold.dim_empleado_historico` h2
        WHERE h2.empleado_id = s.empleado_id AND h2.is_current = TRUE
    );
```

**Consultar la dimensión SCD2:**

```sql
-- Estado actual de un empleado
SELECT *
FROM `pa-prod.pa_gold.dim_empleado_historico`
WHERE empleado_id = 'EMP-001'
    AND is_current = TRUE;

-- Historial completo de un empleado
SELECT *
FROM `pa-prod.pa_gold.dim_empleado_historico`
WHERE empleado_id = 'EMP-001'
ORDER BY valid_from;

-- Estado de un empleado en una fecha específica (point-in-time)
SELECT *
FROM `pa-prod.pa_gold.dim_empleado_historico`
WHERE empleado_id = 'EMP-001'
    AND valid_from <= '2024-06-15'
    AND valid_to >= '2024-06-15';
```

### Aplicación en People Analytics
- **Análisis histórico preciso:** Saber en qué departamento estaba un empleado hace 6 meses es fundamental para análisis de rotación retroactivo.
- **Auditoría salarial:** SCD2 permite reconstruir el historial salarial completo de cada empleado, necesario para auditorías de igualdad.
- **Reporting regulatorio:** Los informes de igualdad exigen datos "as of" una fecha determinada. SCD2 permite reconstruir cualquier punto en el tiempo.
- **Trazabilidad:** Cada cambio queda registrado con fecha exacta, lo que permite detectar patrones (e.g., empleados que cambian de departamento antes de irse).

---

## Tema 8.13: Gestión de la evolución histórica del dato de empleado

### Conceptos clave
- En People Analytics, los datos de empleado evolucionan continuamente: cambios de departamento, promociones, ajustes salariales, cambios de jornada.
- La **gestión de la evolución** requiere decidir cómo almacenar y consultar estos cambios de forma eficiente.
- Existen dos enfoques principales: **snapshots periódicos** (una foto completa por periodo) y **event sourcing** (solo los cambios).
- El enfoque híbrido (snapshots + SCD2) es el más práctico para People Analytics: snapshots en silver para análisis rápido, SCD2 en gold para precisión histórica.

### Detalle técnico

**Enfoque 1: Snapshots mensuales (silver):**

```sqlx
-- definitions/silver/silver_empleados.sqlx
-- Cada mes se carga una foto completa de todos los empleados

config {
    type: "incremental",
    schema: "pa_silver",
    uniqueKey: ["empleado_id", "fecha_snapshot"],
    bigquery: {
        partitionBy: "fecha_snapshot",
        clusterBy: ["departamento", "nivel"]
    }
}

SELECT
    empleado_id,
    CAST('${dataform.projectConfig.vars.fecha_corte}' AS DATE) AS fecha_snapshot,
    departamento,
    nivel,
    genero,
    ciudad,
    salario_bruto,
    jornada,
    antiguedad_meses,
    rating_desempeno,
    score_clima,
    dias_absentismo,
    horas_formacion,
    meses_sin_promocion,
    rotacion,
    fecha_baja,
    fecha_ingreso,
    estado_laboral
FROM ${ref("stg_empleados")}

${ when(incremental(),
    `WHERE fecha_snapshot > (SELECT MAX(fecha_snapshot) FROM ${self()})`) }
```

**Enfoque 2: Event sourcing (registro de cambios):**

```sqlx
-- definitions/silver/silver_cambios_empleado.sqlx
-- Detectar cambios comparando snapshots consecutivos

config {
    type: "table",
    schema: "pa_silver",
    description: "Registro de cambios detectados entre snapshots consecutivos"
}

WITH snapshots_consecutivos AS (
    SELECT
        empleado_id,
        fecha_snapshot,
        departamento,
        nivel,
        salario_bruto,
        jornada,
        ciudad,
        LAG(fecha_snapshot) OVER w AS fecha_anterior,
        LAG(departamento) OVER w AS depto_anterior,
        LAG(nivel) OVER w AS nivel_anterior,
        LAG(salario_bruto) OVER w AS salario_anterior,
        LAG(jornada) OVER w AS jornada_anterior,
        LAG(ciudad) OVER w AS ciudad_anterior
    FROM ${ref("silver_empleados")}
    WINDOW w AS (PARTITION BY empleado_id ORDER BY fecha_snapshot)
)

SELECT
    empleado_id,
    fecha_snapshot AS fecha_cambio,
    -- Detectar qué cambió
    CASE WHEN departamento != depto_anterior THEN 'CAMBIO_DEPARTAMENTO' END AS cambio_depto,
    depto_anterior AS depto_de,
    departamento AS depto_a,
    CASE WHEN nivel != nivel_anterior THEN 'CAMBIO_NIVEL' END AS cambio_nivel,
    nivel_anterior AS nivel_de,
    nivel AS nivel_a,
    CASE WHEN salario_bruto != salario_anterior THEN 'CAMBIO_SALARIO' END AS cambio_salario,
    salario_anterior AS salario_de,
    salario_bruto AS salario_a,
    ROUND(SAFE_DIVIDE(salario_bruto - salario_anterior, salario_anterior) * 100, 2) AS variacion_salario_pct,
    CASE WHEN jornada != jornada_anterior THEN 'CAMBIO_JORNADA' END AS cambio_jornada,
    CASE WHEN ciudad != ciudad_anterior THEN 'CAMBIO_CIUDAD' END AS cambio_ciudad
FROM snapshots_consecutivos
WHERE fecha_anterior IS NOT NULL
    AND (
        departamento != depto_anterior
        OR nivel != nivel_anterior
        OR salario_bruto != salario_anterior
        OR jornada != jornada_anterior
        OR ciudad != ciudad_anterior
    )
```

**Enfoque 3: Tabla resumen de trayectoria:**

```sqlx
-- definitions/gold/metrics/gold_trayectoria_empleado.sqlx

config {
    type: "table",
    schema: "pa_gold",
    description: "Resumen de trayectoria de cada empleado: movimientos, promociones, cambios salariales"
}

SELECT
    c.empleado_id,
    e.nombre_completo,
    e.departamento AS departamento_actual,
    e.nivel AS nivel_actual,
    e.fecha_ingreso,
    -- Resumen de movimientos
    COUNTIF(c.cambio_depto IS NOT NULL) AS num_cambios_departamento,
    COUNTIF(c.cambio_nivel IS NOT NULL) AS num_cambios_nivel,
    COUNTIF(c.cambio_salario IS NOT NULL) AS num_ajustes_salariales,
    -- Primer y último cambio
    MIN(CASE WHEN c.cambio_nivel IS NOT NULL THEN c.fecha_cambio END) AS fecha_primera_promocion,
    MAX(CASE WHEN c.cambio_nivel IS NOT NULL THEN c.fecha_cambio END) AS fecha_ultima_promocion,
    -- Evolución salarial
    MIN(c.salario_de) AS primer_salario_conocido,
    MAX(c.salario_a) AS ultimo_salario_conocido,
    -- Lista de departamentos por los que ha pasado
    ARRAY_AGG(DISTINCT c.depto_a IGNORE NULLS ORDER BY c.depto_a) AS departamentos_historicos,
    -- Lista de niveles por los que ha pasado
    ARRAY_AGG(DISTINCT c.nivel_a IGNORE NULLS ORDER BY c.nivel_a) AS niveles_historicos
FROM ${ref("silver_cambios_empleado")} c
LEFT JOIN ${ref("dim_empleado")} e ON c.empleado_id = e.empleado_id
GROUP BY c.empleado_id, e.nombre_completo, e.departamento, e.nivel, e.fecha_ingreso
```

### Aplicación en People Analytics
- **Career pathing:** Reconstruir la trayectoria de empleados exitosos permite definir career paths y mentoring programs.
- **Análisis de movilidad interna:** Saber cuántos empleados cambian de departamento, con qué frecuencia y en qué dirección revela la dinámica organizativa.
- **Equidad longitudinal:** No basta con comparar salarios actuales; hay que analizar la evolución salarial desde el ingreso para detectar brechas acumuladas.
- **Planificación de sucesiones:** Identificar empleados con trayectorias diversas (múltiples departamentos, promociones rápidas) como candidatos a posiciones de liderazgo.

---

## Resumen del módulo

| Tema | Concepto clave | Herramienta Dataform |
|------|---------------|---------------------|
| 8.1 | ELT en GCP | BigQuery como motor de transformación |
| 8.2 | Estructura de repositorio | `definitions/`, `includes/`, configs |
| 8.3 | Modelos declarativos | SQLX, `config {}`, `ref()` |
| 8.4 | Gestión de dependencias | DAG automático, ejecución ordenada |
| 8.5 | Tests de calidad | Assertions: uniqueKey, nonNull, custom |
| 8.6 | Documentación integrada | Descripciones de columnas, tags |
| 8.7 | Control de entornos | dev vs prod, variables, schema suffix |
| 8.8 | Integración BigQuery | Compilación, ejecución, scheduling |
| 8.9 | Flujo de despliegue | Compile, dry-run, workflow invocations |
| 8.10 | Modularidad | `includes/`, macros JS, constantes |
| 8.11 | Modelo dimensional | Estrella, facts y dims |
| 8.12 | SCD2 | MERGE, valid_from/to, is_current |
| 8.13 | Evolución histórica | Snapshots, event sourcing, trayectorias |

---

## Preparación para el siguiente módulo

En el **Módulo 9: Integración Real con GitHub**, aprenderemos a versionar todo el código de Dataform en un repositorio Git profesional, con flujos de ramas, pull requests y CI/CD automatizado. El repositorio que hemos diseñado en este módulo se convertirá en un proyecto GitHub completo.
