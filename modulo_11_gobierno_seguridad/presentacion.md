# Módulo 11: Gobierno del Dato y Seguridad en People Analytics

## Información de la sesión
- **Sesión:** 9
- **Fecha:** Lunes 8 de Junio, 16:00–17:05
- **Duración:** ~65 minutos (sesión compartida con Módulo 12)
- **Prerequisitos:** Módulos 1–10 completados, pipeline de datos operativo en BigQuery

---

## Tema 11.1: Principios de data governance en RRHH

### Conceptos clave
- El **gobierno del dato** en Recursos Humanos no es solo una cuestión técnica: es una responsabilidad organizativa que afecta a la privacidad de las personas, al cumplimiento normativo y a la confianza del empleado en la empresa.
- A diferencia de otros dominios analíticos (marketing, finanzas), los datos de personas tienen un componente ético y legal único: representan individuos identificables con derechos sobre su información.
- Un framework de gobierno del dato en People Analytics debe definir claramente tres pilares: **Data Ownership** (quién es responsable del dato), **Data Stewardship** (quién lo gestiona operativamente) y **Data Classification** (cómo se categoriza según su sensibilidad).

### Detalle técnico

**Framework de roles en data governance:**

| Rol | Responsabilidad | Ejemplo en People Analytics |
|-----|----------------|-----------------------------|
| **Data Owner** | Decide qué datos se recogen, quién accede y para qué | Director de RRHH (decide que se registre la evaluación de desempeño) |
| **Data Steward** | Garantiza la calidad, completitud y cumplimiento del dato | Analista de datos de RRHH (valida que el campo `salario_bruto` no tenga nulos) |
| **Data Custodian** | Implementa los controles técnicos (accesos, cifrado, backups) | Ingeniero de datos (configura IAM, column-level security en BigQuery) |
| **Data Consumer** | Consume los datos según los permisos otorgados | HRBP que consulta un dashboard de rotación en Looker |

**Marco de clasificación de datos:**

```
┌─────────────────────────────────────────────────────────────────┐
│               CLASIFICACIÓN DE DATOS EN PEOPLE ANALYTICS        │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ RESTRINGIDO (Restricted)                                   │  │
│  │ - Datos médicos (bajas por enfermedad, discapacidad)       │  │
│  │ - Datos sindicales o afiliación política                   │  │
│  │ - Resultados de evaluaciones psicológicas                  │  │
│  │ → Acceso: solo RRHH senior + DPO, cifrado obligatorio     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ CONFIDENCIAL (Confidential)                                │  │
│  │ - Salarios, bonus, equity                                  │  │
│  │ - Evaluaciones de desempeño individuales                   │  │
│  │ - Datos de contratación/rescisión                          │  │
│  │ → Acceso: RRHH + manager directo, enmascaramiento parcial │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ INTERNO (Internal)                                         │  │
│  │ - Departamento, centro de trabajo, antigüedad              │  │
│  │ - Datos agregados de headcount por división                │  │
│  │ - Métricas de formación por equipo                         │  │
│  │ → Acceso: empleados autorizados, sin PII individual        │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ PÚBLICO (Public)                                           │  │
│  │ - Número total de empleados (publicado en memoria anual)   │  │
│  │ - Índice de satisfacción global (encuesta anónima)         │  │
│  │ → Acceso: sin restricciones                                │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- Antes de construir cualquier pipeline o dashboard, el equipo de datos debe sentarse con RRHH y el DPO (Data Protection Officer) para clasificar cada campo del dataset según este framework.
- Un error habitual es tratar todos los datos de empleados con el mismo nivel de protección, lo que resulta en políticas demasiado restrictivas (nadie puede acceder a nada) o demasiado laxas (todo el mundo accede a todo).
- **Ejemplo real:** El campo `salario_bruto` es CONFIDENCIAL, pero su agregación `avg(salario_bruto) GROUP BY departamento` puede ser INTERNO si el grupo tiene al menos 5 personas (principio de k-anonimidad).

---

## Tema 11.2: Gestión de accesos con IAM

### Conceptos clave
- **IAM (Identity and Access Management)** es el sistema de control de accesos de GCP. Todo acceso a BigQuery, Cloud Storage, Vertex AI y cualquier otro servicio pasa por IAM.
- La filosofía debe ser siempre de **privilegio mínimo (least privilege)**: cada usuario o servicio obtiene solo los permisos estrictamente necesarios para su función.
- En People Analytics, la jerarquía de accesos debe reflejar la estructura organizativa: no todos los analistas necesitan ver salarios, no todos los managers necesitan ver datos de otros departamentos.

### Detalle técnico

**Jerarquía de roles en BigQuery:**

| Nivel | Rol IAM | Alcance | Ejemplo PA |
|-------|---------|---------|------------|
| **Proyecto** | `roles/bigquery.jobUser` | Puede ejecutar consultas | Todo analista del equipo de datos |
| **Dataset** | `roles/bigquery.dataViewer` | Puede leer tablas de un dataset | Analista de RRHH → `pa_gold` (solo lectura) |
| **Dataset** | `roles/bigquery.dataEditor` | Puede escribir/modificar tablas | Pipeline de Dataform → `pa_silver`, `pa_gold` |
| **Tabla** | Binding específico | Acceso a una tabla concreta | Finance → solo `fact_costes_personal` |
| **Columna** | Policy tags | Acceso a columnas concretas | Solo RRHH senior ve `salario_bruto` |
| **Fila** | Row-level access policy | Acceso a filas concretas | Cada HRBP ve solo su departamento |

**Configuración de IAM por grupo (recomendado sobre usuarios individuales):**

```sql
-- En BigQuery, otorgar acceso a nivel de dataset a un grupo de Google
-- Se ejecuta via bq CLI o la API, no es SQL puro

-- Concepto: otorgar acceso de lectura al grupo de analistas PA
-- Grupo: grp-pa-analysts@empresa.com → roles/bigquery.dataViewer en pa_gold
-- Grupo: grp-pa-engineers@empresa.com → roles/bigquery.dataEditor en pa_silver, pa_gold
-- Grupo: grp-hrbp@empresa.com → roles/bigquery.dataViewer en pa_gold (con row-level filtering)
```

**Configurar acceso con `gcloud`:**

```bash
# Otorgar rol de dataViewer en un dataset específico
bq update --dataset \
  --source=policy.json \
  pa-prod:pa_gold

# Donde policy.json contiene:
# {
#   "access": [
#     {
#       "role": "READER",
#       "groupByEmail": "grp-pa-analysts@empresa.com"
#     },
#     {
#       "role": "WRITER",
#       "groupByEmail": "grp-pa-engineers@empresa.com"
#     }
#   ]
# }
```

**Service accounts para pipelines (nunca cuentas personales):**

```bash
# Crear service account para el pipeline de Dataform
gcloud iam service-accounts create sa-dataform-pa \
  --display-name="Dataform People Analytics Pipeline" \
  --project=pa-prod

# Otorgar solo los permisos necesarios
gcloud projects add-iam-policy-binding pa-prod \
  --member="serviceAccount:sa-dataform-pa@pa-prod.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding pa-prod \
  --member="serviceAccount:sa-dataform-pa@pa-prod.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"
