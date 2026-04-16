# Módulo 13: Uso Profesional de Google Sheets desde BigQuery

## Información de la sesión
- **Sesión:** 10
- **Fecha:** Lunes 15 de Junio, 16:00–16:55
- **Duración:** ~55 minutos (sesión compartida con Módulo 14)
- **Prerequisitos:** Módulos 1–12 completados, dataset pa_gold operativo en BigQuery, acceso a Google Workspace

---

## Tema 13.1: Conexión segura entre BigQuery y Sheets

### Conceptos clave
- **Connected Sheets** es una funcionalidad nativa de Google Sheets que permite conectar una hoja de cálculo directamente a BigQuery, ejecutando consultas sobre los datos sin necesidad de exportarlos.
- A diferencia de una exportación tradicional (que crea una copia estática), Connected Sheets mantiene la conexión en vivo: los datos se consultan en BigQuery en tiempo real, respetando todos los controles de acceso (IAM, row-level security, column-level security).
- Connected Sheets requiere una licencia de **Google Workspace Business Standard** o superior, y el usuario debe tener permisos de `bigquery.jobUser` y `bigquery.dataViewer` sobre los datasets relevantes.

### Detalle técnico

**Requisitos para configurar Connected Sheets:**

| Requisito | Detalle |
|-----------|---------|
| **Licencia Workspace** | Business Standard, Business Plus, Enterprise Standard, Enterprise Plus, o Education Plus |
| **Permisos IAM** | `roles/bigquery.jobUser` (ejecutar consultas) + `roles/bigquery.dataViewer` (leer datos) |
| **Row/Column Security** | Se respetan automáticamente: el usuario solo ve los datos a los que tiene acceso en BQ |
| **Región** | BigQuery y Sheets deben estar en la misma organización de Google Workspace |
| **Límites** | Hasta 10.000 filas en extracción directa, sin límite en pivot tables y gráficos |

**Pasos para configurar una Connected Sheet:**

```
┌─────────────────────────────────────────────────────────────────┐
│           CONFIGURACIÓN DE CONNECTED SHEETS                      │
│                                                                  │
│  1. Abrir Google Sheets → Datos → Conectores de datos           │
│     → BigQuery                                                   │
│                                                                  │
│  2. Seleccionar el proyecto GCP: pa-prod                        │
│     → Dataset: pa_gold                                           │
│     → Tabla: dim_empleado (o vista v_empleado_tokenizado)       │
│                                                                  │
│  3. La conexión se establece y aparece una vista previa          │
│     de los datos (respetando row-level y column-level security) │
│                                                                  │
│  4. Crear tablas dinámicas, gráficos y fórmulas sobre           │
│     los datos de BigQuery directamente en Sheets                │
│                                                                  │
│  5. Los datos NO se copian a Sheets: cada operación             │
│     ejecuta una consulta en BigQuery                             │
│                                                                  │
│  IMPORTANTE: El usuario de Sheets ve EXACTAMENTE lo mismo        │
│  que vería si ejecutase la consulta directamente en BigQuery.    │
│  Las policy tags y row access policies se aplican.               │
└─────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- Connected Sheets es la herramienta ideal para que los HRBP y managers de RRHH accedan a datos analíticos sin necesidad de aprender SQL: pueden crear tablas dinámicas, gráficos y filtros en un entorno familiar.
- La conexión en vivo garantiza que siempre ven datos actualizados, sin el riesgo de que alguien trabaje con una exportación obsoleta.
- **Riesgo a gestionar:** Aunque los datos no se copian inicialmente, el usuario puede copiar y pegar valores a otra hoja. Este riesgo se mitiga con las políticas de DLP para Workspace (tema 13.7).

---

## Tema 13.2: Extracción controlada de datos sensibles

### Conceptos clave
- No todos los datos de BigQuery deberían ser accesibles desde Sheets. La política de extracción debe definir qué datasets, tablas y columnas están disponibles para conexión desde Sheets.
- La clasificación de datos del Módulo 11 (Public, Internal, Confidential, Restricted) guía esta política: los datos RESTRINGIDOS nunca deberían estar disponibles en Sheets, y los CONFIDENCIALES solo mediante vistas que apliquen enmascaramiento.
- Es mejor exponer **vistas controladas** en lugar de tablas directas, para garantizar que el enmascaramiento y la agregación se aplican antes de que los datos lleguen al usuario de Sheets.

### Detalle técnico

**Política de acceso desde Sheets:**

| Clasificación | Acceso desde Sheets | Mecanismo |
|---------------|---------------------|-----------|
| **Público** | Permitido sin restricciones | Tabla directa |
| **Interno** | Permitido con autenticación | Vista sin enmascaramiento |
| **Confidencial** | Permitido solo vía vista enmascarada | Vista con generalización/agregación |
| **Restringido** | Prohibido | Sin acceso desde Sheets |

**Vistas diseñadas para consumo desde Sheets:**

```sql
-- Vista para HRBP: datos de su departamento, sin salarios individuales
CREATE OR REPLACE VIEW `pa-prod.pa_sheets.v_headcount_departamento` AS
SELECT
    departamento,
    nivel,
    genero,
    COUNT(*) AS headcount,
    ROUND(AVG(antigüedad_meses), 0) AS antigüedad_media_meses,
    ROUND(AVG(rating_desempeno), 1) AS rating_medio,
    ROUND(AVG(score_clima), 1) AS clima_medio,
    -- Rango salarial en lugar de valor exacto
    CONCAT(
        CAST(FLOOR(MIN(salario_bruto) / 5000) * 5000 AS STRING),
        ' - ',
        CAST(CEILING(MAX(salario_bruto) / 5000) * 5000 AS STRING)
    ) AS rango_salarial,
    ROUND(
        COUNTIF(rotacion = 1) * 100.0 / COUNT(*), 1
    ) AS tasa_rotacion_pct
