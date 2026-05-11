# Tiers de Storage en Google Cloud Platform

Material de clase · Sesión 4 · Curso BigQuery + Dataform · People Analytics

---

## 1. La idea fundamental

Google Cloud ofrece **8 opciones de almacenamiento** distintas (entre BigQuery y Cloud Storage), cada una con un perfil de precio/acceso diferente. Elegir bien puede dividir tu factura por 16x. Elegir mal puede multiplicarla.

> **Regla mental**: no existe "el storage barato" universalmente. Existe el storage adecuado para **cómo vas a usar el dato**.

Las tres variables que definen la decisión:

1. **Frecuencia de acceso**: ¿lo lees a diario o una vez al año?
2. **Latencia tolerable**: ¿necesitas respuesta inmediata o puedes esperar?
3. **Tipo de consulta**: ¿SQL directo o procesamiento batch?

---

## 2. Las dos familias de storage

### BigQuery Storage (datos estructurados, queryables)

Para tablas con schema, accesibles vía SQL. Cuatro variantes según activo/long-term y logical/physical billing.

### Google Cloud Storage (GCS) (archivos crudos)

Para archivos en cualquier formato (CSV, Parquet, JSON, imágenes, PDFs). Cuatro tiers según frecuencia de acceso esperada.

---

## 3. Tabla completa de tiers — Precios reales

> Precios en `europe-southwest1` (Madrid), USD/GB/mes. Tomar como referencia comparativa relativa, los precios cambian con el tiempo.

| # | Opción | Precio/GB·mes | Acceso SQL | Latencia |
|---|---|---|---|---|
| 1 | BigQuery Active Logical | $0.020 | ✅ Inmediato | ms |
| 2 | BigQuery Active Physical | $0.040 | ✅ Inmediato | ms |
| 3 | GCS Standard | $0.020 | Vía external table | ms |
| 4 | BigQuery Long-term Logical | $0.010 | ✅ Inmediato | ms |
| 5 | BigQuery Long-term Physical | $0.020 | ✅ Inmediato | ms |
| 6 | GCS Nearline | $0.010 | Vía external table | ms |
| 7 | GCS Coldline | $0.004 | Vía external table | ms |
| 8 | GCS Archive | $0.0012 | Vía external table | ms |

**Observación importante**: todos los tiers de GCS (incluido Archive) tienen latencia de milisegundos. A diferencia de Azure Archive, **no necesitas "rehidratar" datos en GCP**. La diferencia entre tiers es de **precio**, no de **velocidad**.

---

## 4. Concepto clave 1: Long-term Storage automático

BigQuery aplica un **descuento automático del 50%** a tablas que no se modifican en 90 días. Sin que hagas nada.

```
Día 0:    Creas tabla → Active storage ($0.02/GB/mes)
Día 1-89: Active storage ($0.02/GB/mes)
Día 90+:  Long-term storage ($0.01/GB/mes) ← AUTOMÁTICO
```

### Qué cuenta como "tocar" la tabla

| Operación | ¿Resetea contador? |
|---|---|
| `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `TRUNCATE` | ✅ Sí |
| Streaming inserts | ✅ Sí |
| `COPY` con destino esta tabla | ✅ Sí |
| `SELECT` (cualquier cantidad) | ❌ No |
| `CREATE VIEW` que la referencia | ❌ No |
| Snapshots o clones | ❌ No |
| Renombrar la tabla | ❌ No |

### Aplicación por partición

Para tablas particionadas, **long-term se aplica partición por partición**, no a toda la tabla:

```
fact_payroll_monthly (particionada por payroll_month)
  ├── 2024-01 → no modificada en 90+ días → long-term ($0.01/GB) ✅
  ├── 2024-12 → no modificada en 90+ días → long-term ($0.01/GB) ✅
  └── 2025-12 → modificada ayer → active ($0.02/GB)
```

> **Implicación práctica**: las tablas históricas con particiones por fecha se abaratan automáticamente sin necesidad de mover datos.

---

## 5. Concepto clave 2: Physical vs Logical billing

BigQuery permite elegir cómo factura el storage. La decisión se toma **a nivel dataset**.

```sql
-- Cambiar a physical billing
ALTER SCHEMA mi_dataset
SET OPTIONS(storage_billing_model = 'PHYSICAL');