```

### Aplicación en People Analytics
- Los **grupos de Google** son la unidad recomendada para gestionar accesos: cuando un nuevo analista se une al equipo, se añade al grupo `grp-pa-analysts@empresa.com` y hereda automáticamente todos los permisos.
- Las **service accounts** deben usarse para todos los pipelines automatizados. Nunca configurar un pipeline con las credenciales de un empleado (si se va de la empresa, el pipeline deja de funcionar).
- **Principio de separación:** El equipo de ingeniería de datos puede modificar las tablas silver y gold, pero no debería tener acceso a las credenciales de producción de los sistemas fuente (SAP, Workday).

---

## Tema 11.3: Column-level y row-level security en BigQuery

### Conceptos clave
- BigQuery permite controlar el acceso a nivel de **columna** (policy tags) y de **fila** (row-level access policies), permitiendo que diferentes usuarios vean diferentes porciones de la misma tabla.
- Esto es esencial en People Analytics: un HRBP de Marketing solo debería ver los datos de su departamento, y solo RRHH senior debería ver los salarios individuales.
- Las **policy tags** se gestionan a través de **Data Catalog** y se aplican a columnas específicas. Las **row-level access policies** se definen con SQL directamente sobre la tabla.

### Detalle técnico

**Column-level security con policy tags:**

```sql
-- Paso 1: Crear una taxonomía de policy tags en Data Catalog
-- (Se hace via consola o API, aquí el concepto)
-- Taxonomía: "people_analytics_sensitivity"
--   ├── Tag: "PII_alto"       → salario_bruto, evaluacion_individual
--   ├── Tag: "PII_medio"      → nombre, email, telefono
--   └── Tag: "PII_bajo"       → departamento, centro_trabajo

-- Paso 2: Aplicar policy tag a una columna
-- En la definición de la tabla o con ALTER TABLE:
ALTER TABLE `pa-prod.pa_gold.dim_empleado`
ALTER COLUMN salario_bruto
SET OPTIONS (
    description = 'Salario bruto anual en EUR - CONFIDENCIAL'
);
-- La policy tag se aplica via Data Catalog API o consola:
-- bq update --schema schema_with_tags.json pa-prod:pa_gold.dim_empleado

-- Paso 3: Otorgar acceso a la policy tag
-- Solo los miembros con el rol "Fine-Grained Reader" en la policy tag
-- pueden ver los valores de esas columnas.
-- Los demás usuarios ven un error si intentan SELECT salario_bruto.

-- Consulta de un usuario SIN acceso a la columna salario_bruto:
-- SELECT empleado_id, nombre, salario_bruto FROM dim_empleado;
-- ERROR: Access Denied: BigQuery BigQuery: User does not have
-- permission to access policy tag "PII_alto" on column "salario_bruto".

-- Consulta válida para ese usuario (sin la columna restringida):
SELECT empleado_id, departamento, antigüedad_meses
FROM `pa-prod.pa_gold.dim_empleado`;
```

**Row-level security con access policies:**

```sql
-- Crear una row-level access policy para que cada HRBP
-- solo vea los empleados de su departamento

-- Tabla de mapeo: qué usuario ve qué departamento
CREATE OR REPLACE TABLE `pa-prod.pa_config.hrbp_departamento_mapping` (
    email STRING,
    departamento STRING
);

INSERT INTO `pa-prod.pa_config.hrbp_departamento_mapping` VALUES
('maria.garcia@empresa.com', 'Marketing'),
('carlos.lopez@empresa.com', 'Tecnología'),
('ana.martinez@empresa.com', 'Finanzas'),
('pedro.sanchez@empresa.com', 'Operaciones');

-- Crear la row-level access policy
CREATE ROW ACCESS POLICY filtro_departamento_hrbp
ON `pa-prod.pa_gold.dim_empleado`
GRANT TO (
    'group:grp-hrbp@empresa.com'
)
FILTER USING (
    departamento IN (
        SELECT departamento
        FROM `pa-prod.pa_config.hrbp_departamento_mapping`
        WHERE email = SESSION_USER()
    )
);

-- Crear política para que el equipo de data vea todo
CREATE ROW ACCESS POLICY acceso_completo_data_team
ON `pa-prod.pa_gold.dim_empleado`
GRANT TO (
    'group:grp-pa-engineers@empresa.com',
    'group:grp-pa-analysts@empresa.com'
)
FILTER USING (TRUE);

-- Verificar políticas existentes
SELECT *
FROM `pa-prod.pa_gold.INFORMATION_SCHEMA.ROW_ACCESS_POLICIES`
WHERE table_name = 'dim_empleado';
```

**Combinación de column-level y row-level security:**

```
┌─────────────────────────────────────────────────────────────┐
│                     dim_empleado                             │
│                                                              │
│  Columnas:                                                   │
│  ┌──────────┬──────────┬──────────────┬───────────────────┐  │
│  │ empl_id  │ depto    │ salario_bruto│ eval_desempeño    │  │
│  │ (libre)  │ (libre)  │ (PII_alto)   │ (PII_alto)        │  │
│  ├──────────┼──────────┼──────────────┼───────────────────┤  │
│  │ E001     │ Marketing│ 45000        │ 4.2               │  │
│  │ E002     │ Tech     │ 62000        │ 3.8               │  │
│  │ E003     │ Marketing│ 51000        │ 4.5               │  │
│  │ E004     │ Finanzas │ 48000        │ 3.1               │  │
│  └──────────┴──────────┴──────────────┴───────────────────┘  │
│                                                              │
│  HRBP Marketing (maria.garcia@):                             │
│  → Ve filas E001, E003 (row filter)                          │
│  → NO ve salario_bruto ni eval_desempeño (column policy)     │
│                                                              │
│  RRHH Senior (directora.rrhh@):                              │
│  → Ve TODAS las filas (acceso completo)                      │
│  → Ve TODAS las columnas (tiene Fine-Grained Reader)         │
└─────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- La seguridad a nivel de fila es especialmente útil para dashboards compartidos: un mismo dashboard de Looker muestra datos diferentes a cada HRBP según su departamento, sin necesidad de crear dashboards separados.
- La seguridad a nivel de columna protege campos como `salario_bruto`, `evaluacion_desempeno` e `identificacion_fiscal` incluso de los propios ingenieros de datos que administran las tablas.
- **Regla de oro:** Si un analista no necesita una columna para su análisis, no debería poder verla. Es más seguro denegar por defecto y otorgar acceso bajo demanda.

---

## Tema 11.4: Enmascaramiento de datos sensibles

### Conceptos clave
- El **enmascaramiento de datos (data masking)** permite que los usuarios accedan a una versión transformada de los datos sensibles, en lugar de los valores originales.
- A diferencia de la column-level security (que bloquea completamente el acceso), el enmascaramiento permite que el usuario vea la estructura del dato pero no su valor real.
- Existen múltiples técnicas de enmascaramiento, cada una con diferentes niveles de utilidad analítica y seguridad.

### Detalle técnico

**Técnicas de enmascaramiento en BigQuery:**

