# Seguridad y Permisos en BigQuery

Material de clase · Sesión 4 · Curso BigQuery + Dataform · People Analytics

---

## 1. La idea fundamental

En BigQuery, los permisos funcionan como **muñecas rusas**: lo que concedes en un nivel se hereda automáticamente en todo lo que está dentro.

> **Regla de oro**: da permisos al **nivel más bajo posible** que cumpla la necesidad. Más granular = más seguro.

En People Analytics esto es crítico porque manejas datos personales bajo GDPR. Un permiso mal concedido puede exponer salarios, IBANs, evaluaciones de desempeño o información médica.

---

## 2. La jerarquía completa

```
Organización (toda la empresa)
   └── Carpeta (un departamento)
       └── Proyecto (una iniciativa)
           └── Dataset (una "carpeta de tablas")  ← granularidad recomendada
               └── Tabla (la tabla en sí)
                   └── Columna (Policy Tags)
                       └── Fila (Row-level security)
```

### Qué significa cada nivel

| Nivel | Cuándo aplicarlo |
|---|---|
| **Organización** | Casi nunca. Solo roles transversales (auditoría, billing) |
| **Carpeta** | Permisos por departamento (Finanzas, RRHH, IT) |
| **Proyecto** | ⚠️ Peligroso para People Analytics — da acceso a TODO |
| **Dataset** | ✅ **Granularidad recomendada por defecto** |
| **Tabla** | Para casos específicos donde una tabla es más sensible |
| **Columna** | Para campos PII dentro de tablas mixtas (`gross_salary`, `iban`) |
| **Fila** | Cuando un usuario solo puede ver sus propios registros |

### Ejemplo concreto: por qué no a nivel proyecto

Imagina que tu proyecto `people-analytics-formacion` contiene:

```
proyecto/
├── silver_personio              ← incluye salarios
├── silver_personio_payroll      ← nómina detallada (súper sensible)
├── gold_people_analytics        ← métricas agregadas seguras
└── sandbox_carlos               ← experimentos personales
```

Si das `roles/bigquery.dataViewer` **a nivel proyecto** a una HRBP, puede leer:
- ✅ Métricas agregadas (lo que necesita)
- ❌ Salarios individuales (no debería)
- ❌ Nómina con IBANs
- ❌ Tu sandbox personal

**Catástrofe legal** (GDPR Art. 32 — seguridad del tratamiento).

> **Regla práctica**: roles a nivel dataset, nunca proyecto, salvo casos justificados.

---

## 3. Los 5 roles que usas el 95% del tiempo

BigQuery tiene 50+ roles. En la práctica solo necesitas dominar estos:

| Rol | Equivalente humano | Para quién |
|---|---|---|
| `roles/bigquery.dataViewer` | "Puedes leer datos y schemas" | Analistas, dashboards |
| `roles/bigquery.dataEditor` | "Puedes leer + crear/modificar tablas" | Data engineers junior |
| `roles/bigquery.dataOwner` | "Lo anterior + gestionar IAM" | Data engineers senior, DPO |
| `roles/bigquery.jobUser` | "Puedes ejecutar queries" | Todos los que consultan |
| `roles/bigquery.metadataViewer` | "Ves qué tablas existen pero no su contenido" | Auditores, compliance |

### Detalle no obvio: necesitas DOS roles para leer

Para que alguien pueda hacer `SELECT * FROM tabla`, necesita **ambos**:

1. `dataViewer` → permiso de lectura sobre los datos
2. `jobUser` → permiso de ejecutar queries

Es como necesitar **entrada al cine** (`dataViewer`) **y dinero para la entrada** (`jobUser`). Sin ambos, no entras.

```
Usuario tiene dataViewer pero NO jobUser
  → "Permission denied: User does not have bigquery.jobs.create permission"

Usuario tiene jobUser pero NO dataViewer
  → "Permission denied: User does not have access to the table"
```

### Quién paga por qué

- **`dataViewer`**: no implica coste, solo acceso
- **`jobUser`**: el usuario paga las queries que lanza desde su proyecto

> **Patrón común**: `dataViewer` en el proyecto donde están los datos + `jobUser` en el proyecto del usuario (que paga su consumo).

---

## 4. Authorized Views — el patrón fundamental de People Analytics

### El problema que resuelve

**Caso real**: una HRBP necesita ver compa-ratio por país y banda para hacer su trabajo. Pero **no debe ver salarios individuales** (GDPR + política interna).

