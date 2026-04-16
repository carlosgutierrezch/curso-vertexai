# Módulo 7: SQL Avanzado Aplicado a People Analytics

## Información de la sesión
- **Sesión:** 6
- **Fecha:** Lunes 18 de Mayo, 16:00–18:00
- **Duración:** 2 horas (sesión completa)
- **Prerequisitos:** Módulos 1–6 completados, dominio de SQL básico en BigQuery

---

## Tema 7.1: Window functions aplicadas a rotación y cohortes

### Conceptos clave
- Las **window functions** (funciones de ventana) permiten realizar cálculos sobre un conjunto de filas relacionadas con la fila actual, sin agrupar ni colapsar resultados.
- En People Analytics, son esenciales para analizar **tendencias temporales**, **rankings**, **comparaciones entre periodos** y **acumulados** sin perder el detalle individual de cada empleado.
- BigQuery soporta la sintaxis estándar SQL:2003 para window functions con extensiones propias.
- Las funciones principales se agrupan en tres categorías:
  - **Ranking:** `ROW_NUMBER()`, `RANK()`, `DENSE_RANK()`, `NTILE()`
  - **Navegación:** `LAG()`, `LEAD()`, `FIRST_VALUE()`, `LAST_VALUE()`
  - **Agregación:** `SUM()`, `AVG()`, `COUNT()`, `MIN()`, `MAX()` con cláusula `OVER()`

### Detalle técnico

**Estructura general de una window function:**

```sql
funcion_ventana() OVER (
    PARTITION BY columna_particion
    ORDER BY columna_orden
    ROWS BETWEEN inicio AND fin
)
```

**Ejemplo 1 — Ranking de empleados por antigüedad dentro de cada departamento:**

```sql
SELECT
    empleado_id,
    departamento,
    nivel,
    antiguedad_meses,
    ROW_NUMBER() OVER (
        PARTITION BY departamento
        ORDER BY antiguedad_meses DESC
    ) AS ranking_antiguedad,
    RANK() OVER (
        PARTITION BY departamento
        ORDER BY antiguedad_meses DESC
    ) AS ranking_con_empates,
    DENSE_RANK() OVER (
        PARTITION BY departamento
        ORDER BY antiguedad_meses DESC
    ) AS ranking_denso
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01'
    AND rotacion = FALSE
ORDER BY departamento, ranking_antiguedad;
```

**Ejemplo 2 — Variación mensual de headcount con LAG y LEAD:**

```sql
WITH headcount_mensual AS (
    SELECT
        fecha_snapshot,
        departamento,
        COUNT(DISTINCT empleado_id) AS headcount
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot BETWEEN '2024-01-01' AND '2025-03-01'
        AND rotacion = FALSE
    GROUP BY fecha_snapshot, departamento
)
SELECT
    fecha_snapshot,
    departamento,
    headcount,
    LAG(headcount, 1) OVER (
        PARTITION BY departamento ORDER BY fecha_snapshot
    ) AS headcount_mes_anterior,
    LEAD(headcount, 1) OVER (
        PARTITION BY departamento ORDER BY fecha_snapshot
    ) AS headcount_mes_siguiente,
    headcount - LAG(headcount, 1) OVER (
        PARTITION BY departamento ORDER BY fecha_snapshot
    ) AS variacion_absoluta,
    SAFE_DIVIDE(
        headcount - LAG(headcount, 1) OVER (
            PARTITION BY departamento ORDER BY fecha_snapshot
        ),
        LAG(headcount, 1) OVER (
            PARTITION BY departamento ORDER BY fecha_snapshot
        )
    ) * 100 AS variacion_porcentual
FROM headcount_mensual
ORDER BY departamento, fecha_snapshot;
```

**Ejemplo 3 — Running total (acumulado) de bajas por departamento:**

```sql
SELECT
    fecha_snapshot,
    departamento,
    COUNT(DISTINCT CASE WHEN rotacion = TRUE THEN empleado_id END) AS bajas_mes,
    SUM(COUNT(DISTINCT CASE WHEN rotacion = TRUE THEN empleado_id END)) OVER (
        PARTITION BY departamento
        ORDER BY fecha_snapshot
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS bajas_acumuladas,
    AVG(COUNT(DISTINCT CASE WHEN rotacion = TRUE THEN empleado_id END)) OVER (
        PARTITION BY departamento
        ORDER BY fecha_snapshot
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS media_movil_3_meses
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot BETWEEN '2024-01-01' AND '2025-03-01'
GROUP BY fecha_snapshot, departamento
ORDER BY departamento, fecha_snapshot;
```

**Ejemplo 4 — Análisis de cohortes de ingreso con NTILE:**

```sql
WITH empleados_activos AS (
    SELECT
        empleado_id,
        departamento,
        antiguedad_meses,
        salario_bruto,
        NTILE(4) OVER (ORDER BY antiguedad_meses) AS cuartil_antiguedad
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot = '2025-04-01'
        AND rotacion = FALSE
)
SELECT
    cuartil_antiguedad,
    MIN(antiguedad_meses) AS min_antiguedad,
    MAX(antiguedad_meses) AS max_antiguedad,
    COUNT(*) AS num_empleados,
    ROUND(AVG(salario_bruto), 0) AS salario_medio
FROM empleados_activos
GROUP BY cuartil_antiguedad
ORDER BY cuartil_antiguedad;
```

### Aplicación en People Analytics
- **Cohortes de ingreso:** Agrupar empleados por trimestre/año de entrada y seguir su evolución (retención, promociones, salario).
- **Análisis de rotación temporal:** Running totals y medias móviles permiten detectar tendencias de salida que un simple COUNT mensual no revela.
- **Benchmarking interno:** Rankings por departamento facilitan identificar equipos con alta/baja antigüedad, lo que puede correlacionar con riesgo de fuga.
- **Alertas de variación:** Las funciones LAG/LEAD detectan cambios bruscos mes a mes que requieren investigación inmediata.

---

## Tema 7.2: Cálculo de métricas temporales complejas

### Conceptos clave
- En People Analytics, las **métricas temporales** son el eje central del análisis: antigüedad, tiempo entre eventos, tiempo de supervivencia, tiempo hasta la promoción, etc.
- BigQuery ofrece funciones nativas para aritmética de fechas: `DATE_DIFF()`, `TIMESTAMP_DIFF()`, `DATE_ADD()`, `DATE_SUB()`, `EXTRACT()`.
- El cálculo correcto de estas métricas requiere definir claramente las **fechas de referencia** (fecha de corte, fecha de evento, fecha de ingreso).
- El concepto de **survival time** (tiempo de supervivencia) es fundamental para análisis de retención: mide el tiempo desde el ingreso hasta la baja (o hasta la fecha de censura si sigue activo).

### Detalle técnico

**Ejemplo 1 — Cálculo preciso de antigüedad (tenure):**

```sql
SELECT
    empleado_id,
    fecha_ingreso,
    fecha_baja,
    fecha_snapshot,
    -- Antigüedad en meses completos
    DATE_DIFF(
        COALESCE(fecha_baja, fecha_snapshot),
        fecha_ingreso,
        MONTH
    ) AS antiguedad_meses,
    -- Antigüedad en días (más precisa)
    DATE_DIFF(
        COALESCE(fecha_baja, fecha_snapshot),
        fecha_ingreso,
        DAY
    ) AS antiguedad_dias,
    -- Antigüedad en años con decimales
    ROUND(
        DATE_DIFF(
            COALESCE(fecha_baja, fecha_snapshot),
            fecha_ingreso,
            DAY
        ) / 365.25, 2
    ) AS antiguedad_anos,
    -- Clasificación por rango de antigüedad
    CASE
        WHEN DATE_DIFF(COALESCE(fecha_baja, fecha_snapshot), fecha_ingreso, MONTH) < 6 THEN '0-6 meses'
        WHEN DATE_DIFF(COALESCE(fecha_baja, fecha_snapshot), fecha_ingreso, MONTH) < 12 THEN '6-12 meses'
        WHEN DATE_DIFF(COALESCE(fecha_baja, fecha_snapshot), fecha_ingreso, MONTH) < 24 THEN '1-2 años'
        WHEN DATE_DIFF(COALESCE(fecha_baja, fecha_snapshot), fecha_ingreso, MONTH) < 60 THEN '2-5 años'
        ELSE '5+ años'
    END AS rango_antiguedad
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01';
```