FROM `pa-prod.pa_gold.dim_empleado`
WHERE fecha_snapshot = (
    SELECT MAX(fecha_snapshot)
    FROM `pa-prod.pa_gold.dim_empleado`
)
GROUP BY departamento, nivel, genero
HAVING COUNT(*) >= 5;  -- k-anonimidad: mínimo 5 personas por grupo

-- Vista para Finance: costes de personal agregados
CREATE OR REPLACE VIEW `pa-prod.pa_sheets.v_costes_personal_mensual` AS
SELECT
    DATE_TRUNC(fecha_snapshot, MONTH) AS mes,
    departamento,
    COUNT(*) AS headcount,
    SUM(salario_bruto) AS coste_salarial_total,
    ROUND(AVG(salario_bruto), 0) AS salario_medio,
    ROUND(STDDEV(salario_bruto), 0) AS salario_stddev
FROM `pa-prod.pa_gold.dim_empleado`
GROUP BY mes, departamento
HAVING COUNT(*) >= 5;

-- Vista para managers: métricas de equipo sin PII
CREATE OR REPLACE VIEW `pa-prod.pa_sheets.v_metricas_equipo` AS
SELECT
    departamento,
    nivel,
    COUNT(*) AS personas,
    ROUND(AVG(dias_absentismo), 1) AS absentismo_medio_dias,
    ROUND(AVG(horas_formacion), 1) AS formacion_media_horas,
    ROUND(AVG(score_clima), 1) AS clima_medio,
    ROUND(AVG(rating_desempeno), 1) AS rating_medio,
    ROUND(AVG(distancia_km), 1) AS distancia_media_km