¿Cómo le das **uno sin el otro**?

### La solución: vista con permisos especiales

Una **authorized view** es una vista SQL que tiene un "pase de cocina": puede leer datasets a los que el usuario que la consulta no tiene acceso directo.

```
┌─────────────────────────────────────────────────────────────┐
│ silver_personio (datos sensibles)                           │
│   ├── fact_payroll_monthly (incluye gross_salary)          │
│   └── dim_employee                                          │
│                                                             │
│   Permisos:                                                 │
│     - data-engineering@: dataEditor                         │
│     - HRBP: ❌ NO TIENE ACCESO                              │
│     - v_compa_ratio_cohort: ✅ AUTHORIZED (puede leer)      │
└─────────────────────────────────────────────────────────────┘
                          ▲
                          │ lee a través de la vista autorizada
                          │
┌─────────────────────────────────────────────────────────────┐
│ gold_people_analytics (datos agregados seguros)             │
│   └── v_compa_ratio_cohort  ← LA VISTA                      │
│       (es solo SQL, no almacena datos)                      │
│                                                             │
│   Permisos:                                                 │
│     - HRBP: dataViewer ✅                                   │
└─────────────────────────────────────────────────────────────┘
                          ▲
                          │ consulta la vista
                          │
                  ┌───────────────┐
                  │ HRBP España   │
                  └───────────────┘
```

### Implementación paso a paso

**Paso 1**: crear la vista con k-anonymity

```sql
CREATE OR REPLACE VIEW gold_people_analytics.v_compa_ratio_cohort AS
SELECT
  country, 
  band,
  COUNT(*) AS headcount,
  AVG(SAFE_DIVIDE(gross_salary, band_midpoint)) AS avg_compa_ratio,
  APPROX_QUANTILES(
    SAFE_DIVIDE(gross_salary, band_midpoint), 100
  )[OFFSET(50)] AS median_compa_ratio
FROM silver_personio.fact_payroll_monthly p
JOIN silver_personio.dim_employee e USING(employee_code)
WHERE payroll_month = (
  SELECT MAX(payroll_month) 
  FROM silver_personio.fact_payroll_monthly
)
GROUP BY country, band
HAVING COUNT(*) >= 5;   -- ← k-anonymity, obligatoria
```

**Paso 2**: autorizar la vista en el dataset sensible

```python
from google.cloud import bigquery
client = bigquery.Client()

# Obtenemos el dataset que CONTIENE los datos sensibles
source = client.get_dataset("people-analytics-formacion.silver_personio")

# Creamos la "entrada de acceso" tipo "view"
view_ref = bigquery.AccessEntry(
    role=None,                    # ← NULL porque es autorización de vista
    entity_type="view",
    entity_id={
        "projectId": "people-analytics-formacion",
        "datasetId": "gold_people_analytics",
        "tableId": "v_compa_ratio_cohort",
    },
)

# Añadimos la entrada a la lista de accesos
source.access_entries = list(source.access_entries) + [view_ref]
client.update_dataset(source, ["access_entries"])
```

**Paso 3**: dar acceso a la HRBP al dataset de la vista

```python
# Obtenemos el dataset PÚBLICO (donde vive la vista)
gold = client.get_dataset("people-analytics-formacion.gold_people_analytics")

# Creamos entrada de acceso para la HRBP
hrbp_access = bigquery.AccessEntry(
    role="roles/bigquery.dataViewer",
    entity_type="userByEmail",
    entity_id="hrbp-spain@empresa.com",
)

gold.access_entries = list(gold.access_entries) + [hrbp_access]
client.update_dataset(gold, ["access_entries"])
```

### Qué ve la HRBP cuando entra

1. En el explorer izquierdo, **solo ve** `gold_people_analytics`. No ve `silver_personio` (no tiene permiso ni para listarlo).
2. Despliega `gold_people_analytics` y ve la vista.
3. Ejecuta:
   ```sql
   SELECT * FROM gold_people_analytics.v_compa_ratio_cohort;
   ```
   ✅ Funciona. Ve agregados por país y banda.
4. Intenta curiosear:
   ```sql
   SELECT * FROM silver_personio.fact_payroll_monthly LIMIT 10;
   ```
   ❌ `Permission denied: Table not found or access denied`.