**Ejemplo 2 — Tiempo entre eventos (time-between-events):**

```sql
-- Tiempo entre cambios de puesto para cada empleado
WITH cambios_puesto AS (
    SELECT
        empleado_id,
        fecha_cambio,
        puesto_anterior,
        puesto_nuevo,
        LAG(fecha_cambio) OVER (
            PARTITION BY empleado_id ORDER BY fecha_cambio
        ) AS fecha_cambio_anterior
    FROM `pa-prod.pa_silver.silver_movimientos`
    WHERE tipo_movimiento = 'CAMBIO_PUESTO'
)
SELECT
    empleado_id,
    fecha_cambio,
    puesto_anterior,
    puesto_nuevo,
    fecha_cambio_anterior,
    DATE_DIFF(fecha_cambio, fecha_cambio_anterior, MONTH) AS meses_entre_cambios,
    -- Clasificar velocidad de movimiento
    CASE
        WHEN DATE_DIFF(fecha_cambio, fecha_cambio_anterior, MONTH) < 12 THEN 'Rápido (<1 año)'
        WHEN DATE_DIFF(fecha_cambio, fecha_cambio_anterior, MONTH) < 24 THEN 'Normal (1-2 años)'
        ELSE 'Lento (>2 años)'
    END AS velocidad_movimiento
FROM cambios_puesto
WHERE fecha_cambio_anterior IS NOT NULL
ORDER BY empleado_id, fecha_cambio;
```

**Ejemplo 3 — Survival time (tiempo de supervivencia) para análisis de retención:**

```sql
WITH empleados_cohorte AS (
    SELECT
        empleado_id,
        fecha_ingreso,
        fecha_baja,
        -- Survival time: desde ingreso hasta baja o censura
        DATE_DIFF(
            COALESCE(fecha_baja, CURRENT_DATE()),
            fecha_ingreso,
            MONTH
        ) AS survival_months,
        -- Indicador de evento (censura vs. baja observada)
        CASE
            WHEN fecha_baja IS NOT NULL THEN 1
            ELSE 0
        END AS evento_baja,
        -- Cohorte trimestral de ingreso
        FORMAT_DATE('%Y-Q%Q', fecha_ingreso) AS cohorte_ingreso
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot = '2025-04-01'
)
SELECT
    cohorte_ingreso,
    COUNT(*) AS total_cohorte,
    SUM(evento_baja) AS total_bajas,
    ROUND(AVG(survival_months), 1) AS media_survival_meses,
    ROUND(
        APPROX_QUANTILES(survival_months, 2)[OFFSET(1)], 1
    ) AS mediana_survival_meses,
    -- Tasa de supervivencia a 12 meses
    ROUND(
        SAFE_DIVIDE(
            COUNTIF(survival_months >= 12 OR (survival_months < 12 AND evento_baja = 0)),
            COUNT(*)
        ) * 100, 1
    ) AS tasa_supervivencia_12m
FROM empleados_cohorte
GROUP BY cohorte_ingreso
ORDER BY cohorte_ingreso;
```

**Ejemplo 4 — Tiempo hasta primera promoción:**

```sql
WITH primera_promocion AS (
    SELECT
        e.empleado_id,
        e.fecha_ingreso,
        MIN(m.fecha_cambio) AS fecha_primera_promocion
    FROM `pa-prod.pa_silver.silver_empleados` e
    LEFT JOIN `pa-prod.pa_silver.silver_movimientos` m
        ON e.empleado_id = m.empleado_id
        AND m.tipo_movimiento = 'PROMOCION'
    WHERE e.fecha_snapshot = '2025-04-01'
    GROUP BY e.empleado_id, e.fecha_ingreso
)
SELECT
    empleado_id,
    fecha_ingreso,
    fecha_primera_promocion,
    DATE_DIFF(fecha_primera_promocion, fecha_ingreso, MONTH) AS meses_hasta_promocion,
    CASE
        WHEN fecha_primera_promocion IS NULL THEN 'Sin promoción'
        WHEN DATE_DIFF(fecha_primera_promocion, fecha_ingreso, MONTH) < 18 THEN 'Rápida (<18m)'
        WHEN DATE_DIFF(fecha_primera_promocion, fecha_ingreso, MONTH) < 36 THEN 'Normal (18-36m)'
        ELSE 'Tardía (>36m)'
    END AS velocidad_promocion
FROM primera_promocion
ORDER BY meses_hasta_promocion NULLS LAST;
```

### Aplicación en People Analytics
- **Retención por cohorte:** El survival time permite comparar cohortes de ingreso y detectar si las contrataciones recientes se retienen peor.
- **Velocidad de desarrollo:** Medir el tiempo hasta la primera promoción por género, departamento o nivel de ingreso revela sesgos en el desarrollo profesional.
- **Planificación de sucesiones:** El tiempo entre movimientos laterales indica la agilidad organizacional.
- **Early warning:** Empleados que superan la mediana de tiempo sin promoción son candidatos a riesgo de fuga.

---

## Tema 7.3: Subqueries y CTEs estructurados profesionalmente

### Conceptos clave
- Las **Common Table Expressions (CTEs)** y las subqueries son herramientas fundamentales para organizar consultas complejas en pasos lógicos legibles.
- En equipos de datos, la **legibilidad** del SQL es tan importante como su rendimiento: las consultas se revisan en pull requests y se mantienen durante meses o años.
- BigQuery ejecuta los CTEs como subqueries inline (no los materializa por defecto), por lo que no hay penalización de rendimiento respecto a subqueries anidadas.
- Las convenciones de nomenclatura y la estructura modular facilitan la reutilización y el debugging.

### Detalle técnico

**Convenciones de nomenclatura recomendadas:**

| Prefijo CTE | Significado | Ejemplo |
|-------------|-------------|---------|
| `src_` | Fuente de datos cruda | `src_empleados`, `src_evaluaciones` |
| `flt_` | Datos filtrados | `flt_empleados_activos` |
| `agg_` | Datos agregados | `agg_headcount_mensual` |
| `calc_` | Cálculos intermedios | `calc_antiguedad`, `calc_tasa_rotacion` |
| `rnk_` | Rankings aplicados | `rnk_salario_por_depto` |
| `fin_` | Resultado final | `fin_reporte_rotacion` |

**Ejemplo — Consulta profesional con CTEs bien nombrados:**