| Técnica | Descripción | Reversible | Uso recomendado |
|---------|-------------|-----------|-----------------|
| **SHA256** | Hash criptográfico irreversible | No | Pseudonimización para análisis sin necesidad de identificar |
| **Tokenización** | Sustitución por token aleatorio con tabla de mapeo | Sí (con clave) | Cuando se necesita re-identificar en emergencias |
| **Generalización** | Reducir la precisión del dato | No | Rangos salariales en lugar de valores exactos |
| **Supresión** | Eliminar el campo | No | Campos nunca necesarios para análisis |
| **Data Masking Policy** | Política nativa de BigQuery | N/A | Enmascaramiento automático basado en roles |

**Implementación de enmascaramiento con SQL:**

```sql
-- 1. Hash SHA256 para pseudonimizar empleados
SELECT
    SHA256(CAST(empleado_id AS STRING)) AS empleado_id_hash,
    departamento,
    nivel,
    -- Generalizar salario en rangos de 10.000€
    CONCAT(
        CAST(FLOOR(salario_bruto / 10000) * 10000 AS STRING),
        ' - ',
        CAST((FLOOR(salario_bruto / 10000) + 1) * 10000 AS STRING)
    ) AS rango_salarial,
    rating_desempeno,
    rotacion
FROM `pa-prod.pa_gold.dim_empleado`;

-- 2. Tokenización con tabla de mapeo (almacenada en dataset restringido)
-- Crear tabla de tokens
CREATE OR REPLACE TABLE `pa-prod.pa_restricted.token_mapping` AS
SELECT
    empleado_id,
    GENERATE_UUID() AS token,
    CURRENT_TIMESTAMP() AS created_at
FROM `pa-prod.pa_gold.dim_empleado`;

-- Vista tokenizada para analistas
CREATE OR REPLACE VIEW `pa-prod.pa_gold.v_empleado_tokenizado` AS
SELECT
    t.token AS empleado_token,
    e.departamento,
    e.nivel,
    e.antigüedad_meses,
    -- Enmascarar email: m****@empresa.com
    CONCAT(
        SUBSTR(e.email, 1, 1),
        '****@',
        SPLIT(e.email, '@')[OFFSET(1)]
    ) AS email_masked,
    e.rating_desempeno
FROM `pa-prod.pa_gold.dim_empleado` e
JOIN `pa-prod.pa_restricted.token_mapping` t
    ON e.empleado_id = t.empleado_id;

-- 3. Data Masking Policy nativa de BigQuery
-- (Disponible en BigQuery con policy tags)
-- Se configura en Data Catalog: una policy tag con "masking rule"
-- Ejemplo: la columna salario_bruto se muestra como NULL
-- para usuarios sin el rol Fine-Grained Reader,
-- en lugar de dar error de acceso.

-- 4. Generalización de datos para k-anonimidad
-- Solo mostrar agregaciones con al menos 5 personas
CREATE OR REPLACE VIEW `pa-prod.pa_gold.v_salarios_por_grupo` AS
SELECT
    departamento,
    nivel,
    genero,
    COUNT(*) AS num_empleados,
    CASE
        WHEN COUNT(*) >= 5 THEN ROUND(AVG(salario_bruto), 0)
        ELSE NULL  -- Suprimir si el grupo es menor a 5
    END AS salario_medio,
    CASE
        WHEN COUNT(*) >= 5 THEN ROUND(STDDEV(salario_bruto), 0)
        ELSE NULL
    END AS salario_stddev
FROM `pa-prod.pa_gold.dim_empleado`
GROUP BY departamento, nivel, genero;
```

### Aplicación en People Analytics
- El **hash SHA256** es ideal para análisis de rotación o cohortes donde no necesitamos saber quién es el empleado, solo seguir su trayectoria de forma anonimizada.
- La **generalización en rangos salariales** permite que los HRBP analicen equidad salarial sin ver salarios individuales: ven que "en Marketing hay 3 Senior en el rango 40-50K y 2 en el rango 50-60K".
- La regla de **k-anonimidad** (mínimo 5 personas por grupo) es un estándar de facto en People Analytics para evitar la re-identificación indirecta.

---

## Tema 11.5: Clasificación de información confidencial

### Conceptos clave
- La clasificación de información no es un ejercicio teórico: debe traducirse en controles técnicos reales implementados en BigQuery, IAM y las herramientas de visualización.
- El framework de clasificación de cuatro niveles (Public, Internal, Confidential, Restricted) debe documentarse y comunicarse a todo el equipo, con ejemplos concretos de cada categoría aplicados al contexto de People Analytics.
- Cada nivel de clasificación determina: quién puede acceder, cómo se almacena, si requiere enmascaramiento, si se puede exportar y cuánto tiempo se retiene.

### Detalle técnico

**Matriz de controles por nivel de clasificación:**

| Control | Público | Interno | Confidencial | Restringido |
|---------|---------|---------|--------------|-------------|
| **Acceso** | Cualquiera | Empleados autorizados | RRHH + aprobación | Solo DPO + RRHH director |
| **Cifrado** | Estándar GCP | Estándar GCP | CMEK recomendado | CMEK obligatorio |
| **Enmascaramiento** | No | No | Parcial (rangos) | Completo (hash/tokenizar) |
| **Exportación** | Libre | Con aprobación | Prohibido a Sheets | Prohibido |
| **Retención** | Sin límite | Según política | GDPR Art. 5(1)(e) | Mínimo necesario |
| **Auditoría** | No requerida | Trimestral | Mensual | Continua (Cloud Audit Logs) |
| **Ejemplo PA** | N.º total empleados | Headcount por depto | Salarios, evaluaciones | Datos médicos, sindicales |

**Implementar CMEK (Customer-Managed Encryption Keys) para datos restringidos:**

```bash
# Crear key ring en Cloud KMS para datos de PA
gcloud kms keyrings create pa-keyring \
  --location=europe-west1 \
  --project=pa-prod

# Crear clave de cifrado
gcloud kms keys create pa-restricted-key \
  --keyring=pa-keyring \
  --location=europe-west1 \
  --purpose=encryption \
  --rotation-period=90d \
  --project=pa-prod

# Crear dataset con CMEK
bq mk --dataset \
  --default_kms_key=projects/pa-prod/locations/europe-west1/keyRings/pa-keyring/cryptoKeys/pa-restricted-key \
  --description="Datos restringidos con cifrado CMEK" \
  pa-prod:pa_restricted
```

### Aplicación en People Analytics
- Los **datos restringidos** (médicos, sindicales) nunca deberían estar en el mismo dataset que los datos confidenciales. Se almacenan en un dataset separado (`pa_restricted`) con CMEK y auditoría continua.
- La **política de exportación** es crítica: si un analista puede exportar datos confidenciales a Google Sheets y compartirlos externamente, todas las políticas de column-level security se anulan.
- Documentar la clasificación en una tabla de Data Catalog o en un inventario de datos accesible al equipo facilita que cada miembro sepa cómo tratar cada campo.

---

## Tema 11.6: Auditoría de accesos y consultas