> **Detalle clave**: BigQuery no dice "no tienes permiso", dice "no encuentro la tabla". Ni siquiera sabe que `silver_personio` existe. Lo que no puedes ver, no puedes atacar.

---

## 5. k-anonymity — la protección obligatoria

### Qué es

k-anonymity garantiza que **ningún registro pueda identificar a una persona** porque siempre va agrupado con otras k-1 personas similares.

Para People Analytics, el estándar mínimo defendible es **k = 5**.

### Implementación en SQL

```sql
SELECT 
  country, 
  gender, 
  age_band,
  COUNT(*) AS headcount,
  AVG(compa_ratio) AS avg_compa
FROM gold_people_analytics.headcount_demographic
GROUP BY country, gender, age_band
HAVING COUNT(*) >= 5;   -- ← nunca grupos < 5 personas
```

### Por qué k = 5 y no k = 3

Imagina que reportas:

> "En España, banda P3, género no binario: 1 persona, salario 67k€"

Acabas de **identificar a alguien**. Aunque no menciones el nombre, el cruce de filtros (España + P3 + género no binario) puede coincidir con una sola persona en la organización.

Con **k = 5**, ese grupo no aparece en absoluto. La HRBP ve solo cohortes "suficientemente grandes para ser anónimas".

### Proxy discrimination

Cuidado con campos que parecen inocuos pero re-identifican:

```sql
-- ⚠️ Postcode + edad + tenure puede identificar a una sola persona
SELECT postcode, age_band, tenure_bucket, ...

-- ⚠️ Manager_code + departamento limita a equipos pequeños
SELECT manager_code, department, ...
```

> **Regla**: cualquier combinación de filtros debe respetar k ≥ 5. Si un filtro reduce el grupo, refuerza el HAVING.

---

## 6. Column-level Security (Policy Tags)

Para tablas que mezclan campos sensibles y no sensibles, puedes restringir **columnas específicas** sin restringir la tabla entera.

### Caso de uso

```
fact_payroll_monthly
─────────────────────────────────────────────────
employee_code | country | band | gross_salary | iban
──────────────┼─────────┼──────┼──────────────┼──────
   PÚBLICO       PÚBLICO   PÚB.   🔒 SENSIBLE   🔒 PII
```

Los analistas pueden ver employee_code, country, band. Solo Finanzas + DPO pueden ver `gross_salary` y `iban`.

### Implementación

**1. Crear Policy Tags en Data Catalog**:

```bash
gcloud data-catalog taxonomies create \
    --location=europe-southwest1 \
    --display-name="PII Taxonomy" \
    --description="Etiquetas de columnas sensibles"
```

**2. Crear los tags**:

```bash
gcloud data-catalog taxonomies policy-tags create \
    --location=europe-southwest1 \
    --taxonomy=PII_Taxonomy \
    --display-name="Salary"
```

**3. Asignar el tag a una columna**:

```sql
ALTER TABLE silver_personio.fact_payroll_monthly
ALTER COLUMN gross_salary
SET OPTIONS (
  policy_tags = ["projects/proyecto/locations/europe-southwest1/taxonomies/123/policyTags/456"]
);
```

**4. Conceder acceso al tag solo a usuarios autorizados**:

```bash
gcloud data-catalog taxonomies policy-tags add-iam-policy-binding \
    POLICY_TAG_ID \
    --member="user:finanzas-lead@empresa.com" \
    --role="roles/datacatalog.categoryFineGrainedReader"
```

### Resultado

```sql
-- Analista sin acceso al tag "Salary"
SELECT employee_code, country, gross_salary
FROM silver_personio.fact_payroll_monthly;
-- ❌ "User does not have permission to access policy tag for column gross_salary"

-- Pero esto sí funciona
SELECT employee_code, country
FROM silver_personio.fact_payroll_monthly;
-- ✅
```

---

## 7. Row-level Security

Para casos donde un usuario **solo puede ver sus propios registros** o los de su equipo.

### Caso de uso típico

Cada manager puede ver datos de **su equipo directo** pero no de otros equipos.

### Implementación

```sql
CREATE ROW ACCESS POLICY manager_sees_own_team
ON silver_personio.dim_employee
GRANT TO ("group:managers@empresa.com")
FILTER USING (manager_code = SESSION_USER());
```

Cuando un manager ejecuta:

```sql
SELECT * FROM silver_personio.dim_employee;
```

BigQuery automáticamente añade el filtro:

```sql
SELECT * FROM silver_personio.dim_employee
WHERE manager_code = SESSION_USER();
```

Sin que el manager lo sepa. **Filtrado invisible y obligatorio**.

### Casos comunes en People Analytics

```sql
-- Cada empleado ve solo sus datos
CREATE ROW ACCESS POLICY employee_sees_self
ON silver_personio.fact_payroll_monthly
GRANT TO ("group:all-employees@empresa.com")
FILTER USING (employee_email = SESSION_USER());

-- HRBP de cada país ve solo su país
CREATE ROW ACCESS POLICY hrbp_sees_country
ON silver_personio.dim_employee
GRANT TO ("user:hrbp-spain@empresa.com")
FILTER USING (country = 'ES');
```

---

## 8. Capa semántica de 3 niveles

El patrón estándar para servir datos seguros a la organización.

```
silver_*.fact_*                       ← transaccional granular (acceso DE only)
       ↓
tabla intermedia materializada        ← refrescada por SP (acceso DE only)
       ↓
gold_*.v_metrica_oficial              ← vista semántica (authorized view)
       ↓
gold_*.v_dashboard_dominio            ← vista por dominio/consumidor
       ↓
[Consumidores: Looker Studio, analistas, HRBPs]
```

### Por qué tres niveles

**Sin capa semántica**, cada analista calcula "headcount" así:

```sql
-- Analista A
SELECT COUNT(DISTINCT employee_code) FROM dim_employee WHERE status='active';

-- Analista B
SELECT COUNT(*) FROM fact_employee_history
WHERE snapshot_date = LAST_DAY(CURRENT_DATE(), MONTH) AND status='active';

-- Analista C: añade fte ponderado
SELECT SUM(fte) FROM fact_employee_history WHERE snapshot_date = ...;
```

**Tres números distintos**. Reunión de 45 minutos discutiendo cuál es "el bueno".

### Con capa semántica

Hay **una** definición oficial:

```sql
CREATE OR REPLACE TABLE gold_people_analytics.headcount_monthly
PARTITION BY snapshot_month
CLUSTER BY country, band
OPTIONS(
  description = "Headcount oficial: empleados activos al último día del mes (FTE ponderado)."
) AS
SELECT
  DATE_TRUNC(snapshot_date, MONTH) AS snapshot_month,
  country, 
  band,
  COUNT(DISTINCT employee_code) AS headcount_persons,
  SUM(fte) AS headcount_fte
FROM silver_personio.fact_employee_history
WHERE status = 'active' 
  AND snapshot_date = LAST_DAY(snapshot_date, MONTH)
GROUP BY snapshot_month, country, band;
```

Todos los consumidores parten de aquí. **Cero discusión**.

---

## 9. Auditoría e inmutabilidad

### Audit Logs — el log inviolable

Cualquier operación en BigQuery se registra automáticamente en **Cloud Audit Logs**:

- Quién ejecutó la query (email)
- Cuándo exactamente (timestamp con ms)
- Qué query (texto SQL completo)
- Sobre qué tabla
- Desde qué IP
- Si tuvo éxito o falló

> **Importante**: los `_Required` audit logs **no se pueden desactivar**. Son obligatorios por diseño de GCP. Esta es la **garantía de trazabilidad** para compliance (SOC 2, GDPR, ISO 27001).

### Consultar audit logs

```sql
SELECT
  timestamp,
  protopayload_auditlog.authenticationInfo.principalEmail AS user,
  protopayload_auditlog.requestMetadata.callerIp AS ip,
  protopayload_auditlog.serviceData_v1_bigquery
    .jobCompletedEvent.job.jobConfiguration.query.query AS sql
FROM `proyecto.global._Required._AllLogs`
WHERE 
  protopayload_auditlog.serviceName = 'bigquery.googleapis.com'
  AND REGEXP_CONTAINS(
    protopayload_auditlog.serviceData_v1_bigquery
      .jobCompletedEvent.job.jobConfiguration.query.query,
    r'(?i)(DROP TABLE|DELETE FROM|gross_salary)'
  )
ORDER BY timestamp DESC;
```

### INFORMATION_SCHEMA.JOBS — auditoría más accesible

```sql
SELECT 
  user_email, 
  query, 
  creation_time,
  total_bytes_processed
FROM `region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE REGEXP_CONTAINS(query, r'(?i)gross_salary|iban|national_id')
  AND creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