```sql
-- ==================================================================
-- Reporte: Tasa de rotación mensual por departamento y nivel
-- Autor: Equipo People Analytics
-- Última actualización: 2025-04-01
-- Frecuencia: Mensual
-- ==================================================================

WITH
-- Paso 1: Obtener snapshot de empleados activos al inicio del periodo
src_empleados AS (
    SELECT
        empleado_id,
        fecha_snapshot,
        departamento,
        nivel,
        rotacion,
        fecha_baja
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot BETWEEN '2024-01-01' AND '2025-03-01'
),

-- Paso 2: Calcular headcount al inicio de cada mes
agg_headcount AS (
    SELECT
        fecha_snapshot,
        departamento,
        nivel,
        COUNT(DISTINCT empleado_id) AS headcount_inicio
    FROM src_empleados
    WHERE rotacion = FALSE
    GROUP BY fecha_snapshot, departamento, nivel
),

-- Paso 3: Contar bajas por mes, departamento y nivel
agg_bajas AS (
    SELECT
        fecha_snapshot,
        departamento,
        nivel,
        COUNT(DISTINCT empleado_id) AS total_bajas
    FROM src_empleados
    WHERE rotacion = TRUE
    GROUP BY fecha_snapshot, departamento, nivel
),

-- Paso 4: Calcular tasa de rotación
calc_rotacion AS (
    SELECT
        h.fecha_snapshot,
        h.departamento,
        h.nivel,
        h.headcount_inicio,
        COALESCE(b.total_bajas, 0) AS total_bajas,
        SAFE_DIVIDE(
            COALESCE(b.total_bajas, 0),
            h.headcount_inicio
        ) * 100 AS tasa_rotacion_mensual,
        -- Media móvil de 3 meses
        AVG(SAFE_DIVIDE(COALESCE(b.total_bajas, 0), h.headcount_inicio) * 100) OVER (
            PARTITION BY h.departamento, h.nivel
            ORDER BY h.fecha_snapshot
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS tasa_rotacion_media_movil_3m
    FROM agg_headcount h
    LEFT JOIN agg_bajas b
        ON h.fecha_snapshot = b.fecha_snapshot
        AND h.departamento = b.departamento
        AND h.nivel = b.nivel
)

-- Paso 5: Resultado final con alertas
SELECT
    fecha_snapshot,
    departamento,
    nivel,
    headcount_inicio,
    total_bajas,
    ROUND(tasa_rotacion_mensual, 2) AS tasa_rotacion_pct,
    ROUND(tasa_rotacion_media_movil_3m, 2) AS media_movil_3m_pct,
    CASE
        WHEN tasa_rotacion_mensual > 5.0 THEN 'ALERTA_ALTA'
        WHEN tasa_rotacion_mensual > 3.0 THEN 'ATENCION'
        ELSE 'NORMAL'
    END AS nivel_alerta
FROM calc_rotacion
ORDER BY fecha_snapshot DESC, tasa_rotacion_mensual DESC;
```

**Anti-patrones a evitar:**

```sql
-- MAL: Subqueries anidadas ilegibles
SELECT * FROM (
    SELECT * FROM (
        SELECT * FROM (
            SELECT empleado_id, departamento
            FROM tabla
            WHERE condicion = TRUE
        ) sub1
        JOIN otra_tabla ON ...
    ) sub2
    WHERE ...
) sub3;

-- BIEN: CTEs secuenciales con nombres descriptivos
WITH
flt_empleados_activos AS (...),
agg_metricas_depto AS (...),
calc_benchmark AS (...)
SELECT * FROM calc_benchmark;
```

**Reglas de estilo para SQL profesional:**

| Regla | Ejemplo bueno | Ejemplo malo |
|-------|--------------|--------------|
| Palabras clave en MAYÚSCULA | `SELECT`, `FROM`, `WHERE` | `select`, `from`, `where` |
| Columnas en minúscula_snake | `fecha_snapshot` | `FechaSnapshot`, `fecha-snapshot` |
| Una columna por línea | Cada campo en línea separada | Todo en una línea |
| Indentación de 4 espacios | Consistente en todo el equipo | Tabs mezclados con espacios |
| Alias explícitos con `AS` | `COUNT(*) AS total` | `COUNT(*) total` |
| Comentar bloques lógicos | `-- Paso 1: Filtrar activos` | Sin comentarios |

### Aplicación en People Analytics
- **Mantenibilidad:** Los reportes de HR se ejecutan mensual o trimestralmente durante años. CTEs bien nombrados permiten que otro analista entienda la lógica sin documentación externa.
- **Revisión de código:** En pull requests, los revisores pueden validar cada paso lógico de forma independiente.
- **Debugging eficiente:** Cuando un número no cuadra, se puede ejecutar cada CTE por separado para identificar dónde se introduce el error.
- **Reutilización:** CTEs comunes (como `flt_empleados_activos`) se pueden extraer a vistas compartidas.

---

## Tema 7.4: Modelado de métricas de headcount y FTE

### Conceptos clave
- **Headcount** es la métrica más fundamental en People Analytics: el número de empleados en un momento dado (point-in-time) o como promedio en un periodo.
- **FTE (Full-Time Equivalent)** normaliza la jornada de trabajo: un empleado a media jornada cuenta como 0.5 FTE.
- La diferencia entre headcount y FTE es crítica para análisis de coste, capacidad y ratio de HR.
- El **headcount promedio** (average headcount) se utiliza como denominador en tasas de rotación anualizadas y ratios por empleado.
- BigQuery permite calcular estas métricas de forma eficiente gracias a las tablas de snapshots mensuales.

### Detalle técnico

**Ejemplo 1 — Point-in-time headcount:**

```sql
-- Headcount a una fecha específica
SELECT
    departamento,
    nivel,
    COUNT(DISTINCT empleado_id) AS headcount,
    SUM(CASE
        WHEN jornada = 'COMPLETA' THEN 1.0
        WHEN jornada = 'PARCIAL_80' THEN 0.8
        WHEN jornada = 'PARCIAL_50' THEN 0.5
        WHEN jornada = 'PARCIAL_25' THEN 0.25
        ELSE 1.0
    END) AS fte
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01'
    AND rotacion = FALSE
GROUP BY departamento, nivel
ORDER BY departamento, nivel;
```

**Ejemplo 2 — Average headcount para cálculo de tasa de rotación anual:**

```sql
WITH headcount_mensual AS (
    SELECT
        fecha_snapshot,
        departamento,
        COUNT(DISTINCT empleado_id) AS headcount
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot BETWEEN '2024-01-01' AND '2024-12-01'
        AND rotacion = FALSE
    GROUP BY fecha_snapshot, departamento
),

avg_headcount AS (
    SELECT
        departamento,
        ROUND(AVG(headcount), 1) AS headcount_promedio_anual
    FROM headcount_mensual
    GROUP BY departamento
),

bajas_anuales AS (
    SELECT
        departamento,
        COUNT(DISTINCT empleado_id) AS total_bajas_2024
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_baja BETWEEN '2024-01-01' AND '2024-12-31'
        AND rotacion = TRUE
    GROUP BY departamento
)

SELECT
    a.departamento,
    a.headcount_promedio_anual,
    COALESCE(b.total_bajas_2024, 0) AS total_bajas,
    ROUND(
        SAFE_DIVIDE(COALESCE(b.total_bajas_2024, 0), a.headcount_promedio_anual) * 100,
        2
    ) AS tasa_rotacion_anual_pct
FROM avg_headcount a
LEFT JOIN bajas_anuales b ON a.departamento = b.departamento
ORDER BY tasa_rotacion_anual_pct DESC;
```

**Ejemplo 3 — Evolución de FTE por departamento (serie temporal):**