FROM `pa-prod.pa_gold.dim_empleado`
WHERE fecha_snapshot = (
    SELECT MAX(fecha_snapshot)
    FROM `pa-prod.pa_gold.dim_empleado`
)
GROUP BY departamento, nivel
HAVING COUNT(*) >= 5;
```

### Aplicación en People Analytics
- Crear un dataset específico `pa_sheets` que contenga solo vistas preparadas para consumo desde Sheets simplifica la gestión de permisos: se otorga acceso a `pa_sheets` a los grupos de HRBP y Finance, y nunca a `pa_gold` directamente.
- El filtro `HAVING COUNT(*) >= 5` garantiza la **k-anonimidad** en todas las vistas: ningún grupo con menos de 5 personas se muestra, evitando la re-identificación indirecta.
- Las vistas deben estar **documentadas en un catálogo** que explique a los usuarios de negocio qué datos contiene cada vista, su frecuencia de actualización y sus limitaciones.

---

## Tema 13.3: Limitación de acceso por usuario

### Conceptos clave
- El acceso a las Connected Sheets debe controlarse a dos niveles: quién puede **crear** conexiones a BigQuery desde Sheets, y quién puede **ver** los datos una vez que la hoja está creada.
- Google Sheets tiene su propio sistema de permisos (viewer, commenter, editor) que se combina con los permisos de BigQuery IAM. Un usuario necesita permisos en **ambos** sistemas para acceder a los datos.
- Las restricciones de dominio permiten limitar el compartir hojas solo a usuarios dentro de la organización, evitando que datos de PA se compartan externamente por error.

### Detalle técnico

**Matriz de permisos combinados (Sheets + BigQuery):**

| Permiso en Sheets | Permiso en BigQuery | Resultado |
|--------------------|---------------------|-----------|
| Editor de la hoja | `bigquery.dataViewer` + `bigquery.jobUser` | Puede ver datos y crear nuevas vistas/pivots |
| Viewer de la hoja | `bigquery.dataViewer` + `bigquery.jobUser` | Puede ver los datos existentes (las consultas se ejecutan con su identidad) |
| Viewer de la hoja | Sin permisos en BQ | Ve la estructura de la hoja pero los datos aparecen como error |
| Sin acceso a la hoja | `bigquery.dataViewer` | No puede ver nada en la hoja |

**Configuraciones de restricción recomendadas:**

```
┌─────────────────────────────────────────────────────────────────┐
│          RESTRICCIONES DE COMPARTICIÓN EN WORKSPACE              │
│                                                                  │
│  Google Admin Console → Apps → Google Workspace → Drive          │
│                                                                  │
│  1. Restricción de dominio:                                      │
│     → Compartir solo con usuarios de @empresa.com                │
│     → Desactivar "Cualquier persona con el enlace"              │
│                                                                  │
│  2. Restricción de descarga:                                     │
│     → Desactivar "Descargar, imprimir y copiar" para viewers    │
│     → Solo editors pueden descargar                              │
│                                                                  │
│  3. Expiración de acceso:                                        │
│     → Configurar acceso temporal (ej: 30 días)                  │
│     → Revisión trimestral de permisos                            │
│                                                                  │
│  4. Labels de clasificación:                                     │
│     → Etiquetar hojas con datos PA como "CONFIDENCIAL"          │
│     → Aplicar políticas DLP de Workspace según etiqueta         │
└─────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- **Escenario habitual:** Un HRBP crea una Connected Sheet con datos de headcount, la comparte con su director, y este la reenvía a un consultor externo. Con las restricciones de dominio, el consultor externo no puede acceder a los datos incluso si recibe el enlace.
- La combinación de permisos de Sheets + BigQuery crea una "doble barrera": incluso si alguien obtiene acceso a la hoja, necesita también permisos en BigQuery para ver los datos reales.
- Se recomienda utilizar **grupos de Google** para gestionar el acceso a las hojas de PA (ej: `grp-pa-sheets-hrbp@empresa.com`), facilitando las altas y bajas.

---

## Tema 13.4: Uso de Connected Sheets

### Conceptos clave
- Connected Sheets permite trabajar con datos de BigQuery utilizando la interfaz familiar de Sheets: tablas dinámicas, gráficos, columnas calculadas y fórmulas, pero sin copiar los datos localmente.
- Las operaciones de Connected Sheets se traducen en consultas SQL que se ejecutan en BigQuery, consumiendo slots (Editions) o bytes (On Demand). Esto tiene implicaciones de coste que deben gestionarse.
- Connected Sheets es especialmente potente para **análisis ad-hoc** que los usuarios de negocio necesitan hacer sin depender del equipo de datos.

### Detalle técnico

**Funcionalidades de Connected Sheets:**

| Funcionalidad | Descripción | Ejecuta consulta en BQ |
|---------------|-------------|----------------------|
| **Tabla dinámica** | Pivot table sobre datos de BQ | Sí (agregación) |
| **Gráfico** | Gráfico basado en datos de BQ | Sí (extracción + agregación) |
| **Extracción** | Copiar hasta 10.000 filas a la hoja | Sí (LIMIT 10000) |
| **Columna calculada** | Fórmula sobre datos de BQ | Sí (se traduce a SQL) |
| **Filtros** | Filtrar datos en la vista | Sí (WHERE clause) |
| **Actualizar** | Refrescar datos | Sí (re-ejecuta consulta) |