### Conceptos clave
- La **auditoría** es la capacidad de saber quién accedió a qué datos, cuándo, desde dónde y con qué consulta. Es un requisito legal (GDPR Art. 5(2) — principio de responsabilidad) y una buena práctica operativa.
- GCP ofrece **Cloud Audit Logs** que registran automáticamente las operaciones administrativas y de acceso a datos. BigQuery además expone información detallada de consultas a través de `INFORMATION_SCHEMA.JOBS`.
- La auditoría en People Analytics debe responder preguntas como: "¿Quién consultó la tabla de salarios en los últimos 30 días?" o "¿Se exportaron datos de empleados fuera de BigQuery?"

### Detalle técnico

**Consultar el historial de jobs de BigQuery:**

```sql
-- ¿Quién ha consultado la tabla de salarios en los últimos 30 días?
SELECT
    user_email,
    job_id,
    creation_time,
    total_bytes_processed,
    total_slot_ms,
    query
FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
    AND (
        REGEXP_CONTAINS(query, r'(?i)salario_bruto')
        OR REGEXP_CONTAINS(query, r'(?i)dim_empleado')
        OR REGEXP_CONTAINS(query, r'(?i)evaluacion_desempeno')
    )
ORDER BY creation_time DESC;

-- ¿Cuántos bytes ha procesado cada usuario en el último mes?
SELECT
    user_email,
    COUNT(*) AS num_queries,
    SUM(total_bytes_processed) / POW(1024, 3) AS total_gb_processed,
    SUM(total_bytes_billed) / POW(1024, 3) AS total_gb_billed,
    MAX(creation_time) AS last_query
FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
GROUP BY user_email
ORDER BY total_gb_processed DESC;

-- ¿Se han realizado exportaciones (EXTRACT) de datos de empleados?
SELECT
    user_email,
    creation_time,
    destination_table.dataset_id,
    destination_table.table_id,
    query
FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
    AND REGEXP_CONTAINS(query, r'(?i)EXPORT\s+DATA')
ORDER BY creation_time DESC;
```

**Configurar alertas automáticas de auditoría:**

```sql
-- Vista materializada para detectar accesos anómalos
-- (más de 10 consultas a tablas sensibles en una hora)
CREATE OR REPLACE VIEW `pa-prod.pa_audit.v_accesos_anomalos` AS
SELECT
    user_email,
    TIMESTAMP_TRUNC(creation_time, HOUR) AS hora,
    COUNT(*) AS num_consultas_sensibles,
    ARRAY_AGG(DISTINCT REGEXP_EXTRACT(query, r'(?i)(dim_empleado|fact_salarios|eval_desempeno)')) AS tablas_accedidas
FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
    AND REGEXP_CONTAINS(query, r'(?i)(dim_empleado|fact_salarios|eval_desempeno)')
GROUP BY user_email, TIMESTAMP_TRUNC(creation_time, HOUR)
HAVING COUNT(*) > 10;
```

### Aplicación en People Analytics
- La auditoría no es solo para detectar accesos maliciosos: es útil para optimizar (¿qué tablas nadie consulta?) y para compliance (demostrar al DPO que solo las personas autorizadas accedieron a datos de salarios).
- Se recomienda crear una **consulta programada** semanal que genere un informe de accesos a tablas sensibles y lo envíe al responsable de seguridad del equipo de datos.
- Los Cloud Audit Logs se pueden exportar a BigQuery mediante **Log Sinks** para análisis histórico de largo plazo (más allá de los 30 días de INFORMATION_SCHEMA).

---

## Tema 11.7: Minimización del dato

### Conceptos clave
- El **principio de minimización** (GDPR Art. 5(1)(c)) establece que solo deben recogerse y procesarse los datos que sean estrictamente necesarios para la finalidad declarada.
- En People Analytics, esto significa preguntarse antes de cada ingesta: "¿Realmente necesitamos este campo para nuestro análisis? ¿Podemos lograr el mismo resultado con datos agregados o anonimizados?"
- La minimización no es solo una obligación legal: reduce el riesgo (menos datos sensibles = menor impacto en caso de brecha), simplifica la gobernanza y reduce costes de almacenamiento.

### Detalle técnico

**Checklist de minimización para pipelines de People Analytics:**

| Pregunta | Acción si la respuesta es NO |
|----------|------------------------------|
| ¿El campo es necesario para algún análisis actual o planificado? | No ingerir el campo |
| ¿Se necesita el dato a nivel individual o basta con agregado? | Agregar en la ingesta |
| ¿Se necesita la precisión completa (salario exacto vs rango)? | Generalizar |
| ¿Se necesita la identificación del empleado? | Pseudonimizar (SHA256) |
| ¿Se necesita retener el dato más allá de X meses? | Configurar política de retención |

**Implementar minimización en el pipeline de Dataform:**

```sql
-- En Dataform: modelo silver que ya aplica minimización
-- archivo: definitions/silver/silver_empleados.sqlx

config {
    type: "table",
    schema: "pa_silver",
    description: "Tabla de empleados minimizada - solo campos necesarios para análisis PA",
    assertions: {
        nonNull: ["empleado_id_hash", "departamento", "fecha_ingreso"]
    }
}

SELECT
    -- Pseudonimizar: nunca almacenar el ID original en silver/gold
    SHA256(CAST(empleado_id AS STRING)) AS empleado_id_hash,

    -- Campos necesarios para segmentación
    departamento,
    nivel,
    centro_trabajo,

    -- Generalizar edad en rangos de 5 años
    CONCAT(CAST(FLOOR(edad / 5) * 5 AS STRING), '-', CAST(FLOOR(edad / 5) * 5 + 4 AS STRING)) AS rango_edad,

    -- Fecha de ingreso (sin hora exacta)
    DATE(fecha_ingreso) AS fecha_ingreso,

    -- Métricas necesarias (sin generalizar, se protegen con column-level security)
    salario_bruto,
    rating_desempeno,
    score_clima,

    -- NO incluir: nombre, email, teléfono, DNI, dirección
    -- Estos campos se quedan en bronze y solo son accesibles
    -- para casos específicos con aprobación

    CURRENT_DATE() AS fecha_snapshot

FROM ${ref("bronze_empleados")}
WHERE fecha_snapshot = CURRENT_DATE()
```

### Aplicación en People Analytics
- **Datos que frecuentemente se recogen innecesariamente:** dirección postal del empleado (¿realmente se necesita para análisis de rotación?), número de hijos (datos especialmente protegidos), nacionalidad (si no es relevante para el análisis).
- La minimización debe aplicarse en la **capa silver**, no en gold: los datos originales se mantienen en bronze (para auditoría y requerimientos legales), pero la capa que consumen los analistas ya está minimizada.
- **Política de retención:** Los datos de empleados que han dejado la empresa deben eliminarse o anonimizarse tras un período definido (típicamente 2-5 años según la normativa laboral española).

---

## Tema 11.8: Cumplimiento de GDPR en GCP

### Conceptos clave
- El **GDPR (Reglamento General de Protección de Datos)** es la normativa europea de protección de datos personales. Aplica a cualquier tratamiento de datos de empleados en la UE.
- GCP proporciona controles técnicos que se mapean directamente a los artículos del GDPR, pero la responsabilidad de configurarlos correctamente es del **responsable del tratamiento** (la empresa), no del proveedor (Google).
- En People Analytics, prácticamente todo el dato es "dato personal" según el GDPR, y algunos campos (salud, sindical) son "datos de categoría especial" con protección reforzada.