```sql
SELECT
    fecha_snapshot,
    departamento,
    COUNT(DISTINCT empleado_id) AS headcount,
    SUM(CASE
        WHEN jornada = 'COMPLETA' THEN 1.0
        WHEN jornada = 'PARCIAL_80' THEN 0.8
        WHEN jornada = 'PARCIAL_50' THEN 0.5
        WHEN jornada = 'PARCIAL_25' THEN 0.25
        ELSE 1.0
    END) AS fte,
    -- Ratio FTE/headcount indica proporción de jornada reducida
    ROUND(
        SAFE_DIVIDE(
            SUM(CASE
                WHEN jornada = 'COMPLETA' THEN 1.0
                WHEN jornada = 'PARCIAL_80' THEN 0.8
                WHEN jornada = 'PARCIAL_50' THEN 0.5
                WHEN jornada = 'PARCIAL_25' THEN 0.25
                ELSE 1.0
            END),
            COUNT(DISTINCT empleado_id)
        ), 3
    ) AS ratio_fte_headcount
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot BETWEEN '2024-01-01' AND '2025-03-01'
    AND rotacion = FALSE
GROUP BY fecha_snapshot, departamento
ORDER BY departamento, fecha_snapshot;
```

### Aplicación en People Analytics
- **Presupuestos de personal:** El FTE es la base para calcular el coste de personal proyectado; el headcount solo cuenta personas.
- **Ratios operativos:** Métricas como "ingresos por FTE" o "ratio HR por cada 100 FTE" requieren FTE, no headcount.
- **Tasa de rotación anualizada:** Siempre se calcula con el headcount promedio del periodo como denominador, no con el headcount de un solo mes.
- **Reporting regulatorio:** Muchos informes legales (como el informe de brecha salarial) requieren distinguir entre headcount y FTE.

---

## Tema 7.5: Análisis longitudinal de empleados

### Conceptos clave
- El **análisis longitudinal** sigue a los mismos individuos a lo largo del tiempo, detectando cambios de estado, trayectorias profesionales y patrones de evolución.
- Con tablas de snapshots mensuales (como `silver_empleados`), cada empleado tiene una fila por cada mes, lo que permite reconstruir su historia completa.
- BigQuery ofrece `ARRAY_AGG()` para consolidar la historia de un empleado en un solo registro, facilitando análisis de secuencias.
- Detectar **cambios de estado** (cambio de departamento, nivel, salario) requiere comparar filas consecutivas del mismo empleado.

### Detalle técnico

**Ejemplo 1 — Detectar cambios de estado entre snapshots:**

```sql
WITH empleados_con_anterior AS (
    SELECT
        empleado_id,
        fecha_snapshot,
        departamento,
        nivel,
        salario_bruto,
        LAG(departamento) OVER (
            PARTITION BY empleado_id ORDER BY fecha_snapshot
        ) AS depto_anterior,
        LAG(nivel) OVER (
            PARTITION BY empleado_id ORDER BY fecha_snapshot
        ) AS nivel_anterior,
        LAG(salario_bruto) OVER (
            PARTITION BY empleado_id ORDER BY fecha_snapshot
        ) AS salario_anterior
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot BETWEEN '2024-01-01' AND '2025-03-01'
)
SELECT
    empleado_id,
    fecha_snapshot,
    -- Cambio de departamento
    CASE WHEN departamento != depto_anterior THEN TRUE ELSE FALSE END AS cambio_departamento,
    depto_anterior AS de_departamento,
    departamento AS a_departamento,
    -- Cambio de nivel (promoción/degradación)
    CASE WHEN nivel != nivel_anterior THEN TRUE ELSE FALSE END AS cambio_nivel,
    nivel_anterior AS de_nivel,
    nivel AS a_nivel,
    -- Cambio salarial
    salario_bruto - salario_anterior AS variacion_salario,
    ROUND(SAFE_DIVIDE(salario_bruto - salario_anterior, salario_anterior) * 100, 2) AS variacion_salario_pct
FROM empleados_con_anterior
WHERE depto_anterior IS NOT NULL  -- Excluir primer snapshot
    AND (
        departamento != depto_anterior
        OR nivel != nivel_anterior
        OR salario_bruto != salario_anterior
    )
ORDER BY empleado_id, fecha_snapshot;
```

**Ejemplo 2 — Historial completo de un empleado con ARRAY_AGG:**

```sql
SELECT
    empleado_id,
    MIN(fecha_snapshot) AS primer_snapshot,
    MAX(fecha_snapshot) AS ultimo_snapshot,
    COUNT(DISTINCT departamento) AS num_departamentos,
    COUNT(DISTINCT nivel) AS num_niveles,
    -- Array con la secuencia de departamentos
    ARRAY_AGG(DISTINCT departamento ORDER BY departamento) AS departamentos_unicos,
    -- Trayectoria completa de niveles (con orden temporal)
    ARRAY_AGG(
        STRUCT(fecha_snapshot, nivel, departamento, salario_bruto)
        ORDER BY fecha_snapshot
    ) AS trayectoria
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot BETWEEN '2024-01-01' AND '2025-03-01'
GROUP BY empleado_id
HAVING COUNT(DISTINCT nivel) > 1  -- Solo empleados con cambios de nivel
ORDER BY num_niveles DESC
LIMIT 100;
```

**Ejemplo 3 — Trayectoria simplificada eliminando duplicados consecutivos:**

```sql
WITH cambios AS (
    SELECT
        empleado_id,
        fecha_snapshot,
        nivel,
        departamento,
        LAG(nivel) OVER (PARTITION BY empleado_id ORDER BY fecha_snapshot) AS nivel_prev,
        LAG(departamento) OVER (PARTITION BY empleado_id ORDER BY fecha_snapshot) AS depto_prev
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot BETWEEN '2023-01-01' AND '2025-03-01'
),

solo_cambios AS (
    SELECT *
    FROM cambios
    WHERE nivel != nivel_prev
        OR departamento != depto_prev
        OR nivel_prev IS NULL  -- Primer registro
)

SELECT
    empleado_id,
    ARRAY_AGG(
        STRUCT(
            fecha_snapshot AS fecha,
            nivel,
            departamento
        )
        ORDER BY fecha_snapshot
    ) AS historial_cambios,
    COUNT(*) AS num_cambios
FROM solo_cambios
GROUP BY empleado_id
ORDER BY num_cambios DESC;
```

### Aplicación en People Analytics
- **Movilidad interna:** Identificar patrones de movimiento entre departamentos revela si la organización promueve la movilidad o los silos.
- **Trayectorias de carrera:** Secuencias de niveles permiten construir "career paths" reales versus los teóricos.
- **Detección de anomalías:** Un empleado con 3 cambios de departamento en 12 meses puede indicar un problema organizativo.
- **Equidad salarial temporal:** Comparar la evolución salarial de empleados similares permite detectar disparidades acumuladas.

---

## Tema 7.6: Identificación de patrones de salida

### Conceptos clave
- Los **patrones de salida** son secuencias de señales observables en los datos antes de que un empleado deje la organización.
- No se trata de predicción (eso es ML), sino de **análisis descriptivo** de los últimos N meses de empleados que se han ido, buscando patrones comunes.
- Señales típicas previas a la baja: caída en el desempeño, aumento del absentismo, congelación salarial, estancamiento en el nivel.
- El análisis se basa en comparar la evolución de empleados que se fueron vs. empleados similares que se quedaron.

### Detalle técnico

**Ejemplo 1 — Perfil de los últimos 6 meses antes de la baja:**