**Ejemplo de uso en People Analytics:**

```
┌─────────────────────────────────────────────────────────────────┐
│              CONNECTED SHEETS — CASO DE USO                      │
│                                                                  │
│  Escenario: HRBP de Marketing quiere analizar la rotación       │
│  de su departamento por nivel y antigüedad                      │
│                                                                  │
│  1. Abre Google Sheets → Datos → BigQuery                       │
│     → pa-prod → pa_sheets → v_headcount_departamento            │
│                                                                  │
│  2. Crea tabla dinámica:                                         │
│     Filas: nivel                                                 │
│     Columnas: genero                                             │
│     Valores: headcount (SUM), tasa_rotacion_pct (AVG)           │
│                                                                  │
│  3. Crea gráfico de barras: rotación por nivel                  │
│                                                                  │
│  4. Añade columna calculada:                                     │
│     "riesgo" = IF(tasa_rotacion_pct > 15, "ALTO", "NORMAL")    │
│                                                                  │
│  5. Comparte la hoja con su director (viewer)                   │
│     → El director ve los datos actualizados en tiempo real       │
│     → El director NO puede descargar (política de Workspace)    │
│                                                                  │
│  TODO esto SIN que el HRBP escriba una sola línea de SQL.      │
└─────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- Connected Sheets empodera a los HRBP para hacer análisis self-service sin depender del equipo de datos para cada consulta ad-hoc. Esto reduce el backlog del equipo de datos y acelera la toma de decisiones.
- **Control de costes:** Cada vez que un usuario refresca una tabla dinámica en Connected Sheets, se ejecuta una consulta en BigQuery. Si 20 HRBP abren su hoja cada mañana, son 20 consultas. Monitorizar el consumo de Connected Sheets es importante (se ve en INFORMATION_SCHEMA con el user_email del usuario de Sheets).
- Las tablas dinámicas son la funcionalidad más útil: permiten explorar los datos por múltiples dimensiones sin necesidad de consultas predefinidas.

---

## Tema 13.5: Actualización automática de datos

### Conceptos clave
- Connected Sheets puede configurarse para actualizar los datos automáticamente en intervalos regulares, garantizando que los stakeholders siempre ven información actualizada.
- Para datos que no requieren tiempo real, una alternativa más económica es usar **scheduled queries** en BigQuery que escriben los resultados en una tabla, y la Connected Sheet se conecta a esa tabla.
- La frecuencia de actualización debe alinearse con la frecuencia de actualización de los datos fuente: si el pipeline de Dataform se ejecuta a las 2:00 AM, refrescar la hoja a las 3:00 AM garantiza datos del día anterior.

### Detalle técnico

**Opciones de actualización:**

| Método | Frecuencia | Coste | Complejidad |
|--------|-----------|-------|-------------|
| **Refresh manual** | A demanda (el usuario hace clic en "Actualizar") | Bajo | Ninguna |
| **Scheduled refresh** en Sheets | Cada 1, 2, 4, 8, 12 o 24 horas | Medio | Baja |
| **Scheduled query** en BQ + Connected Sheet | Según cron de la scheduled query | Controlado | Media |
| **Dataform + tabla destino** | Según pipeline de Dataform | Mínimo (ya incluido) | Integrado |

**Configurar scheduled query para alimentar una tabla de Sheets:**

```sql
-- Scheduled query: se ejecuta diariamente a las 3:00 AM
-- Escribe los resultados en una tabla que luego consume Connected Sheets
-- Ventaja: el coste de la consulta se ejecuta UNA vez al día,
-- no cada vez que un usuario abre la hoja

CREATE OR REPLACE TABLE `pa-prod.pa_sheets.t_resumen_diario_headcount`
PARTITION BY fecha
CLUSTER BY departamento
AS
SELECT
    CURRENT_DATE() AS fecha,
    departamento,
    nivel,
    genero,
    COUNT(*) AS headcount,
    ROUND(AVG(salario_bruto), 0) AS salario_medio,
    ROUND(AVG(rating_desempeno), 1) AS rating_medio,
    ROUND(AVG(score_clima), 1) AS clima_medio,
    ROUND(
        COUNTIF(rotacion = 1) * 100.0 / COUNT(*), 1
    ) AS tasa_rotacion_pct,
    ROUND(AVG(antigüedad_meses), 0) AS antigüedad_media