### Detalle técnico

**Mapeo GDPR a controles GCP:**

| Artículo GDPR | Requisito | Control en GCP |
|----------------|-----------|----------------|
| **Art. 5** — Principios | Minimización, limitación finalidad | Dataform (transformar solo lo necesario), políticas de retención en BQ |
| **Art. 6** — Base legal | Necesidad de base legal para tratar | Documentar en Data Catalog la base legal de cada dataset |
| **Art. 9** — Categorías especiales | Protección reforzada datos salud/sindicales | Dataset `pa_restricted` con CMEK + IAM restrictivo |
| **Art. 17** — Derecho al olvido | Borrar datos a petición del interesado | Procedimiento de DELETE + verificación en todas las capas |
| **Art. 22** — Decisiones automatizadas | Derecho a no ser sujeto de decisiones solo automáticas | Human-in-the-loop obligatorio en modelos de Vertex AI |
| **Art. 25** — Protección por diseño | Privacy by design y by default | Column-level security activado por defecto, acceso denegado por defecto |
| **Art. 32** — Seguridad del tratamiento | Medidas técnicas y organizativas | IAM, cifrado, audit logs, VPC Service Controls |
| **Art. 35** — DPIA | Evaluación de impacto obligatoria para tratamientos de alto riesgo | DPIA antes de implementar modelos predictivos sobre empleados |

**Implementar derecho al olvido (Art. 17):**

```sql
-- Procedimiento almacenado para ejecutar el derecho al olvido
-- Se invoca cuando RRHH recibe una solicitud formal de borrado
CREATE OR REPLACE PROCEDURE `pa-prod.pa_ops.ejecutar_derecho_olvido`(
    IN p_empleado_id STRING,
    IN p_solicitante STRING,
    IN p_motivo STRING
)
BEGIN
    DECLARE v_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

    -- 1. Registrar la solicitud en el log de auditoría
    INSERT INTO `pa-prod.pa_audit.log_derecho_olvido` (
        empleado_id, solicitante, motivo, timestamp_solicitud, estado
    ) VALUES (
        p_empleado_id, p_solicitante, p_motivo, v_timestamp, 'EN_PROCESO'
    );

    -- 2. Eliminar de la capa gold
    DELETE FROM `pa-prod.pa_gold.dim_empleado`
    WHERE empleado_id = p_empleado_id;

    DELETE FROM `pa-prod.pa_gold.fact_rotacion`
    WHERE empleado_id = p_empleado_id;

    -- 3. Anonimizar en la capa silver (no borrar, para integridad referencial)
    UPDATE `pa-prod.pa_silver.silver_empleados`
    SET
        nombre = 'ANONIMIZADO',
        email = 'anonimizado@deleted.com',
        telefono = NULL,
        direccion = NULL,
        salario_bruto = NULL,
        dni = NULL
    WHERE empleado_id = p_empleado_id;

    -- 4. Registrar la finalización
    UPDATE `pa-prod.pa_audit.log_derecho_olvido`
    SET estado = 'COMPLETADO',
        timestamp_completado = CURRENT_TIMESTAMP()
    WHERE empleado_id = p_empleado_id
        AND timestamp_solicitud = v_timestamp;
END;

-- Ejecutar:
-- CALL `pa-prod.pa_ops.ejecutar_derecho_olvido`('E12345', 'dpo@empresa.com', 'Solicitud empleado ex');
```

### Aplicación en People Analytics
- El **derecho al olvido** es uno de los más complejos de implementar en pipelines de datos: requiere localizar al empleado en todas las capas (bronze, silver, gold), en todas las tablas y en los backups.
- Las **decisiones automatizadas** (Art. 22) son especialmente relevantes: si un modelo de Vertex AI predice qué empleados tienen riesgo de rotación y eso influye en decisiones de promoción, se requiere una DPIA previa y supervisión humana obligatoria.
- La **localización de datos** en la región `EU` (o `europe-west1`) es un control técnico que facilita el cumplimiento del Art. 44+ sobre transferencias internacionales.

---

## Tema 11.9: Gestión de consentimientos

### Conceptos clave
- En el contexto laboral, la **base legal** para tratar datos de empleados suele ser el "interés legítimo" o la "ejecución del contrato" (GDPR Art. 6(1)(b) y (f)), no el consentimiento. Sin embargo, para ciertos tratamientos (encuestas de clima, análisis predictivos de rotación), puede requerirse consentimiento explícito.
- La gestión de consentimientos debe estar integrada en el pipeline de datos: si un empleado retira su consentimiento para análisis predictivos, sus datos deben excluirse automáticamente de los datasets que alimentan esos modelos.

### Detalle técnico

**Tabla de consentimientos en BigQuery:**

```sql
-- Tabla de registro de consentimientos
CREATE OR REPLACE TABLE `pa-prod.pa_config.consentimientos_empleados` (
    empleado_id STRING NOT NULL,
    tipo_tratamiento STRING NOT NULL,  -- 'PREDICTIVO', 'ENCUESTA_CLIMA', 'BENCHMARK_SALARIAL'
    consentimiento BOOL NOT NULL,
    fecha_consentimiento TIMESTAMP NOT NULL,
    fecha_retiro TIMESTAMP,
    canal STRING,  -- 'EMAIL', 'PORTAL_RRHH', 'ESCRITO'
    ip_origen STRING,
    version_politica STRING  -- Versión de la política de privacidad aceptada
)
PARTITION BY DATE(fecha_consentimiento)
CLUSTER BY empleado_id, tipo_tratamiento;

-- Vista que filtra automáticamente empleados sin consentimiento
CREATE OR REPLACE VIEW `pa-prod.pa_gold.v_empleados_con_consentimiento_predictivo` AS
SELECT e.*
FROM `pa-prod.pa_gold.dim_empleado` e
INNER JOIN `pa-prod.pa_config.consentimientos_empleados` c
    ON e.empleado_id = c.empleado_id
WHERE c.tipo_tratamiento = 'PREDICTIVO'
    AND c.consentimiento = TRUE
    AND c.fecha_retiro IS NULL;

-- Esta vista es la que debe alimentar los modelos de Vertex AI,
-- NUNCA la tabla dim_empleado directamente
```

### Aplicación en People Analytics
- Los modelos de predicción de rotación en Vertex AI deben alimentarse exclusivamente de la vista filtrada por consentimiento, nunca de la tabla completa.
- El registro de consentimientos debe incluir un **versionado de la política de privacidad**: si la política cambia, los consentimientos anteriores pueden no ser válidos para los nuevos tratamientos.
- Es responsabilidad de RRHH (no del equipo de datos) obtener y gestionar los consentimientos; el equipo de datos implementa los controles técnicos para respetarlos.

---

## Tema 11.10: Cultura de responsabilidad del dato