-- O en la creación
CREATE SCHEMA mi_dataset
OPTIONS(storage_billing_model = 'PHYSICAL');
```

### Comparativa

| Dimensión | Logical | Physical |
|---|---|---|
| Precio Active | $0.020/GB | $0.040/GB |
| Precio Long-term | $0.010/GB | $0.020/GB |
| Qué se factura | Bytes lógicos (sin comprimir) | Bytes físicos (comprimidos) |
| Snapshots | Cuentan como duplicación | Comparten físicos (CoW) |
| Time travel | No se factura | Sí se factura |
| Bytes obsoletos | No se facturan | Sí se facturan hasta GC |

### El cálculo numérico que sorprende

BigQuery comprime con **Capacitor** con ratios típicos de **6-10x**. Para una tabla de 10 GB lógicos:

```
Logical billing:  10 GB × $0.02 = $0.20/mes
Physical billing: 1.66 GB × $0.04 = $0.066/mes   ← 3x más barato
```

> **Regla práctica**: para datos típicos (tablas analíticas con compresión decente), **physical billing gana**.

### Restricciones

- Una vez activado physical, **no puedes volver a logical durante 14 días**
- Physical incluye time travel y bytes pendientes de garbage collection
- Si tu tabla tiene mucho UPDATE/DELETE, physical puede salir más caro

---

## 6. Concepto clave 3: Tiers de GCS y lifecycle

GCS tiene 4 tiers con la lógica: **menor precio de storage = mayor precio de retrieval**.

| Tier | Storage/GB | Retrieval/GB | Duración mínima |
|---|---|---|---|
| Standard | $0.020 | $0 | 0 días |
| Nearline | $0.010 | $0.01 | 30 días |
| Coldline | $0.004 | $0.02 | 90 días |
| Archive | $0.0012 | $0.05 | 365 días |

### Trampa común: duración mínima

Si subes 100 GB a Archive y los borras al día siguiente, **te facturan como si los hubieras tenido 365 días**. Esto evita abuso del tier barato.

### Lifecycle policy automática

GCS puede mover archivos entre tiers automáticamente según edad:

```json
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "ARCHIVE"},
        "condition": {"age": 90}
      },
      {
        "action": {"type": "Delete"},
        "condition": {"age": 2555}
      }
    ]
  }
}
```

Resultado:
- Días 0-30: Standard (accedes fácil)
- Días 30-90: pasa a Coldline automáticamente
- Días 90+: pasa a Archive automáticamente
- Día 2555 (7 años): se borra automáticamente

---

## 7. Jerarquía real de precios (con compresión 6x asumida)

Para **10 GB lógicos** durante un mes, coste efectivo:

| Posición | Opción | Coste real |
|---|---|---|
| 1 (más barato) | **GCS Archive** | $0.012 |
| 2 | **BigQuery Long-term Physical** | $0.033 |
| 3 | **GCS Coldline** | $0.040 |
| 4 | **BigQuery Active Physical** | $0.066 |
| 5 | **BigQuery Long-term Logical** | $0.100 |
| 6 | **GCS Nearline** | $0.100 |
| 7 | **BigQuery Active Logical** | $0.200 |
| 8 (más caro) | **GCS Standard** | $0.200 |

### Insight contraintuitivo

**BigQuery Long-term Physical ($0.033) es más barato que GCS Coldline ($0.040)** y mantiene acceso SQL directo. Mucha gente migra a GCS pensando que ahorra, y a veces hace lo contrario.

---

## 8. Matriz de decisión por escenario

### Escenario A — Tablas activas diarias

**Recomendación**: BigQuery Active Physical con `storage_billing_model = 'PHYSICAL'`

**Por qué**: compresión maximiza ratio precio/acceso. $0.066/mes por 10 GB con SQL instantáneo.

### Escenario B — Tablas históricas, consulta ocasional

**Recomendación**: BigQuery Active Physical. Dejar que pase a Long-term automáticamente.

**Por qué**: tras 90 días, BigQuery te baja el precio a la mitad sin que muevas datos. **Mejor que Coldline y con SQL directo**.

### Escenario C — Snapshots de auditoría con retención larga

**Recomendación**: Snapshot BigQuery + Physical billing.

**Por qué**: con physical billing, los snapshots solo facturan los bytes que diverjan (Copy-on-Write). Si la tabla original cambia poco, el snapshot ocupa físicamente casi nada.

### Escenario D — Datos verdaderamente fríos (compliance 7+ años)

**Recomendación**: Export a GCS Archive + lifecycle a Delete.

**Por qué**: la diferencia económica importa con volúmenes grandes.

**Ejemplo 100 GB durante 7 años**:
- BigQuery long-term physical: $27.72
- GCS Archive: $1.01 → **ahorro 25x**

### Escenario E — Limpieza del explorer manteniendo recuperabilidad

**Opción 1** (mover a archive dataset):
```sql
ALTER SCHEMA carlos_archive
SET OPTIONS(storage_billing_model = 'PHYSICAL');
```
Tablas pasan a long-term automáticamente tras 90 días.

**Opción 2** (export a GCS Coldline):
```bash
gcloud storage buckets create gs://carlos-archive \
    --default-storage-class=COLDLINE \
    --location=europe-southwest1