```sql
WITH empleados_baja AS (
    -- Identificar empleados con baja y su fecha
    SELECT DISTINCT
        empleado_id,
        fecha_baja
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE rotacion = TRUE
        AND fecha_baja BETWEEN '2024-01-01' AND '2024-12-31'
),

ultimos_6_meses AS (
    -- Obtener snapshots de los 6 meses previos a la baja
    SELECT
        e.empleado_id,
        e.fecha_snapshot,
        eb.fecha_baja,
        DATE_DIFF(eb.fecha_baja, e.fecha_snapshot, MONTH) AS meses_antes_baja,
        e.rating_desempeno,
        e.score_clima,
        e.dias_absentismo,
        e.horas_formacion,
        e.salario_bruto,
        e.meses_sin_promocion
    FROM `pa-prod.pa_silver.silver_empleados` e
    INNER JOIN empleados_baja eb ON e.empleado_id = eb.empleado_id
    WHERE DATE_DIFF(eb.fecha_baja, e.fecha_snapshot, MONTH) BETWEEN 0 AND 6
)

SELECT
    meses_antes_baja,
    COUNT(DISTINCT empleado_id) AS num_empleados,
    ROUND(AVG(rating_desempeno), 2) AS avg_rating,
    ROUND(AVG(score_clima), 2) AS avg_clima,
    ROUND(AVG(dias_absentismo), 1) AS avg_absentismo,
    ROUND(AVG(horas_formacion), 1) AS avg_formacion,
    ROUND(AVG(salario_bruto), 0) AS avg_salario,
    ROUND(AVG(meses_sin_promocion), 1) AS avg_meses_sin_promo
FROM ultimos_6_meses
GROUP BY meses_antes_baja
ORDER BY meses_antes_baja DESC;
```

**Ejemplo 2 — Comparación: empleados que se fueron vs. los que se quedaron:**

```sql
WITH cohorte AS (
    SELECT
        empleado_id,
        departamento,
        nivel,
        antiguedad_meses,
        rating_desempeno,
        score_clima,
        dias_absentismo,
        meses_sin_promocion,
        salario_bruto,
        rotacion,
        CASE WHEN rotacion = TRUE THEN 'Baja' ELSE 'Activo' END AS estado
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot = '2024-06-01'  -- Snapshot 6 meses antes del análisis
)

SELECT
    estado,
    COUNT(*) AS num_empleados,
    ROUND(AVG(rating_desempeno), 2) AS avg_rating,
    ROUND(AVG(score_clima), 2) AS avg_clima,
    ROUND(AVG(dias_absentismo), 1) AS avg_absentismo,
    ROUND(AVG(meses_sin_promocion), 1) AS avg_meses_sin_promo,
    ROUND(AVG(salario_bruto), 0) AS avg_salario,
    ROUND(AVG(antiguedad_meses), 1) AS avg_antiguedad,
    -- Percentil 25 del salario (para detectar desigualdad)
    ROUND(APPROX_QUANTILES(salario_bruto, 4)[OFFSET(1)], 0) AS p25_salario,
    ROUND(APPROX_QUANTILES(salario_bruto, 4)[OFFSET(3)], 0) AS p75_salario
FROM cohorte
GROUP BY estado;
```

**Ejemplo 3 — Secuencia de señales previas a la baja:**

```sql
WITH señales_baja AS (
    SELECT
        e.empleado_id,
        e.fecha_snapshot,
        -- Señal 1: Rating cayó respecto al snapshot anterior
        CASE WHEN e.rating_desempeno < LAG(e.rating_desempeno) OVER (
            PARTITION BY e.empleado_id ORDER BY e.fecha_snapshot
        ) THEN 1 ELSE 0 END AS senal_caida_rating,
        -- Señal 2: Absentismo aumentó
        CASE WHEN e.dias_absentismo > LAG(e.dias_absentismo) OVER (
            PARTITION BY e.empleado_id ORDER BY e.fecha_snapshot
        ) THEN 1 ELSE 0 END AS senal_aumento_absentismo,
        -- Señal 3: Sin promoción en >24 meses
        CASE WHEN e.meses_sin_promocion > 24 THEN 1 ELSE 0 END AS senal_estancamiento,
        -- Señal 4: Formación = 0 horas
        CASE WHEN e.horas_formacion = 0 THEN 1 ELSE 0 END AS senal_sin_formacion,
        e.rotacion
    FROM `pa-prod.pa_silver.silver_empleados` e
    WHERE e.fecha_snapshot BETWEEN '2024-06-01' AND '2024-12-01'
)

SELECT
    CASE WHEN rotacion = TRUE THEN 'Baja' ELSE 'Activo' END AS grupo,
    COUNT(DISTINCT empleado_id) AS n,
    ROUND(AVG(senal_caida_rating) * 100, 1) AS pct_caida_rating,
    ROUND(AVG(senal_aumento_absentismo) * 100, 1) AS pct_aumento_absentismo,
    ROUND(AVG(senal_estancamiento) * 100, 1) AS pct_estancamiento,
    ROUND(AVG(senal_sin_formacion) * 100, 1) AS pct_sin_formacion
FROM señales_baja
GROUP BY rotacion
ORDER BY grupo;
```

### Aplicación en People Analytics
- **Intervención temprana:** Si el análisis revela que el 70% de los empleados que se van muestran caída de rating 3 meses antes, HR puede actuar proactivamente.
- **Diseño de encuestas de salida:** Conocer los patrones cuantitativos permite diseñar preguntas más específicas en las entrevistas de salida.
- **Input para modelos predictivos:** Las señales identificadas en SQL se convierten en features para modelos de ML en módulos posteriores.
- **Business case para retención:** Cuantificar cuántos empleados muestran señales permite dimensionar el problema y justificar inversión en programas de retención.

---

## Tema 7.7: Segmentación avanzada por variables demográficas

### Conceptos clave
- La **segmentación interseccional** cruza múltiples variables demográficas simultáneamente (género x nivel x departamento) para revelar disparidades que el análisis unidimensional oculta.
- BigQuery soporta `GROUPING SETS`, `ROLLUP` y `CUBE` para generar múltiples niveles de agregación en una sola consulta.
- El análisis interseccional es fundamental para cumplimiento normativo (planes de igualdad, auditorías salariales) y para detectar sesgos sistémicos.
- Es esencial manejar correctamente los **tamaños mínimos de grupo**: no reportar métricas de grupos con menos de 5-10 personas por privacidad y significancia estadística.

### Detalle técnico

**Ejemplo 1 — Brecha salarial interseccional con GROUPING SETS:**

```sql
SELECT
    COALESCE(genero, '-- TODOS --') AS genero,
    COALESCE(nivel, '-- TODOS --') AS nivel,
    COALESCE(departamento, '-- TODOS --') AS departamento,
    COUNT(*) AS headcount,
    ROUND(AVG(salario_bruto), 0) AS salario_medio,
    ROUND(APPROX_QUANTILES(salario_bruto, 2)[OFFSET(1)], 0) AS salario_mediano,
    -- No reportar si el grupo tiene menos de 5 personas
    CASE
        WHEN COUNT(*) < 5 THEN NULL
        ELSE ROUND(AVG(salario_bruto), 0)
    END AS salario_medio_reportable,
    -- Identificar nivel de agrupación
    GROUPING(genero) AS es_total_genero,
    GROUPING(nivel) AS es_total_nivel,
    GROUPING(departamento) AS es_total_depto
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01'
    AND rotacion = FALSE
GROUP BY GROUPING SETS (
    (genero, nivel, departamento),   -- Detalle completo
    (genero, nivel),                  -- Por género y nivel
    (genero, departamento),           -- Por género y departamento
    (genero),                         -- Solo por género
    (departamento),                   -- Solo por departamento
    ()                                -- Total general
)
HAVING COUNT(*) >= 5  -- Filtrar grupos pequeños
ORDER BY genero, nivel, departamento;
```

**Ejemplo 2 — Análisis de equidad salarial con ROLLUP:**