FROM `pa-prod.pa_gold.dim_empleado`
WHERE fecha_snapshot = (
    SELECT MAX(fecha_snapshot)
    FROM `pa-prod.pa_gold.dim_empleado`
)
GROUP BY departamento, nivel, genero
HAVING COUNT(*) >= 5;
```

### Aplicación en People Analytics
- La **scheduled query** a tabla destino es el patrón recomendado para dashboards de Sheets: la consulta se ejecuta una vez al día, y todas las Connected Sheets se conectan a la tabla resultado. Esto controla el coste independientemente del número de usuarios que abran la hoja.
- Para datos que cambian con frecuencia intradiaria (ej: contrataciones en proceso durante una campaña de reclutamiento), el refresh automático cada 4 horas es una buena opción.
- La actualización debe documentarse en la propia hoja (ej: celda con "Datos actualizados a las 03:00 AM del día X") para que los usuarios sepan la frescura de la información.

---

## Tema 13.6: Control de versiones en hojas compartidas

### Conceptos clave
- Cuando múltiples usuarios editan una hoja de cálculo con datos de People Analytics, es fundamental mantener un control de versiones para saber quién modificó qué y cuándo.
- Google Sheets ofrece **historial de versiones** nativo, pero para un control más riguroso se recomienda usar **named ranges**, **protected ranges** y convenciones de documentación.
- Las hojas con datos de PA deben tener zonas protegidas que solo ciertos usuarios pueden modificar, evitando que un editor accidental borre o modifique datos críticos.

### Detalle técnico

**Estrategia de protección de hojas:**

```
┌─────────────────────────────────────────────────────────────────┐
│           ESTRUCTURA DE UNA HOJA PROTEGIDA DE PA                 │
│                                                                  │
│  Pestaña "Datos" (PROTEGIDA - solo el owner puede editar)       │
│  ├── Datos de Connected Sheets (tabla dinámica, gráficos)       │
│  ├── Celda A1: "Última actualización: 2026-06-15 03:00"        │
│  └── Celda A2: "Fuente: pa-prod.pa_sheets.v_headcount_depto"   │
│                                                                  │
│  Pestaña "Análisis" (EDITABLE por HRBP)                        │
│  ├── Columnas calculadas sobre los datos                        │
│  ├── Comentarios y notas del HRBP                               │
│  └── Gráficos personalizados                                    │
│                                                                  │
│  Pestaña "Metadata" (PROTEGIDA)                                 │
│  ├── Clasificación del dato: INTERNO                            │
│  ├── Owner: equipo-pa-data@empresa.com                          │
│  ├── Fecha de creación: 2026-04-15                              │
│  ├── Política de retención: Revisión trimestral                 │
│  └── Connected Sheets IDs y tablas BQ vinculadas                │
│                                                                  │
│  Named Ranges:                                                   │
│  ├── "HEADCOUNT_ACTUAL" → Datos!B2:B100                         │
│  ├── "ROTACION_PCT" → Datos!F2:F100                             │
│  └── "METADATA_OWNER" → Metadata!B2                              │
└─────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- La pestaña **Metadata** es una buena práctica para hojas de PA: cualquier persona que abra la hoja sabe inmediatamente qué clasificación tiene, quién es el responsable y de dónde vienen los datos.
- Los **named ranges** facilitan que otros documentos o hojas referencien datos específicos de forma estable (ej: un informe en Google Docs que referencia el rango "HEADCOUNT_ACTUAL" se actualiza automáticamente).
- El historial de versiones de Google Sheets permite auditar quién modificó la hoja, pero tiene un límite temporal. Para hojas críticas, se recomienda hacer una copia de seguridad trimestral.

---

## Tema 13.7: Buenas prácticas para evitar fugas de información

### Conceptos clave
- La mayor vulnerabilidad de Connected Sheets es que, una vez que los datos se muestran en la hoja, un usuario puede copiar y pegar, hacer capturas de pantalla o exportar a PDF. Los controles técnicos pueden dificultar pero no eliminar completamente este riesgo.
- Google Workspace ofrece políticas de **DLP (Data Loss Prevention)** que detectan y bloquean el compartir archivos con datos sensibles fuera de la organización.
- La combinación de controles técnicos (DLP, restricciones de descarga) y controles organizativos (formación, políticas claras, consecuencias) es la estrategia más efectiva.