```

---

## 9. Costes ocultos que la tabla no muestra

### Costes de retrieval en GCS frío

Cada lectura desde Coldline/Archive cuesta dinero. Para 30 lecturas/año de 10 GB:

```
Storage Archive: 10 GB × $0.0012 × 12 = $0.144
Retrieval:       30 × 10 GB × $0.05 = $15.00
TOTAL:           $15.14/año           ← el retrieval mata el ahorro
```

> **Regla**: Archive solo tiene sentido cuando consultas <1 vez al año.

### Operaciones GCS

GCS factura por número de operaciones (PUT, GET, LIST):

| Tier | Por 10K operaciones |
|---|---|
| Standard | $0.05 |
| Coldline | $0.10 |
| Archive | $0.50 |

Para checkpoints normales es despreciable. Para sistemas con millones de archivos pequeños puede sumar.

### Costes cross-region

Si tu BigQuery está en `europe-southwest1` y tu GCS en `us-central1`, hay transferencia inter-región ($0.01-0.12/GB).

> **Lección**: pon todo en la misma región.

---

## 10. La regla de oro decisional

```
¿Vas a consultar la tabla en los próximos 6 meses?
│
├── SÍ, frecuentemente
│   └── → BigQuery Physical en dataset principal
│
├── SÍ, ocasionalmente
│   └── → BigQuery Physical en dataset "archive" 
│       (long-term automático tras 90d)
│
├── NO, pero podría
│   └── → BigQuery Physical en dataset "archive"
│       (sigue siendo competitivo si la dejas tranquila)
│
└── NO, casi nunca
    │
    ├── Volumen < 100 GB
    │   └── → BigQuery sigue ganando, no compliques
    │
    ├── Volumen 100 GB - 1 TB
    │   └── → GCS Coldline, lifecycle a Archive tras 1 año
    │
    └── Volumen > 1 TB
        └── → GCS Archive directo + lifecycle delete
            tras retención legal
```

---

## 11. Setup recomendado para sandbox/experimentación

Para un entorno de curso o exploración:

```python
from google.cloud import bigquery
client = bigquery.Client()
PROJECT_ID = "people-analytics-formacion"

# Sandbox: TTL agresivo, logical billing (más simple)
sandbox = bigquery.Dataset(f"{PROJECT_ID}.sandbox_carlos")
sandbox.location = "europe-southwest1"
sandbox.default_table_expiration_ms = 7 * 24 * 60 * 60 * 1000  # 7 días
sandbox.labels = {"team": "people-analytics", "env": "sandbox"}
client.create_dataset(sandbox, exists_ok=True)