```sql
SELECT
    COALESCE(departamento, '== TOTAL ==') AS departamento,
    COALESCE(genero, '== TOTAL ==') AS genero,
    COUNT(*) AS headcount,
    ROUND(AVG(salario_bruto), 0) AS salario_medio,
    ROUND(STDDEV(salario_bruto), 0) AS salario_desviacion,
    MIN(salario_bruto) AS salario_min,
    MAX(salario_bruto) AS salario_max,
    -- Brecha respecto al grupo de referencia (Hombre del mismo departamento)
    ROUND(AVG(salario_bruto), 0) - FIRST_VALUE(ROUND(AVG(salario_bruto), 0)) OVER (
        PARTITION BY departamento
        ORDER BY CASE WHEN genero = 'Hombre' THEN 0 ELSE 1 END
    ) AS brecha_vs_referencia
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01'
    AND rotacion = FALSE
GROUP BY ROLLUP(departamento, genero)
ORDER BY departamento, genero;
```

**Ejemplo 3 — Tasa de rotación por segmento interseccional:**

```sql
WITH segmentos AS (
    SELECT
        genero,
        nivel,
        departamento,
        COUNT(DISTINCT empleado_id) AS headcount_total,
        COUNTIF(rotacion = TRUE) AS total_bajas,
        ROUND(
            SAFE_DIVIDE(COUNTIF(rotacion = TRUE), COUNT(DISTINCT empleado_id)) * 100,
            2
        ) AS tasa_rotacion_pct
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot BETWEEN '2024-01-01' AND '2024-12-01'
    GROUP BY genero, nivel, departamento
    HAVING COUNT(DISTINCT empleado_id) >= 10  -- Mínimo estadístico
)

SELECT
    *,
    -- Comparar con la tasa global
    tasa_rotacion_pct - AVG(tasa_rotacion_pct) OVER () AS desviacion_vs_global,
    -- Ranking de mayor a menor rotación
    RANK() OVER (ORDER BY tasa_rotacion_pct DESC) AS ranking_rotacion
FROM segmentos
ORDER BY tasa_rotacion_pct DESC;
```

### Aplicación en People Analytics
- **Planes de igualdad:** La legislación española (RD 901/2020) exige análisis de brecha salarial desagregado por género, nivel y categoría profesional.
- **Auditorías salariales:** El análisis interseccional revela brechas ocultas: la brecha puede ser baja a nivel global pero significativa en ciertos niveles o departamentos.
- **Diversidad e inclusión:** Segmentar la rotación por grupos demográficos identifica si ciertos colectivos experimentan tasas de salida desproporcionadas.
- **Tamaño mínimo de grupo:** Siempre aplicar umbrales (>= 5 para salario, >= 10 para tasas) para proteger la privacidad y evitar conclusiones sobre muestras no representativas.

---

## Tema 7.8: Optimización de consultas complejas

### Conceptos clave
- En proyectos de People Analytics con datos históricos, las consultas pueden procesar varios GB de datos. Optimizar reduce costes y tiempos de ejecución.
- BigQuery cobra por **bytes escaneados** (en modo on-demand): cada optimización tiene impacto económico directo.
- Las herramientas principales de optimización son: `EXPLAIN`, particionado, clustering, evitar correlated subqueries y materializar CTEs costosos.
- La regla 80/20 aplica: el 80% de la optimización viene de evitar full table scans y de usar filtros de partición.

### Detalle técnico

**Ejemplo 1 — Uso de EXPLAIN para analizar plan de ejecución:**

```sql
-- Analizar plan de ejecución sin ejecutar la consulta
EXPLAIN
SELECT
    departamento,
    nivel,
    AVG(salario_bruto) AS salario_medio
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01'
    AND departamento = 'Tecnología'
GROUP BY departamento, nivel;
```

**Ejemplo 2 — Evitar correlated subqueries:**

```sql
-- MAL: Correlated subquery (se ejecuta por cada fila)
SELECT
    e.empleado_id,
    e.departamento,
    e.salario_bruto,
    (SELECT AVG(e2.salario_bruto)
     FROM `pa-prod.pa_silver.silver_empleados` e2
     WHERE e2.departamento = e.departamento
       AND e2.fecha_snapshot = e.fecha_snapshot
       AND e2.rotacion = FALSE
    ) AS salario_medio_depto
FROM `pa-prod.pa_silver.silver_empleados` e
WHERE e.fecha_snapshot = '2025-04-01'
    AND e.rotacion = FALSE;

-- BIEN: Reescribir con JOIN o window function
SELECT
    empleado_id,
    departamento,
    salario_bruto,
    AVG(salario_bruto) OVER (PARTITION BY departamento) AS salario_medio_depto,
    salario_bruto - AVG(salario_bruto) OVER (PARTITION BY departamento) AS desviacion_vs_media
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01'
    AND rotacion = FALSE;
```

**Ejemplo 3 — Materializar CTEs costosos como tablas temporales:**

```sql
-- Cuando un CTE se referencia múltiples veces, materializarlo
-- Paso 1: Crear tabla temporal
CREATE TEMP TABLE tmp_metricas_empleado AS
SELECT
    empleado_id,
    departamento,
    nivel,
    salario_bruto,
    antiguedad_meses,
    rating_desempeno,
    AVG(salario_bruto) OVER (PARTITION BY departamento, nivel) AS salario_medio_segmento,
    PERCENT_RANK() OVER (PARTITION BY departamento ORDER BY salario_bruto) AS percentil_salario
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01'
    AND rotacion = FALSE;

-- Paso 2: Usar la tabla temporal en consultas posteriores
SELECT
    departamento,
    nivel,
    COUNT(*) AS headcount,
    COUNTIF(percentil_salario < 0.25 AND rating_desempeno >= 4) AS alto_rendimiento_bajo_salario,
    COUNTIF(percentil_salario > 0.75 AND rating_desempeno <= 2) AS bajo_rendimiento_alto_salario
FROM tmp_metricas_empleado
GROUP BY departamento, nivel
ORDER BY alto_rendimiento_bajo_salario DESC;
```

**Checklist de optimización:**

| Punto | Verificar | Impacto |
|-------|-----------|---------|
| Filtro de partición | `WHERE fecha_snapshot = ...` presente | ALTO: reduce bytes escaneados 10-100x |
| SELECT explícito | No usar `SELECT *` | MEDIO: reduce bytes leídos |
| Clustering aprovechado | Filtros usan columnas de clustering | MEDIO: reduce bytes dentro de partición |
| Sin correlated subqueries | Reescribir como JOINs o window functions | ALTO: de O(n^2) a O(n) |
| CTEs duplicados | Materializar como TEMP TABLE si se usan 2+ veces | MEDIO: evita recalcular |
| APPROX_QUANTILES | Usar en lugar de exactos cuando sea aceptable | BAJO: ~10% más rápido |
| Filtros tempranos | Aplicar WHERE lo antes posible en CTEs | MEDIO: reduce datos en pasos posteriores |

### Aplicación en People Analytics
- **Control de costes:** Un reporte mensual mal optimizado que escanea toda la tabla histórica puede costar 10x más de lo necesario.
- **Tiempo de respuesta:** Los dashboards de Looker que usan consultas optimizadas cargan en segundos vs. minutos.
- **Escalabilidad:** A medida que crece el histórico de empleados, las consultas no optimizadas degradan exponencialmente.
- **FinOps:** El módulo 12 (FinOps) se basa en estas prácticas para monitorizar y reducir el gasto en BigQuery.

---

## Tema 7.9: Estandarización de lógica de negocio en SQL

### Conceptos clave
- Las definiciones de negocio como "empleado activo", "rotación voluntaria" o "headcount" deben estar **codificadas una sola vez** y reutilizarse en todas las consultas.
- Las **vistas** (views) y las **funciones definidas por el usuario** (UDFs) en BigQuery permiten encapsular esta lógica.
- Sin estandarización, diferentes analistas calculan la misma métrica de forma diferente, generando discrepancias que erosionan la confianza del negocio.
- El principio es **"Single Source of Truth" (SSOT)**: cada definición de negocio tiene una única implementación.