### Detalle técnico

**Controles anti-fuga para hojas de People Analytics:**

| Control | Tipo | Efectividad | Implementación |
|---------|------|-------------|----------------|
| Desactivar descarga/impresión para viewers | Técnico | Alta | Configuración de compartición en Sheets |
| Restricción de dominio | Técnico | Alta | Google Admin Console |
| DLP para Workspace | Técnico | Alta | Google Admin → Reglas DLP |
| Marca de agua (Confidencial) | Disuasorio | Media | Header de la hoja |
| Formación obligatoria | Organizativo | Media | Onboarding + reciclaje anual |
| Política de consecuencias | Organizativo | Alta | Código de conducta de datos |
| Auditoría de compartición | Detective | Alta | Revisión trimestral de permisos |
| Expiración de acceso | Preventivo | Alta | Acceso temporal por defecto |

**Configuración de DLP en Google Workspace:**

```
┌─────────────────────────────────────────────────────────────────┐
│           REGLAS DLP PARA GOOGLE WORKSPACE                       │
│                                                                  │
│  Regla 1: Detectar datos salariales en hojas compartidas        │
│  ├── Condición: contenido coincide con patrón "salario"         │
│  │   + valores numéricos > 20000                                │
│  ├── Acción: Bloquear compartir externamente                    │
│  └── Notificación: al admin de seguridad                        │
│                                                                  │
│  Regla 2: Detectar DNI/NIE en archivos de Drive                │
│  ├── Condición: InfoType SPAIN_DNI o SPAIN_NIE detectado        │
│  ├── Acción: Advertencia al usuario + log                       │
│  └── Notificación: al DPO                                       │
│                                                                  │
│  Regla 3: Archivos con label "CONFIDENCIAL"                    │
│  ├── Condición: archivo tiene etiqueta de clasificación         │
│  ├── Acción: Solo compartir dentro del dominio                  │
│  └── Notificación: ninguna (preventiva silenciosa)              │
└─────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- El escenario más frecuente de fuga no es malicioso: un HRBP comparte una hoja con datos de headcount con un consultor externo de compensación para un benchmarking. Sin restricciones de dominio, los datos salen de la organización. Con DLP, se bloquea el intento y se notifica al responsable.
- Las **marcas de agua visuales** ("CONFIDENCIAL — Solo uso interno") son un control disuasorio efectivo: si alguien hace una captura de pantalla, la marca de agua aparece en la imagen.
- Se recomienda revisar trimestralmente todas las hojas de PA compartidas y verificar que los permisos siguen siendo apropiados.

---

## Tema 13.8: Validación de datos exportados

### Conceptos clave
- Cuando los datos pasan de BigQuery a Sheets (incluso via Connected Sheets), puede producirse pérdida de precisión, truncado o errores de formato que invaliden el análisis.
- La validación debe verificar: número de filas, totales de control (sumas), integridad de tipos de dato y ausencia de valores nulos inesperados.
- Es responsabilidad del equipo de datos proporcionar mecanismos de validación que los usuarios de negocio puedan verificar fácilmente.

### Detalle técnico

**Checklist de validación:**

```sql
-- Consulta de control que se incluye en la hoja para verificación
-- El usuario de Sheets compara estos valores con lo que ve en la hoja

SELECT
    'v_headcount_departamento' AS vista,
    COUNT(*) AS num_filas,
    SUM(headcount) AS total_headcount,
    COUNT(DISTINCT departamento) AS num_departamentos,
    MIN(headcount) AS min_headcount_grupo,
    MAX(headcount) AS max_headcount_grupo,
    CURRENT_TIMESTAMP() AS timestamp_verificacion
FROM `pa-prod.pa_sheets.v_headcount_departamento`;