# Scratch: sin TTL, physical billing (medio plazo)
scratch = bigquery.Dataset(f"{PROJECT_ID}.scratch_carlos")
scratch.location = "europe-southwest1"
scratch.labels = {"team": "people-analytics", "env": "scratch"}
client.create_dataset(scratch, exists_ok=True)
client.query(f"ALTER SCHEMA `{PROJECT_ID}.scratch_carlos` SET OPTIONS(storage_billing_model = 'PHYSICAL')").result()

# Archive: para experimentos antiguos que ya no consultas
archive = bigquery.Dataset(f"{PROJECT_ID}.archive_carlos")
archive.location = "europe-southwest1"
archive.labels = {"team": "people-analytics", "env": "archive"}
client.create_dataset(archive, exists_ok=True)
client.query(f"ALTER SCHEMA `{PROJECT_ID}.archive_carlos` SET OPTIONS(storage_billing_model = 'PHYSICAL')").result()
```

Flujo operativo:

```
sandbox_carlos      → TTL 7 días, todo expira solo
       ↓ (mover lo valioso)
scratch_carlos      → sin TTL, accedes frecuente
       ↓ (mover lo dormido)
archive_carlos      → sin TTL, long-term tras 90d
       ↓ (solo si volumen y compliance lo justifican)
GCS Coldline/Archive
```

---

## 12. Resumen ejecutivo para clase

### Los 3 conceptos que tu alumno debe llevarse

1. **Long-term automático en BigQuery**: tablas sin tocar 90 días pagan la mitad. Aplica por partición.

2. **Physical billing**: en datos con compresión típica (6x), sale 3x más barato. Activar a nivel dataset.

3. **GCS tiers**: 4 tiers con storage barato + retrieval caro. Latencia siempre en ms. Lifecycle policies automatizan transiciones.

### El error más común

> "Voy a mover todo a GCS Coldline para ahorrar."

Suele ser peor que dejarlo en BigQuery con Physical billing + long-term automático. Solo es claramente mejor con TB+ que no consultas casi nunca.

### Para tu sandbox del curso

Para volúmenes < 100 GB de experimentación: **BigQuery Physical billing en datasets organizados (sandbox/scratch/archive)** te da el mejor compromiso entre coste, acceso SQL y limpieza del explorer. No te metas en GCS salvo que tengas razones específicas (portabilidad, compliance, volumen grande).

---

## Anexo: comandos de referencia rápida

### Cambiar billing model de un dataset

```sql
ALTER SCHEMA mi_dataset
SET OPTIONS(storage_billing_model = 'PHYSICAL');
```

### Crear bucket GCS con tier por defecto

```bash
gcloud storage buckets create gs://mi-bucket \
    --location=europe-southwest1 \
    --default-storage-class=COLDLINE \
    --uniform-bucket-level-access
```

### Aplicar lifecycle policy

```bash
gcloud storage buckets update gs://mi-bucket \
    --lifecycle-file=lifecycle.json
```

### Ver storage físico vs lógico de tus tablas

```sql
SELECT
  table_schema,
  table_name,
  ROUND(total_logical_bytes / POW(1024, 3), 2) AS gb_logical,
  ROUND(total_physical_bytes / POW(1024, 3), 2) AS gb_physical,
  ROUND(total_logical_bytes / NULLIF(total_physical_bytes, 0), 1) AS compression_ratio
FROM `region-eu`.INFORMATION_SCHEMA.TABLE_STORAGE
ORDER BY total_logical_bytes DESC
LIMIT 20;
```

### Export a GCS desde BigQuery

```python
job_config = bigquery.ExtractJobConfig(
    destination_format="PARQUET",
    compression="SNAPPY"
)

extract_job = client.extract_table(
    "proyecto.dataset.tabla",
    "gs://mi-bucket/checkpoints/tabla-*.parquet",
    job_config=job_config
)
extract_job.result()
```

### Import desde GCS a BigQuery

```python
job_config = bigquery.LoadJobConfig(
    source_format=bigquery.SourceFormat.PARQUET,
    write_disposition="WRITE_TRUNCATE"
)

load_job = client.load_table_from_uri(
    "gs://mi-bucket/checkpoints/tabla-*.parquet",
    "proyecto.dataset.tabla_restaurada",
    job_config=job_config
)
load_job.result()
```