### Detalle técnico

**Ejemplo 1 — Vista para "empleado activo":**

```sql
-- Definición canónica: ¿qué es un empleado activo?
-- Un empleado es activo si: no tiene rotación, tiene fecha_snapshot vigente,
-- y no está en estado de baja temporal
CREATE OR REPLACE VIEW `pa-prod.pa_gold.v_empleados_activos` AS
SELECT
    empleado_id,
    fecha_snapshot,
    departamento,
    nivel,
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
    fecha_ingreso
FROM `pa-prod.pa_silver.silver_empleados`
WHERE rotacion = FALSE
    AND estado_laboral NOT IN ('BAJA_TEMPORAL', 'EXCEDENCIA')
;
-- IMPORTANTE: Todas las consultas que necesiten "empleados activos"
-- deben usar esta vista, NO la tabla silver con filtros propios.
```

**Ejemplo 2 — Vista para "rotación voluntaria":**

```sql
-- Definición canónica: ¿qué es rotación voluntaria?
CREATE OR REPLACE VIEW `pa-prod.pa_gold.v_rotacion_voluntaria` AS
SELECT
    empleado_id,
    fecha_baja,
    departamento,
    nivel,
    genero,
    antiguedad_meses,
    motivo_baja,
    -- Clasificación estandarizada
    CASE
        WHEN motivo_baja IN ('RENUNCIA', 'MEJOR_OFERTA', 'MOTIVOS_PERSONALES',
                              'CAMBIO_SECTOR', 'EMPRENDIMIENTO') THEN 'VOLUNTARIA'
        WHEN motivo_baja IN ('DESPIDO_DISCIPLINARIO', 'ERE', 'FIN_CONTRATO',
                              'NO_SUPERA_PRUEBA') THEN 'INVOLUNTARIA'
        WHEN motivo_baja IN ('JUBILACION', 'FALLECIMIENTO', 'INCAPACIDAD') THEN 'NATURAL'
        ELSE 'SIN_CLASIFICAR'
    END AS tipo_rotacion
FROM `pa-prod.pa_silver.silver_empleados`
WHERE rotacion = TRUE
    AND fecha_baja IS NOT NULL;
```

**Ejemplo 3 — UDF para cálculo estandarizado de antigüedad:**

```sql
-- Función reutilizable para calcular antigüedad en años
CREATE OR REPLACE FUNCTION `pa-prod.pa_gold.fn_antiguedad_anos`(
    fecha_ingreso DATE,
    fecha_referencia DATE
) AS (
    ROUND(DATE_DIFF(fecha_referencia, fecha_ingreso, DAY) / 365.25, 2)
);

-- Función para clasificar rango de antigüedad
CREATE OR REPLACE FUNCTION `pa-prod.pa_gold.fn_rango_antiguedad`(
    antiguedad_meses INT64
) AS (
    CASE
        WHEN antiguedad_meses < 6 THEN '01. < 6 meses'
        WHEN antiguedad_meses < 12 THEN '02. 6-12 meses'
        WHEN antiguedad_meses < 24 THEN '03. 1-2 años'
        WHEN antiguedad_meses < 60 THEN '04. 2-5 años'
        WHEN antiguedad_meses < 120 THEN '05. 5-10 años'
        ELSE '06. 10+ años'
    END
);

-- Uso en consultas:
SELECT
    empleado_id,
    `pa-prod.pa_gold.fn_antiguedad_anos`(fecha_ingreso, CURRENT_DATE()) AS antiguedad_anos,
    `pa-prod.pa_gold.fn_rango_antiguedad`(antiguedad_meses) AS rango
FROM `pa-prod.pa_gold.v_empleados_activos`
WHERE fecha_snapshot = '2025-04-01';
```

**Ejemplo 4 — Vista para tasa de rotación mensual estandarizada:**

```sql
CREATE OR REPLACE VIEW `pa-prod.pa_gold.v_tasa_rotacion_mensual` AS
WITH headcount AS (
    SELECT
        fecha_snapshot,
        departamento,
        COUNT(DISTINCT empleado_id) AS headcount_activo
    FROM `pa-prod.pa_gold.v_empleados_activos`
    GROUP BY fecha_snapshot, departamento
),
bajas AS (
    SELECT
        DATE_TRUNC(fecha_baja, MONTH) AS mes_baja,
        departamento,
        tipo_rotacion,
        COUNT(DISTINCT empleado_id) AS num_bajas
    FROM `pa-prod.pa_gold.v_rotacion_voluntaria`
    GROUP BY DATE_TRUNC(fecha_baja, MONTH), departamento, tipo_rotacion
)
SELECT
    h.fecha_snapshot,
    h.departamento,
    h.headcount_activo,
    COALESCE(b_vol.num_bajas, 0) AS bajas_voluntarias,
    COALESCE(b_inv.num_bajas, 0) AS bajas_involuntarias,
    COALESCE(b_vol.num_bajas, 0) + COALESCE(b_inv.num_bajas, 0) AS bajas_totales,
    ROUND(SAFE_DIVIDE(COALESCE(b_vol.num_bajas, 0), h.headcount_activo) * 100, 2) AS tasa_vol_pct,
    ROUND(SAFE_DIVIDE(
        COALESCE(b_vol.num_bajas, 0) + COALESCE(b_inv.num_bajas, 0),
        h.headcount_activo
    ) * 100, 2) AS tasa_total_pct
FROM headcount h
LEFT JOIN bajas b_vol
    ON h.fecha_snapshot = b_vol.mes_baja
    AND h.departamento = b_vol.departamento
    AND b_vol.tipo_rotacion = 'VOLUNTARIA'
LEFT JOIN bajas b_inv
    ON h.fecha_snapshot = b_inv.mes_baja
    AND h.departamento = b_inv.departamento
    AND b_inv.tipo_rotacion = 'INVOLUNTARIA';
```

### Aplicación en People Analytics
- **Confianza del negocio:** Cuando el CEO pregunta "¿cuántos empleados tenemos?" y dos analistas dan números diferentes, se pierde credibilidad. Las vistas canónicas eliminan este problema.
- **Onboarding acelerado:** Un nuevo analista del equipo solo necesita conocer las vistas gold, no reconstruir toda la lógica desde las tablas silver.
- **Auditoría:** Las definiciones de negocio en vistas son versionadas en Dataform/GitHub y trazables en el tiempo.
- **Regulación:** Los planes de igualdad y auditorías salariales exigen definiciones consistentes y documentadas.

---

## Tema 7.10: Validación de resultados y control de calidad

### Conceptos clave
- La **validación de datos** es el último paso antes de publicar cualquier métrica. Sin validación, los errores en datos upstream se propagan silenciosamente.
- BigQuery permite implementar validaciones como **assertions** (condiciones que deben cumplirse), **conteos de filas** y **checks de integridad referencial**.
- Las validaciones deben ejecutarse automáticamente (en Dataform, como assertions) o como paso final de cada consulta analítica.
- Tipos de validación: completitud, unicidad, rangos válidos, integridad referencial, consistencia temporal.

### Detalle técnico

**Ejemplo 1 — Assertions básicas en SQL puro:**