### Conceptos clave
- La tecnología y las políticas son necesarias pero no suficientes: sin una **cultura de responsabilidad** compartida por todo el equipo, los controles técnicos se sortean o se ignoran.
- Cada miembro del equipo debe entender que los datos de empleados no son "solo datos": representan personas reales con derecho a la privacidad.
- La cultura se construye con formación continua, comunicación clara de las normas, ejemplos de buenas y malas prácticas, y consecuencias reales para las violaciones.

### Detalle técnico

**Pilares de la cultura de responsabilidad:**

```
┌────────────────────────────────────────────────────────────────┐
│           CULTURA DE RESPONSABILIDAD DEL DATO                   │
│                                                                  │
│  1. FORMACIÓN                                                    │
│     - Onboarding obligatorio sobre protección de datos           │
│     - Reciclaje anual GDPR para todo el equipo de datos          │
│     - Simulacros de incidentes de seguridad                      │
│                                                                  │
│  2. PROCESOS                                                     │
│     - Revisión de seguridad obligatoria en cada PR               │
│     - Checklist de privacidad antes de poner en producción       │
│     - Canal interno para reportar dudas/incidentes               │
│                                                                  │
│  3. COMUNICACIÓN                                                 │
│     - Newsletter mensual del DPO con recordatorios               │
│     - Casos de estudio (anonimizados) de incidentes reales       │
│     - Reconocimiento público de buenas prácticas                 │
│                                                                  │
│  4. ACCOUNTABILITY                                               │
│     - Cada dataset tiene un owner documentado                    │
│     - Las violaciones de política tienen consecuencias reales    │
│     - Auditoría trimestral de accesos con revisión por el owner  │
│                                                                  │
│  5. ÉTICA                                                        │
│     - Filtro ético: Legal → Ético → Útil → Accionable           │
│     - Comité de ética para nuevos tratamientos de datos          │
│     - Transparencia con los empleados sobre qué datos se usan   │
└────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- El **filtro ético** (Legal, Ético, Útil, Accionable) debe aplicarse a cada nuevo proyecto de People Analytics: que sea legal no significa que sea ético, y que sea ético no significa que sea útil.
- **Ejemplo:** Analizar la correlación entre el código postal del empleado y su probabilidad de rotación es legal y técnicamente posible, pero puede ser éticamente cuestionable si el código postal es un proxy de nivel socioeconómico o etnia.
- La comunicación con los empleados (transparencia sobre qué datos se recogen y para qué) genera confianza y facilita la adopción del programa de People Analytics.

---

## Tema 11.11: Uso de Cloud DLP / Sensitive Data Protection

### Conceptos clave
- **Cloud DLP (Data Loss Prevention)**, renombrado como **Sensitive Data Protection**, es el servicio de GCP para descubrir, clasificar y proteger datos sensibles.
- DLP puede inspeccionar datos en BigQuery, Cloud Storage, Datastore y otros servicios para detectar automáticamente PII (Personally Identifiable Information) como nombres, DNI, emails, números de tarjeta, IBAN, etc.
- Además de detectar, DLP puede **des-identificar** datos aplicando transformaciones (hashing, tokenización, generalización) de forma automatizada.

### Detalle técnico

**Conceptos clave de DLP:**

| Concepto | Descripción |
|----------|-------------|
| **InfoType** | Tipo de dato sensible predefinido (PERSON_NAME, SPAIN_DNI, EMAIL_ADDRESS, etc.) |
| **Inspection Job** | Escaneo de un recurso (tabla BQ, bucket GCS) para detectar infoTypes |
| **De-identification Template** | Plantilla que define cómo transformar los datos sensibles encontrados |
| **Finding** | Cada instancia de dato sensible detectada, con su ubicación y probabilidad |
| **Likelihood** | Nivel de confianza de la detección (VERY_UNLIKELY → VERY_LIKELY) |

**InfoTypes relevantes para People Analytics en España:**

| InfoType | Detecta | Ejemplo |
|----------|---------|---------|
| `PERSON_NAME` | Nombres de personas | "María García López" |
| `EMAIL_ADDRESS` | Direcciones de email | "m.garcia@empresa.com" |
| `PHONE_NUMBER` | Números de teléfono | "+34 612 345 678" |
| `SPAIN_DNI` | DNI/NIE españoles | "12345678Z", "X1234567A" |
| `SPAIN_NIE` | NIE específicamente | "Y1234567X" |
| `SPAIN_SOCIAL_SECURITY_NUMBER` | Número de la Seguridad Social | "28/12345678/01" |
| `IBAN_CODE` | Números IBAN | "ES91 2100 0418 4502 0005 1332" |
| `DATE_OF_BIRTH` | Fechas de nacimiento | "15/03/1985" |
| `STREET_ADDRESS` | Direcciones postales | "Calle Mayor 15, 3ºB" |
| `FINANCIAL_ACCOUNT_NUMBER` | Números de cuenta | "2100 0418 45 0200051332" |

**Crear un inspection job con Python:**

```python
from google.cloud import dlp_v2

def inspeccionar_tabla_bigquery(
    project_id: str,
    dataset_id: str,
    table_id: str,
    info_types: list[str] = None
) -> dict:
    """
    Ejecuta un inspection job de DLP sobre una tabla de BigQuery
    para detectar datos sensibles (PII).

    Args:
        project_id: ID del proyecto GCP
        dataset_id: Dataset de BigQuery
        table_id: Tabla a inspeccionar
        info_types: Lista de infoTypes a buscar

    Returns:
        Resultado del inspection job con los findings
    """
    dlp_client = dlp_v2.DlpServiceClient()

    # InfoTypes relevantes para People Analytics en España
    if info_types is None:
        info_types = [
            "PERSON_NAME",
            "EMAIL_ADDRESS",
            "PHONE_NUMBER",
            "SPAIN_DNI",
            "SPAIN_NIE",
            "SPAIN_SOCIAL_SECURITY_NUMBER",
            "IBAN_CODE",
            "DATE_OF_BIRTH",
            "STREET_ADDRESS",
            "FINANCIAL_ACCOUNT_NUMBER",
        ]

    # Configuración de la inspección
    inspect_config = {
        "info_types": [{"name": it} for it in info_types],
        "min_likelihood": dlp_v2.Likelihood.LIKELY,
        "limits": {
            "max_findings_per_request": 100,
        },
        "include_quote": True,  # Incluir el texto encontrado
    }

    # Recurso a inspeccionar
    storage_config = {
        "big_query_options": {
            "table_reference": {
                "project_id": project_id,
                "dataset_id": dataset_id,
                "table_id": table_id,
            },
            "rows_limit": 10000,  # Limitar filas para controlar coste
            "sample_method": "RANDOM_START",
        }
    }

    # Acción: guardar findings en BigQuery
    actions = [
        {
            "save_findings": {
                "output_config": {
                    "table": {
                        "project_id": project_id,
                        "dataset_id": "pa_audit",
                        "table_id": f"dlp_findings_{table_id}",
                    }
                }
            }
        }
    ]

    # Crear el inspection job
    inspect_job = {
        "inspect_config": inspect_config,
        "storage_config": storage_config,
        "actions": actions,
    }

    parent = f"projects/{project_id}/locations/europe-west1"
    response = dlp_client.create_dlp_job(
        request={
            "parent": parent,
            "inspect_job": inspect_job,
        }
    )

    print(f"Job creado: {response.name}")
    print(f"Estado: {response.state.name}")
    return response