-- Resultado esperado: se incluye en la pestaña "Metadata" de la hoja
-- para que el HRBP pueda verificar visualmente que los datos coinciden
```

**Patrón de reconciliación automatizada:**

```
┌─────────────────────────────────────────────────────────────────┐
│              VALIDACIÓN DE DATOS EN SHEETS                       │
│                                                                  │
│  En la pestaña "Validación" de cada hoja:                       │
│                                                                  │
│  ┌────────────────┬────────────────┬────────────────┐           │
│  │ Métrica        │ BigQuery       │ Sheets         │           │
│  ├────────────────┼────────────────┼────────────────┤           │
│  │ Total filas    │ =BQ_COUNT      │ =COUNTA(...)   │           │
│  │ Sum headcount  │ =BQ_SUM_HC     │ =SUM(...)      │           │
│  │ Departamentos  │ =BQ_DISTINCT   │ =UNIQUE COUNT  │           │
│  │ ¿Coinciden?    │         =IF(B=C, "OK", "ERROR") │           │
│  └────────────────┴────────────────┴────────────────┘           │
│                                                                  │
│  Si alguna fila muestra "ERROR", investigar la discrepancia     │
│  antes de usar los datos para tomar decisiones.                 │
└─────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- Un error de reconciliación en datos de headcount puede llevar a decisiones incorrectas de contratación o presupuesto. La validación no es opcional.
- Los usuarios de negocio deben acostumbrarse a verificar la pestaña de validación antes de usar los datos. Es responsabilidad del equipo de datos educar sobre esta práctica.
- Si se detectan discrepancias frecuentes, puede indicar un problema en la vista de BigQuery (ej: filtros que excluyen registros esperados) o en la configuración de Connected Sheets.

---

## Tema 13.9: Uso colaborativo con RRHH

### Conceptos clave
- Google Sheets es el puente natural entre el equipo de datos y los stakeholders de RRHH y Finanzas. Su familiaridad y facilidad de uso lo convierten en la herramienta de consumo más accesible para usuarios no técnicos.
- Los casos de uso más comunes son: compartir informes de headcount, facilitar revisiones salariales, distribuir métricas de rotación por departamento y coordinar procesos de talento.
- El modelo de colaboración debe definir claramente quién produce los datos (equipo de datos), quién los consume (RRHH) y quién los valida (ambos).

### Detalle técnico

**Casos de uso colaborativos:**

| Caso de uso | Productor | Consumidor | Tipo de hoja | Frecuencia |
|-------------|-----------|------------|--------------|------------|
| Informe mensual de headcount | Scheduled query | Director RRHH | Connected Sheet + tabla dinámica | Mensual (1er día hábil) |
| Revisión salarial anual | Equipo PA | Comp & Ben + Finance | Hoja compartida con rangos protegidos | Anual (febrero) |
| Dashboard de rotación por depto | Dataform pipeline | HRBPs | Connected Sheet con gráficos | Semanal (lunes) |
| Seguimiento de encuesta de clima | Equipo PA | Director RRHH + managers | Hoja con permisos granulares | Post-encuesta |
| Reconciliación de nómina | Finance | RRHH + Finance | Hoja protegida, solo viewers | Mensual |

**Flujo de colaboración para revisión salarial:**

```
┌─────────────────────────────────────────────────────────────────┐
│         FLUJO COLABORATIVO — REVISIÓN SALARIAL ANUAL            │
│                                                                  │
│  1. Equipo de datos prepara vista en BigQuery:                  │
│     v_revision_salarial_2026 (departamento, nivel, rango,       │
│     headcount, compa-ratio, propuesta)                          │
│                                                                  │
│  2. Se crea Connected Sheet por departamento:                   │
│     → Row-level security filtra automáticamente                 │
│     → Cada HRBP ve solo su departamento                         │
│                                                                  │
│  3. Comp & Ben añade la columna "propuesta_incremento"          │
│     en una pestaña editable (rango no protegido)                │
│                                                                  │
│  4. Finance revisa los totales de coste (viewer de la pestaña   │
│     de Comp & Ben, no puede editar)                             │
│                                                                  │
│  5. Director RRHH aprueba → se genera tabla final en BigQuery   │
│     que alimenta el proceso de nómina                           │
│                                                                  │
│  6. Auditoría: historial de versiones de Sheets documenta       │
│     quién propuso cada cambio y cuándo                          │
└─────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- La revisión salarial es uno de los procesos más sensibles de RRHH y uno donde la colaboración via Sheets es más natural. Connected Sheets garantiza que los datos base son siempre los oficiales de BigQuery.
- El equipo de datos debe resistir la tentación de crear "la hoja perfecta": es mejor proporcionar los datos con estructura clara y dejar que RRHH la personalice según sus necesidades.
- La **documentación del flujo** (quién hace qué, en qué orden, con qué plazos) es tan importante como la implementación técnica.

---

## Tema 13.10: Gobernanza del uso de hojas conectadas

### Conceptos clave
- A medida que la organización adopta Connected Sheets, el número de hojas conectadas a BigQuery crece de forma orgánica. Sin gobernanza, se pierde visibilidad sobre quién accede a qué datos desde qué hoja.
- Se necesita un **registro centralizado** de todas las Connected Sheets activas, con información sobre su propósito, owner, datos vinculados y última revisión.
- La auditoría periódica debe verificar que las hojas siguen siendo necesarias, que los permisos son correctos y que las políticas de seguridad se cumplen.

### Detalle técnico

**Registro de hojas conectadas:**

```sql
-- Tabla de registro de Connected Sheets (mantenida manualmente o via API de Drive)
CREATE OR REPLACE TABLE `pa-prod.pa_config.registro_connected_sheets` (
    sheet_id STRING NOT NULL,
    sheet_nombre STRING NOT NULL,
    sheet_url STRING,
    owner_email STRING NOT NULL,
    departamento_consumidor STRING,
    dataset_bigquery STRING NOT NULL,
    tablas_conectadas ARRAY<STRING>,
    clasificacion STRING,  -- 'PUBLICO', 'INTERNO', 'CONFIDENCIAL'
    fecha_creacion DATE,
    fecha_ultima_revision DATE,
    estado STRING,  -- 'ACTIVA', 'ARCHIVADA', 'PENDIENTE_REVISION'
    notas STRING
);