ORDER BY creation_time DESC;
```

Cualquier persona con `bigquery.jobs.list` ve quién consultó qué.

---

## 10. Patrón GDPR-compliant para People Analytics

Combinando todo lo anterior, así se organiza un proyecto serio:

```
proyecto-people-analytics/
│
├── bronze_personio                    ← raw, 90 días retención
│   └── Acceso: SA ingesta only
│
├── silver_personio                    ← limpio, 7 años retención
│   └── Acceso: data-engineering@ + authorized views
│
├── silver_personio_payroll            ← nómina (más sensible)
│   └── Acceso: data-engineering-payroll@ + DPO + authorized views
│
├── gold_people_analytics              ← métricas seguras
│   └── Acceso: analistas + HRBPs vía vistas (k-anonymity ≥ 5)
│
├── audit_archive                      ← snapshots para auditoría
│   └── Acceso: solo DPO
│
├── pipeline_runs                      ← logs ejecuciones
│   └── Acceso: SRE + DE
│
└── sandbox_<usuario>                  ← experimentación personal
    └── Acceso: usuario individual, TTL 7 días
```

### Cumplimiento de cada artículo de GDPR

| Artículo GDPR | Cómo se cumple en BigQuery |
|---|---|
| **Art. 5(1)(c)** Minimización | Authorized views con solo columnas necesarias |
| **Art. 5(1)(e)** Limitación plazo | `partition_expiration_days` automático |
| **Art. 5(1)(f)** Integridad/confidencialidad | IAM granular + Policy Tags |
| **Art. 25** Privacy by design | k-anonymity en vistas, datos por defecto agregados |
| **Art. 30** Registro actividades | Audit Logs automáticos |
| **Art. 32** Seguridad del tratamiento | Roles IAM + cifrado en reposo + cifrado en tránsito |
| **Art. 33** Notificación de brechas | Cloud Logging + alertas |

---

## 11. Errores comunes y cómo evitarlos

### Error 1: dar dataOwner cuando bastaba dataViewer

```python
# ❌ MAL: dataOwner permite gestionar IAM (dar permisos a otros)
hrbp = bigquery.AccessEntry(
    role="roles/bigquery.dataOwner",
    entity_type="userByEmail",
    entity_id="hrbp@empresa.com",
)

# ✅ BIEN: dataViewer es suficiente para consultar
hrbp = bigquery.AccessEntry(
    role="roles/bigquery.dataViewer",
    entity_type="userByEmail",
    entity_id="hrbp@empresa.com",
)
```

### Error 2: permisos a usuarios individuales en vez de grupos

```python
# ❌ MAL: si la HRBP cambia, hay que reasignar permisos
entity_type="userByEmail",
entity_id="hrbp-spain@empresa.com"

# ✅ BIEN: grupos de Google Workspace
entity_type="groupByEmail",
entity_id="hrbp-spain-group@empresa.com"
```

Las personas cambian de rol, los grupos se mantienen. Gestionar permisos a nivel grupo es mucho más sostenible.

### Error 3: ignorar k-anonymity en views nuevas

```sql
-- ❌ MAL: una sola persona puede aparecer
CREATE VIEW v_compa_by_band_country AS
SELECT country, band, AVG(gross_salary) AS avg_salary
FROM silver_personio.fact_payroll_monthly
GROUP BY country, band;

-- ✅ BIEN: garantiza k ≥ 5
CREATE VIEW v_compa_by_band_country AS
SELECT country, band, AVG(gross_salary) AS avg_salary
FROM silver_personio.fact_payroll_monthly
GROUP BY country, band
HAVING COUNT(*) >= 5;
```

### Error 4: olvidar jobUser

```python
# ❌ MAL: dataViewer solo no permite ejecutar queries
client.update_dataset(dataset, ["access_entries"])

# ✅ BIEN: también necesitas jobUser a nivel proyecto
gcloud projects add-iam-policy-binding mi-proyecto \
    --member="user:hrbp@empresa.com" \
    --role="roles/bigquery.jobUser"
```

### Error 5: hardcodear permisos en queries

```sql
-- ❌ MAL: lógica de seguridad en la query (alguien puede saltársela)
SELECT * FROM dim_employee
WHERE country = 'ES'   -- "esto es solo para HRBP de España"