# Ejemplo de uso: inspeccionar la tabla bronze de empleados
resultado = inspeccionar_tabla_bigquery(
    project_id="pa-prod",
    dataset_id="pa_bronze",
    table_id="bronze_empleados"
)
```

**Consultar los findings del inspection job:**

```sql
-- Ver los findings de DLP almacenados en BigQuery
SELECT
    info_type.name AS tipo_dato_sensible,
    likelihood AS probabilidad,
    location.content_locations[SAFE_OFFSET(0)].record_location.field_id.name AS columna,
    quote AS texto_encontrado,
    COUNT(*) OVER (PARTITION BY info_type.name) AS total_por_tipo
FROM `pa-prod.pa_audit.dlp_findings_bronze_empleados`
WHERE likelihood IN ('LIKELY', 'VERY_LIKELY')
ORDER BY info_type.name, likelihood DESC
LIMIT 50;
```

### Aplicación en People Analytics
- Se recomienda ejecutar un **inspection job de DLP mensual** sobre las tablas bronze para verificar que no se están ingiriendo datos sensibles no previstos (por ejemplo, un nuevo campo de la fuente que contiene comentarios con datos médicos).
- Los findings se almacenan en BigQuery para análisis histórico: permiten detectar tendencias como "desde que cambiamos el sistema de ATS, el campo `notas_entrevista` contiene nombres completos de candidatos que deberían estar anonimizados".
- **Coste:** DLP cobra por volumen de datos inspeccionados. Se recomienda usar sampling (`rows_limit`) y ejecutar inspecciones periódicas en lugar de en tiempo real.

---

## Tema 11.12: Identificación automática de datos sensibles PII

### Conceptos clave
- La identificación automática de PII complementa la clasificación manual: incluso con un inventario de datos bien documentado, pueden existir campos que contienen PII no detectada (campos de texto libre, comentarios de evaluaciones, notas de entrevistas).
- DLP permite crear **perfiles de datos** que escanean automáticamente todos los recursos de un proyecto y clasifican cada columna según el tipo de dato sensible que contiene.
- La combinación de detección automática (DLP) y clasificación manual (Data Catalog) proporciona la cobertura más completa.

### Detalle técnico

**Crear un de-identification template para anonimizar datos detectados:**

```python
from google.cloud import dlp_v2

def crear_template_desidentificacion(project_id: str) -> str:
    """
    Crea un template de des-identificación en DLP que define
    cómo transformar cada tipo de dato sensible.
    """
    dlp_client = dlp_v2.DlpServiceClient()

    # Definir transformaciones por tipo de dato
    deidentify_config = {
        "record_transformations": {
            "field_transformations": [
                {
                    # Nombres → reemplazar con placeholder
                    "info_type_transformations": {
                        "transformations": [
                            {
                                "info_types": [{"name": "PERSON_NAME"}],
                                "primitive_transformation": {
                                    "replace_config": {
                                        "new_value": {
                                            "string_value": "[NOMBRE_REDACTADO]"
                                        }
                                    }
                                },
                            },
                            {
                                # DNI → hash SHA256
                                "info_types": [
                                    {"name": "SPAIN_DNI"},
                                    {"name": "SPAIN_NIE"},
                                ],
                                "primitive_transformation": {
                                    "crypto_hash_config": {
                                        "crypto_key": {
                                            "kms_wrapped": {
                                                "wrapped_key": "BASE64_ENCODED_KEY",
                                                "crypto_key_name": (
                                                    "projects/pa-prod/locations/europe-west1/"
                                                    "keyRings/pa-keyring/cryptoKeys/dlp-key"
                                                ),
                                            }
                                        }
                                    }
                                },
                            },
                            {
                                # Email → enmascarar parcialmente
                                "info_types": [{"name": "EMAIL_ADDRESS"}],
                                "primitive_transformation": {
                                    "character_mask_config": {
                                        "masking_character": "*",
                                        "number_to_mask": 5,
                                        "characters_to_ignore": [
                                            {"characters_to_skip": "@."}
                                        ],
                                    }
                                },
                            },
                            {
                                # Teléfono → reemplazar
                                "info_types": [{"name": "PHONE_NUMBER"}],
                                "primitive_transformation": {
                                    "replace_config": {
                                        "new_value": {
                                            "string_value": "+34 XXX XXX XXX"
                                        }
                                    }
                                },
                            },
                        ]
                    }
                }
            ]
        }
    }

    parent = f"projects/{project_id}/locations/europe-west1"
    template = dlp_client.create_deidentify_template(
        request={
            "parent": parent,
            "deidentify_template": {
                "display_name": "PA - Plantilla de des-identificación estándar",
                "description": "Anonimización de PII en datos de People Analytics",
                "deidentify_config": deidentify_config,
            },
        }
    )

    print(f"Template creado: {template.name}")
    return template.name


# Crear el template
template_name = crear_template_desidentificacion("pa-prod")
```

**Automatizar la inspección periódica con Cloud Scheduler:**

```
┌───────────────────────────────────────────────────────────────┐
│              FLUJO DE INSPECCIÓN AUTOMÁTICA DLP                │
│                                                                │
│  Cloud Scheduler (cron: 0 2 1 * *)                            │
│       │ (1º de cada mes a las 2:00 AM)                        │
│       ▼                                                        │
│  Cloud Function: trigger_dlp_inspection()                      │
│       │                                                        │
│       ├──► DLP Inspection Job: pa_bronze.bronze_empleados      │
│       ├──► DLP Inspection Job: pa_bronze.bronze_evaluaciones   │
│       └──► DLP Inspection Job: pa_bronze.bronze_candidatos     │
│                │                                               │
│                ▼                                                │
│  Findings → pa_audit.dlp_findings_*                            │
│                │                                               │
│                ▼                                                │
│  Scheduled Query: resumen mensual de PII detectada             │
│                │                                               │
│                ▼                                                │
│  Alerta a Slack/email si se detectan nuevos tipos de PII       │
└───────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- La inspección automática es especialmente valiosa cuando se integran nuevas fuentes de datos: si RRHH conecta un nuevo ATS (Applicant Tracking System), el scan de DLP detectará inmediatamente si los datos incluyen PII no prevista.
- Los templates de des-identificación se reutilizan en toda la organización, garantizando que la anonimización sea consistente en todos los pipelines.
- **Coste estimado:** Inspeccionar 100.000 filas con 10 InfoTypes cuesta aproximadamente 1-3 USD por ejecución.

---

## Tema 11.13: Uso de Secret Manager para gestión segura de credenciales

### Conceptos clave
- **Secret Manager** es el servicio de GCP para almacenar y gestionar de forma segura credenciales, claves de API, tokens de acceso y cualquier otro dato secreto que necesiten los pipelines.
- Las credenciales **nunca** deben estar en código fuente, variables de entorno en texto claro, hojas de cálculo ni en ningún lugar accesible fuera de Secret Manager.
- En People Analytics, los secretos típicos son: credenciales de conexión a sistemas HRIS (SAP, Workday), tokens de API de plataformas de encuestas (Qualtrics), claves de servicio para Cloud Functions, y passwords de bases de datos fuente.