```sql
-- Assert 1: No hay duplicados de empleado por snapshot
-- Si esta consulta devuelve filas, hay un problema de calidad
SELECT
    fecha_snapshot,
    empleado_id,
    COUNT(*) AS duplicados
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01'
GROUP BY fecha_snapshot, empleado_id
HAVING COUNT(*) > 1;
-- Resultado esperado: 0 filas

-- Assert 2: No hay salarios nulos o negativos en empleados activos
SELECT
    empleado_id,
    salario_bruto
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01'
    AND rotacion = FALSE
    AND (salario_bruto IS NULL OR salario_bruto <= 0);
-- Resultado esperado: 0 filas

-- Assert 3: Todos los departamentos válidos
SELECT DISTINCT departamento
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01'
    AND departamento NOT IN (
        'Tecnología', 'Marketing', 'Ventas', 'RRHH',
        'Finanzas', 'Operaciones', 'Legal', 'Dirección'
    );
-- Resultado esperado: 0 filas
```

**Ejemplo 2 — Validación de consistencia temporal:**

```sql
-- Verificar que el headcount no varía más de un 10% entre meses consecutivos
-- (variaciones mayores suelen indicar un error de carga)
WITH headcount_mensual AS (
    SELECT
        fecha_snapshot,
        COUNT(DISTINCT empleado_id) AS headcount
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE rotacion = FALSE
    GROUP BY fecha_snapshot
),

variaciones AS (
    SELECT
        fecha_snapshot,
        headcount,
        LAG(headcount) OVER (ORDER BY fecha_snapshot) AS headcount_anterior,
        SAFE_DIVIDE(
            ABS(headcount - LAG(headcount) OVER (ORDER BY fecha_snapshot)),
            LAG(headcount) OVER (ORDER BY fecha_snapshot)
        ) * 100 AS variacion_pct
    FROM headcount_mensual
)

SELECT *
FROM variaciones
WHERE variacion_pct > 10  -- Umbral de alerta
ORDER BY fecha_snapshot;
-- Si devuelve filas, investigar ese mes
```

**Ejemplo 3 — Integridad referencial entre tablas:**

```sql
-- Verificar que todos los empleados en movimientos existen en la tabla master
SELECT DISTINCT
    m.empleado_id
FROM `pa-prod.pa_silver.silver_movimientos` m
LEFT JOIN `pa-prod.pa_silver.silver_empleados` e
    ON m.empleado_id = e.empleado_id
WHERE e.empleado_id IS NULL;
-- Resultado esperado: 0 filas (no hay huérfanos)

-- Verificar que todos los departamentos en empleados existen en dimensión
SELECT DISTINCT
    e.departamento
FROM `pa-prod.pa_silver.silver_empleados` e
LEFT JOIN `pa-prod.pa_gold.dim_departamento` d
    ON e.departamento = d.nombre_departamento
WHERE d.nombre_departamento IS NULL
    AND e.fecha_snapshot = '2025-04-01';
-- Resultado esperado: 0 filas
```

**Ejemplo 4 — Script de validación completo post-carga:**

```sql
-- Procedimiento de validación post-carga mensual
-- Ejecutar después de cada carga de datos

DECLARE fecha_carga DATE DEFAULT '2025-04-01';
DECLARE errores_encontrados INT64 DEFAULT 0;

-- Check 1: Filas cargadas
SELECT COUNT(*) AS filas_cargadas
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = fecha_carga;
-- Verificar que sea > 0 y razonable (e.g., entre 1800 y 2200)

-- Check 2: Duplicados
SET errores_encontrados = (
    SELECT COUNT(*)
    FROM (
        SELECT empleado_id, COUNT(*) AS n
        FROM `pa-prod.pa_silver.silver_empleados`
        WHERE fecha_snapshot = fecha_carga
        GROUP BY empleado_id
        HAVING COUNT(*) > 1
    )
);
SELECT IF(errores_encontrados > 0,
    ERROR(CONCAT('VALIDACIÓN FALLIDA: ', CAST(errores_encontrados AS STRING), ' empleados duplicados')),
    'OK: Sin duplicados'
) AS check_duplicados;

-- Check 3: Campos obligatorios no nulos
SET errores_encontrados = (
    SELECT COUNTIF(
        empleado_id IS NULL
        OR departamento IS NULL
        OR nivel IS NULL
        OR salario_bruto IS NULL
    )
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot = fecha_carga
);
SELECT IF(errores_encontrados > 0,
    ERROR(CONCAT('VALIDACIÓN FALLIDA: ', CAST(errores_encontrados AS STRING), ' filas con campos nulos')),
    'OK: Sin nulos en campos obligatorios'
) AS check_nulos;

-- Check 4: Rangos válidos
SET errores_encontrados = (
    SELECT COUNTIF(
        salario_bruto < 15000 OR salario_bruto > 500000
        OR edad < 18 OR edad > 70
        OR rating_desempeno < 1 OR rating_desempeno > 5
    )
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot = fecha_carga
);
SELECT IF(errores_encontrados > 0,
    ERROR(CONCAT('VALIDACIÓN FALLIDA: ', CAST(errores_encontrados AS STRING), ' filas con valores fuera de rango')),
    'OK: Valores dentro de rangos esperados'
) AS check_rangos;
```

**Tabla resumen de validaciones recomendadas:**

| Validación | Qué verifica | Frecuencia | Severidad |
|------------|-------------|------------|-----------|
| **Unicidad** | No hay duplicados por PK | Cada carga | BLOQUEANTE |
| **Not null** | Campos obligatorios tienen valor | Cada carga | BLOQUEANTE |
| **Rangos** | Valores dentro de límites razonables | Cada carga | ALERTA |
| **Integridad referencial** | FKs apuntan a registros existentes | Cada carga | BLOQUEANTE |
| **Consistencia temporal** | Variación headcount < 10% | Cada carga | ALERTA |
| **Completitud** | Todos los departamentos presentes | Cada carga | ALERTA |
| **Frescura** | Datos del mes correcto cargados | Diaria | BLOQUEANTE |

### Aplicación en People Analytics
- **Confianza en los datos:** Los stakeholders de HR necesitan confiar ciegamente en los números. Un solo error visible destruye meses de credibilidad.
- **Detección temprana:** Las validaciones automáticas detectan errores de carga antes de que lleguen a los dashboards.
- **Cumplimiento:** Las auditorías salariales y planes de igualdad requieren datos verificables y trazables.
- **Cultura de calidad:** Implementar validaciones sistemáticas establece un estándar profesional para el equipo de datos.

---

## Resumen del módulo

| Tema | Concepto clave | Herramientas SQL |
|------|---------------|------------------|
| 7.1 | Window functions | `ROW_NUMBER`, `RANK`, `LAG`, `LEAD`, `SUM() OVER` |
| 7.2 | Métricas temporales | `DATE_DIFF`, `COALESCE`, survival time |
| 7.3 | CTEs profesionales | Nomenclatura, modularidad, comentarios |
| 7.4 | Headcount y FTE | Point-in-time, average headcount, ratio FTE |
| 7.5 | Análisis longitudinal | `ARRAY_AGG`, detección de cambios con `LAG` |
| 7.6 | Patrones de salida | Señales pre-baja, comparación grupos |
| 7.7 | Segmentación interseccional | `GROUPING SETS`, `ROLLUP`, `CUBE` |
| 7.8 | Optimización | `EXPLAIN`, materialized CTEs, evitar correlated |
| 7.9 | Estandarización | Vistas canónicas, UDFs, SSOT |
| 7.10 | Validación | Assertions, checks de integridad, rangos |

---

## Preparación para el siguiente módulo

En el **Módulo 8: Dataform como Capa de Transformación Profesional**, utilizaremos todo el SQL avanzado aprendido en este módulo para construir un pipeline de transformación declarativo y versionado. Las vistas y CTEs que hemos creado aquí se convertirán en modelos SQLX de Dataform, con assertions automáticas y documentación integrada.