-- ✅ BIEN: lógica de seguridad en la base de datos
CREATE ROW ACCESS POLICY hrbp_spain_sees_spain
ON dim_employee
GRANT TO ("user:hrbp-spain@empresa.com")
FILTER USING (country = 'ES');
```

---

## 12. Checklist de seguridad para tu próximo dataset

Antes de exponer un dataset nuevo a la organización, verifica:

```
☐ Permisos a nivel dataset (NO a nivel proyecto)
☐ Roles asignados a grupos (NO a usuarios individuales)
☐ Vistas con HAVING COUNT(*) >= 5 si exponen demografía
☐ Authorized view configurada si lee de datasets sensibles
☐ Policy Tags en columnas PII (salary, IBAN, national_id)
☐ Row-level security si aplica filtrado por dueño
☐ Documentación en description del dataset (DPO contact, retention)
☐ Labels (team, env, contains_pii) para FinOps
☐ Audit log query lista para "quién accedió a esto último mes"
☐ TTL configurado si es dataset temporal/sandbox
```

---

## 13. Resumen ejecutivo para clase

### Los 4 conceptos que tu alumno debe llevarse

1. **Granularidad dataset**: permisos siempre a nivel dataset, nunca proyecto. Salvo casos justificados.

2. **Authorized views**: el patrón fundamental para servir datos sensibles. Vista en gold con permiso especial para leer silver.

3. **k-anonymity ≥ 5**: nunca exponer grupos demográficos con menos de 5 personas. `HAVING COUNT(*) >= 5` obligatorio.

4. **Audit logs inmutables**: todo queda registrado. Esta es la garantía de cumplimiento normativo.

### El error más común

> "Le doy dataOwner al equipo de analistas para que tengan flexibilidad."

dataOwner permite gestionar IAM. Estás dando permiso para que cualquier analista conceda acceso a otros. Catástrofe.

> **Regla**: dataOwner solo a data engineers senior + DPO. Resto: dataViewer/dataEditor según necesidad.

### Para tu sandbox del curso

En entornos formativos puedes ser más relajado, pero **enseña los patrones correctos**. Aunque en clase el alumno tenga `dataOwner` en su sandbox personal, debe entender que en producción no se hace así.

---

## Anexo: comandos de referencia rápida

### Listar quién tiene acceso a un dataset

```python
from google.cloud import bigquery
client = bigquery.Client()

dataset = client.get_dataset("proyecto.silver_personio")
for entry in dataset.access_entries:
    print(f"{entry.entity_type}: {entry.entity_id} → {entry.role}")
```

### Añadir un grupo con dataViewer

```python
new_entry = bigquery.AccessEntry(
    role="roles/bigquery.dataViewer",
    entity_type="groupByEmail",
    entity_id="people-analytics-team@empresa.com",
)
dataset.access_entries = list(dataset.access_entries) + [new_entry]
client.update_dataset(dataset, ["access_entries"])
```

### Revocar acceso

```python
dataset.access_entries = [
    entry for entry in dataset.access_entries
    if entry.entity_id != "ex-empleado@empresa.com"
]
client.update_dataset(dataset, ["access_entries"])
```

### Ver row access policies de una tabla

```sql
SELECT
  table_name,
  row_access_policy_name,
  grantees,
  filter_predicate
FROM `proyecto.silver_personio.INFORMATION_SCHEMA.ROW_ACCESS_POLICIES`
WHERE table_name = 'dim_employee';
```

### Crear vista autorizada (UI fácil)

En la consola de BigQuery:

1. Click en el dataset que contiene la vista (ej: `gold_people_analytics`)
2. Click en la vista (ej: `v_compa_ratio_cohort`)
3. Botón **"Share"** arriba a la derecha
4. Pestaña **"Authorize view"**
5. Selecciona el dataset que la vista debe poder leer (ej: `silver_personio`)
6. Save

Hace lo mismo que el código Python pero por UI.

### Buscar columnas PII en todo el proyecto

```sql
SELECT 
  table_schema,
  table_name,
  column_name,
  data_type
FROM `region-eu`.INFORMATION_SCHEMA.COLUMNS
WHERE LOWER(column_name) IN (
  'gross_salary', 'salary', 'iban', 'national_id', 'dni',
  'passport', 'birth_date', 'home_address', 'phone_number'
)
ORDER BY table_schema, table_name;
```

Output: lista de todas las columnas sensibles del proyecto. Útil para auditorías de DPO.