-- Vista para el informe trimestral de gobernanza
CREATE OR REPLACE VIEW `pa-prod.pa_config.v_sheets_pendientes_revision` AS
SELECT
    sheet_nombre,
    owner_email,
    clasificacion,
    dataset_bigquery,
    fecha_ultima_revision,
    DATE_DIFF(CURRENT_DATE(), fecha_ultima_revision, DAY) AS dias_sin_revision,
    CASE
        WHEN DATE_DIFF(CURRENT_DATE(), fecha_ultima_revision, DAY) > 90 THEN 'REVISION_URGENTE'
        WHEN DATE_DIFF(CURRENT_DATE(), fecha_ultima_revision, DAY) > 60 THEN 'REVISION_PENDIENTE'
        ELSE 'OK'
    END AS estado_revision
FROM `pa-prod.pa_config.registro_connected_sheets`
WHERE estado = 'ACTIVA'
ORDER BY dias_sin_revision DESC;
```

### Aplicación en People Analytics
- La gobernanza de hojas conectadas es un proceso continuo, no un evento puntual. Cada trimestre, el responsable del registro debe verificar que las hojas activas siguen siendo necesarias y que los permisos son correctos.
- Las hojas que ya no se usan deben **archivarse** (no eliminarse): se desconectan de BigQuery, se mueven a una carpeta de archivo en Drive y se marca como "ARCHIVADA" en el registro.
- Incluir el **coste de BigQuery** generado por cada Connected Sheet (consultable en INFORMATION_SCHEMA por user_email) en el registro ayuda a identificar hojas con alto consumo que podrían optimizarse.

---

## Resumen del módulo

```
┌────────────────────────────────────────────────────────────────┐
│         GOOGLE SHEETS — BUENAS PRÁCTICAS IMPLEMENTADAS          │
│                                                                  │
│  CONEXIÓN           │  SEGURIDAD            │  GOBERNANZA       │
│  ─────────          │  ──────────           │  ──────────       │
│  Connected Sheets   │  Vistas controladas   │  Registro central │
│  Dataset pa_sheets  │  k-anonimidad (≥5)    │  Auditoría trim.  │
│  Refresh programado │  DLP Workspace        │  Owner por hoja   │
│  Scheduled queries  │  Restricción dominio  │  Clasificación    │
│                     │  Rangos protegidos    │  Expiración       │
│                                                                  │
│  PRINCIPIO: Los datos viven en BigQuery.                        │
│  Sheets es una ventana controlada, no una copia.                │
└────────────────────────────────────────────────────────────────┘
```

---

## Próximo módulo

**Módulo 14: Looker como Capa de Consumo Analítico** — De la hoja de cálculo al dashboard profesional: modelado semántico, métricas oficiales y self-service controlado con LookML.