### Detalle técnico

**Crear y acceder a secretos con Python:**

```python
from google.cloud import secretmanager

def crear_secreto(project_id: str, secret_id: str, valor: str) -> str:
    """
    Crea un secreto en Secret Manager y almacena su primer valor.

    Args:
        project_id: ID del proyecto GCP
        secret_id: Nombre identificador del secreto
        valor: Valor del secreto (credencial, API key, etc.)

    Returns:
        Nombre completo del secreto creado
    """
    client = secretmanager.SecretManagerServiceClient()
    parent = f"projects/{project_id}"

    # Crear el secreto (contenedor)
    secret = client.create_secret(
        request={
            "parent": parent,
            "secret_id": secret_id,
            "secret": {
                "replication": {
                    "user_managed": {
                        "replicas": [
                            {"location": "europe-west1"},
                        ]
                    }
                },
                "labels": {
                    "equipo": "people-analytics",
                    "clasificacion": "restringido",
                },
            },
        }
    )

    # Añadir la versión con el valor
    version = client.add_secret_version(
        request={
            "parent": secret.name,
            "payload": {"data": valor.encode("UTF-8")},
        }
    )

    print(f"Secreto creado: {secret.name}")
    print(f"Versión: {version.name}")
    return secret.name


def obtener_secreto(project_id: str, secret_id: str, version: str = "latest") -> str:
    """
    Obtiene el valor de un secreto desde Secret Manager.

    Args:
        project_id: ID del proyecto GCP
        secret_id: Nombre del secreto
        version: Versión a recuperar (default: "latest")

    Returns:
        Valor del secreto como string
    """
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/{version}"

    response = client.access_secret_version(request={"name": name})
    payload = response.payload.data.decode("UTF-8")

    print(f"Secreto obtenido: {secret_id} (versión {version})")
    return payload


def rotar_secreto(project_id: str, secret_id: str, nuevo_valor: str) -> str:
    """
    Rota un secreto añadiendo una nueva versión y deshabilitando la anterior.
    """
    client = secretmanager.SecretManagerServiceClient()
    parent = f"projects/{project_id}/secrets/{secret_id}"

    # Obtener la versión actual para deshabilitarla después
    # Listar versiones activas
    versions = client.list_secret_versions(
        request={"parent": parent, "filter": "state:ENABLED"}
    )
    versiones_activas = [v.name for v in versions]

    # Añadir nueva versión
    nueva_version = client.add_secret_version(
        request={
            "parent": parent,
            "payload": {"data": nuevo_valor.encode("UTF-8")},
        }
    )
    print(f"Nueva versión creada: {nueva_version.name}")

    # Deshabilitar versiones anteriores
    for v in versiones_activas:
        client.disable_secret_version(request={"name": v})
        print(f"Versión deshabilitada: {v}")

    return nueva_version.name


# --- Ejemplo de uso en pipeline de People Analytics ---

# Almacenar credenciales del sistema HRIS
crear_secreto(
    project_id="pa-prod",
    secret_id="hris-api-key",
    valor="sk-prod-a1b2c3d4e5f6g7h8i9j0"
)

# Almacenar credenciales de la base de datos de nóminas
crear_secreto(
    project_id="pa-prod",
    secret_id="nominas-db-password",
    valor="P@ssw0rd_Pr0d_N0m1n4s_2026!"
)

# Usar en una Cloud Function de ingesta
def ingerir_datos_hris():
    """Cloud Function que ingiere datos del HRIS usando Secret Manager."""
    import requests

    api_key = obtener_secreto("pa-prod", "hris-api-key")

    response = requests.get(
        "https://api.hris-empresa.com/v2/employees",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        params={"updated_since": "2026-06-01"},
    )

    if response.status_code == 200:
        empleados = response.json()["data"]
        # Procesar y cargar en BigQuery...
        print(f"Ingesta completada: {len(empleados)} empleados")
    else:
        raise RuntimeError(f"Error HRIS API: {response.status_code}")
```

**Gestión de permisos para Secret Manager:**

```bash
# Solo la service account del pipeline puede acceder a los secretos
gcloud secrets add-iam-policy-binding hris-api-key \
  --member="serviceAccount:sa-ingesta-pa@pa-prod.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project=pa-prod

# El equipo de ingeniería puede gestionar (crear/rotar) secretos
gcloud secrets add-iam-policy-binding hris-api-key \
  --member="group:grp-pa-engineers@empresa.com" \
  --role="roles/secretmanager.secretVersionManager" \
  --project=pa-prod

# NADIE más debería tener acceso a los secretos de producción
# Verificar quién tiene acceso:
gcloud secrets get-iam-policy hris-api-key --project=pa-prod
```

**Política de rotación de secretos:**

| Tipo de secreto | Frecuencia de rotación | Responsable |
|-----------------|----------------------|-------------|
| API keys de servicios externos | Cada 90 días | Ingeniero de datos |
| Passwords de bases de datos | Cada 60 días | DBA / SRE |
| Service account keys | Cada 90 días (o usar Workload Identity) | DevOps |
| Tokens OAuth de integraciones | Según expiración del token | Automatizado |

### Aplicación en People Analytics
- El error más común en equipos de datos es tener la API key del HRIS en una variable de entorno o, peor aún, hardcodeada en un notebook de Jupyter. **Secret Manager elimina este riesgo.**
- La **rotación periódica** de secretos es especialmente importante cuando hay cambios en el equipo: si un ingeniero deja la empresa y tenía acceso a las credenciales, la rotación garantiza que las credenciales antiguas dejan de funcionar.
- **Workload Identity Federation** es la alternativa preferida a las service account keys: permite que Cloud Functions y otros servicios se autentiquen sin necesidad de gestionar claves JSON.

---

## Resumen del módulo

```
┌────────────────────────────────────────────────────────────────┐
│          GOBIERNO Y SEGURIDAD — CONTROLES IMPLEMENTADOS         │
│                                                                  │
│  GOBERNANZA          │  SEGURIDAD              │  CUMPLIMIENTO  │
│  ─────────────       │  ──────────             │  ────────────  │
│  Data ownership      │  IAM least privilege    │  GDPR mapeo    │
│  Clasificación 4N    │  Column-level security  │  Art. 17 proc  │
│  Cultura ética       │  Row-level security     │  Consentimiento│
│  Minimización        │  Enmascaramiento        │  DPIA          │
│                      │  Cloud DLP              │  Auditoría     │
│                      │  Secret Manager         │  Retención     │
│                                                                  │
│  HERRAMIENTAS GCP:                                              │
│  IAM · Data Catalog · Policy Tags · Cloud DLP ·                 │
│  Secret Manager · Cloud Audit Logs · INFORMATION_SCHEMA ·       │
│  Cloud KMS (CMEK)                                               │
└────────────────────────────────────────────────────────────────┘
```

---

## Próximo módulo

**Módulo 12: Estrategia de FinOps y Control de Costes** — Pasamos del "quién puede acceder" al "cuánto cuesta lo que ejecutamos", con modelos de pricing de BigQuery, análisis de costes y alertas automáticas.
