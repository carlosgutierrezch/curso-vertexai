# Sesión 5 — Backup-as-Code

**Módulo 9 (Integración con GitHub) + Módulo 10 (Backups y Recuperación)**
Curso GCP + Vertex AI para People Analytics · Imagina Formación

---

## La idea que articula la sesión

> **Tu estrategia de respaldo es código. Código que vive en Git, lo revisan tus pares y lo audita un DPO. Si vive en una wiki o en la cabeza de alguien, no es una estrategia: es una pirueta.**

Esta sesión une dos temas que normalmente se enseñan por separado porque son la misma pieza vista desde dos lados:

- **M9** te da el dónde y el cómo se cambia la política (Git, PR, CI, branch protection).
- **M10** te da el qué política se aplica (snapshots, time travel, exports, retención).

Sin M9, M10 son comandos sueltos que cualquiera puede ejecutar mal un viernes a las seis. Sin M10, M9 es un repo vacío con buenas intenciones.

---

# Parte 1 · El problema que justifica la fusión

---

## Slide 1 — La pregunta incómoda

**¿Dónde vive HOY tu política de retención de BigQuery?**

Respuestas típicas en clientes reales:

- 🟥 "En Confluence, creo que la actualizamos hace dos años"
- 🟥 "El DPO la lleva, está en un Word"
- 🟥 "Está en el código del pipeline, embebida"
- 🟥 "No tenemos una, asumimos que BigQuery hace algo"
- 🟩 "En el repo, en `backups/policies/RETENTION.md`, firmada por DPO vía CODEOWNERS, validada por CI"

Solo la última es operable. El resto son ilusiones de control.

> **Definición práctica de "operable"**: alguien que entra hoy al equipo puede reproducir, auditar y reactivar la política sin entrevistar a tres personas.

---

## Slide 2 — El caso real que vamos a evitar

**Anécdota compuesta (basada en incidentes públicos)**:

```
Lunes 09:14   Analista hace ALTER TABLE … SET OPTIONS(partition_expiration_days=0)
              "para limpiar lo viejo y bajar la factura"
Lunes 09:15   BigQuery comienza a borrar particiones > 0 días
Lunes 14:30   HRBP no puede consultar Q1
Lunes 14:31   Time travel = 7 días por defecto, pero
              el cambio retroactivo de retention NO se cubre
              porque la partición ya no existe técnicamente
Martes 03:00  Backup automático corre sobre tabla casi vacía
Miércoles     DPO firma incident report
```

**Coste del incidente**: 8 meses de histórico de payroll irrecuperables. Auditoría externa rechaza el cierre anual.

**Causa raíz NO técnica**: nadie revisó el cambio. Si hubiera pasado por un Pull Request con CODEOWNERS=`@dpo`, no habría ocurrido.

---

## Slide 3 — La propuesta: Backup-as-Code

Tres principios:

1. **Todo lo operativo es un fichero**: script SQL, política `.md`, workflow `.yml`. Si no es un fichero, no se versiona, no existe.
2. **Todo cambio pasa por revisión**: PR + CODEOWNERS + CI verde. Nadie cambia retention en producción solo.
3. **Todo se prueba mensualmente**: el restore que nunca se prueba no funciona el día que importa.

Lo que conseguimos al final de la sesión:

- Un repo `people-analytics-ops` con el código de M10 versionado
- Un PR con CODEOWNERS sobre `backups/policies/`
- Un Cloud Build (o GitHub Actions) que valida SQL antes de merge
- Snapshots reales sobre `predictions_retention.retention_actions` (la tabla que generamos en Sesión 3)
- Recuperación demostrada por 3 vías diferentes con sus costes comparados

---

# Parte 2 · Git como infraestructura, no como herramienta

---

## Slide 4 — Por qué Dataform es nativamente Git

Dataform (que usaste en Sesión 4 para `dim_employee_scd2`) **no es una herramienta que opcionalmente usa Git**. Su modelo mental ES Git:

| Concepto Dataform | Concepto Git |
|---|---|
| Workspace personal | Branch en local |
| Compile + Run del workspace | Test antes de commitear |
| Push del workspace | `git push` |
| Release config | Tag (`v1.2.0`) |
| Schedule sobre release config | CI/CD que ejecuta el tag |

Implicación: el día que entendiste M8 (Dataform), entendiste GitOps aplicado a datos. Solo te falta nombrarlo.

> **Mensaje para el alumno**: si en Sesión 4 ejecutaste un workspace y viste cambios, ya operaste un branch. No estás aprendiendo Git desde cero, estás formalizando algo que ya hiciste.

---

## Slide 5 — El flujo realista de un equipo de datos

```
                       ┌──────────────────┐
                       │     main         │  ← protegida, solo PR
                       │  (= producción)  │
                       └──────▲───────────┘
                              │ PR + 1 review + CI green
                       ┌──────┴───────────┐
                       │    develop       │  ← integradora
                       └──────▲───────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
      feature/snapshot   feature/retention   feature/restore-test
       (Carlos)         (Lucía)            (Ana)
```

**Reglas mínimas defendibles**:

- `main` no acepta push directo, solo merge desde PR aprobado
- Cada `feature/*` parte de `develop`, no de `main`
- Tag semántico sobre `main` cuando hay release (`v1.0.0`, `v1.1.0`)
- Hotfix: branch directo de `main`, merge a `main` Y a `develop`

> **Anti-patrón observado**: ramas que viven más de 2 semanas. Si tu feature no se mergea en 10 días, el problema es el alcance, no Git.

---

## Slide 6 — El Pull Request como gate técnico Y de compliance

Un PR no es "donde pides que te revisen el código". Es **el sitio donde una decisión queda registrada para siempre**.

En People Analytics, esto importa porque:

| Cambio | Quién debe firmar | Cómo se garantiza |
|---|---|---|
| SQL de transformación nuevo | Data Engineer senior | `CODEOWNERS`: `dataform/ @data-eng-team` |
| Cambio en retention de tabla con PII | DPO | `CODEOWNERS`: `backups/policies/ @dpo` |
| Nueva vista expuesta a Looker | Product analyst lead | `CODEOWNERS`: `dataform/definitions/gold/ @analytics-lead` |
| Cambio en CI/CD | DevOps + DE lead | `CODEOWNERS`: `.github/ @devops @data-eng-lead` |

Cuando el auditor pregunte "¿quién aprobó este cambio en retention?", la respuesta es un link a un PR con timestamp, no "creo que el DPO dijo OK por Slack".

---

## Slide 7 — Branch protection rules que importan

En GitHub → Settings → Branches → Add rule sobre `main`:

```
☑ Require a pull request before merging
   ☑ Require approvals: 1 (2 si el repo toca PII)
   ☑ Dismiss stale pull request approvals when new commits are pushed
   ☑ Require review from CODEOWNERS

☑ Require status checks to pass before merging
   ☑ Require branches to be up to date
   Required checks: ci/dataform-validate, ci/sql-lint, ci/backup-policy-check

☑ Require conversation resolution before merging

☑ Require linear history             ← evita merge commits espagueti

☑ Do not allow bypassing the above settings   ← incluso a admins
☐ Allow force pushes                          ← NO
☐ Allow deletions                             ← NO
```

> **El check que más vale**: `Require review from CODEOWNERS`. Sin él, alguien puede aprobar un cambio sobre la política de retención sin que el DPO se entere.

---

## Slide 8 — Anti-patrón: Git como "guardar archivos"

Síntomas de que tu equipo usa Git como Dropbox:

- Commits con mensaje `update`, `cambios`, `wip`, `.`
- Branches `pruebas-juan`, `nuevo`, `final`, `final2`, `final-definitivo`
- Squash de 47 commits con título genérico
- Nadie lee diffs en los PR, todos dicen "LGTM"
- Reverts son `git revert` ciegos, no análisis de causa

Síntomas de que tu equipo usa Git como **registro de decisiones**:

- Mensaje de commit explica el porqué, no el qué (el qué está en el diff)
- Cada PR responde a un issue/ticket trazable
- Squash limpio: 1 PR = 1 unidad lógica de cambio
- Reverts tienen postmortem adjunto
- `git log` se lee como una crónica del producto

> **Métrica casera**: si abres `git log --oneline | head -50` y entiendes la evolución del proyecto, vas bien. Si parece ruido, tienes un problema cultural antes que técnico.

---

# Parte 3 · CI/CD aplicado a People Analytics

---

## Slide 9 — Qué valida un CI honesto antes del merge

Un CI que se merece la `R` de "Required" hace **al menos** estas cuatro cosas:

```
1. Lint SQL          → sqlfluff lint dataform/definitions/**/*.sqlx
                       Detecta SELECT *, falta de alias, naming inconsistente

2. Dry-run Dataform  → dataform compile && dataform dry-run
                       BigQuery valida el SQL sin facturar bytes

3. Test assertions   → dataform test
                       Las assertions de S4 (uniqueKey, rowConditions) corren

4. Policy check      → custom: grep que `partition_expiration_days` < 90
                       en cualquier tabla con label `contains_pii=true`
                       falla el build
```

> **El cuarto check es el que nadie pone y el que más vale**. Convierte una política escrita en humano ("retención mínima 90 días para PII") en una **regla ejecutable**. Si alguien intenta subirla a 30, el CI rojo se lo dice antes que el DPO.

---

## Slide 10 — GitHub Actions vs Cloud Build

| Dimensión | GitHub Actions | Cloud Build |
|---|---|---|
| Donde corre | Runners de GitHub (o self-hosted) | Workers de GCP |
| Auth a GCP | Workload Identity Federation (recomendado) o SA key | Service Account nativo |
| Coste | 2000 min/mes gratis en repos privados | Primeros 120 min/día gratis |
| Trigger | Push, PR, schedule, manual | Igual + Pub/Sub + Cloud Build trigger |
| Logs | En GitHub UI | Cloud Logging |
| Visibilidad | Mezclado con PRs y issues | Separado del repo |

**Cuándo usar GH Actions**:
- Repo público o team distribuido fuera de GCP
- Quieres todo en un sitio (PRs + CI)
- Necesitas matrices de versiones (Python 3.9, 3.10, 3.11)

**Cuándo usar Cloud Build**:
- Ya vives en GCP, quieres IAM/Logging/VPC nativos
- El CI necesita Service Accounts con permisos sensibles
- Volumen alto (los minutos gratis de GH Actions se acaban)

> **Mi recomendación para People Analytics en GCP**: **Cloud Build** para deploys y operaciones contra BQ; **GH Actions** para lint y tests que no tocan datos. Defense in depth: si comprometes uno, no comprometes los dos.

---

## Slide 11 — El pipeline mínimo defendible

```yaml
# .github/workflows/validate-backups.yml (esquemático)
name: validate-backups
on:
  pull_request:
    paths:
      - 'backups/**'
      - 'dataform/**'

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.11' }
      - run: pip install sqlfluff
      - run: sqlfluff lint backups/sql --dialect bigquery

  dataform-dry-run:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
          service_account: ${{ secrets.CI_SA }}
      - run: npx @dataform/cli@latest compile --json | jq '.tables | length'
      - run: npx @dataform/cli@latest run --dry-run

  policy-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: python backups/scripts/check_retention_policy.py
```

3 jobs, 1 minuto cada uno, paralelos donde aplica. Lo suficiente para parar el 95% de los errores reales.

---

## Slide 12 — Gestión de cambios en producción

El patrón **release branch + tag + Dataform release config**:

```
develop ─────●─────●─────●─────●─────●─────●─────●─────►
              \                                    \
               \                                    \
        feature/snapshot                       release/2026-Q2
                                                     │
                                                     │ tests OK,
                                                     │ DPO aprueba
                                                     ▼
                                                  tag v1.4.0
                                                     │
                                                     │ Dataform schedule
                                                     │ apunta a tag
                                                     ▼
                                              PRODUCCIÓN
```

**Reglas**:
- Un tag = un release inmutable
- Producción **solo** corre tags, nunca branches mutables
- Rollback = apuntar el schedule al tag anterior, no `git revert`

> **Beneficio menos obvio**: cuando un auditor pregunta "qué versión exacta del SQL corría el 15 de marzo a las 03:00", la respuesta es un tag. Trazabilidad gratis.

---

## Slide 13 — Buenas prácticas colaborativas que se notan

**Convención de commits — Conventional Commits**:

```
feat(snapshot): add daily snapshot for retention_actions
fix(retention): cap partition_expiration_days at 90 for PII tables
docs(policy): clarify DPO sign-off requirements
chore(ci): bump sqlfluff to 3.0
refactor(dataform): extract tenure_bucket UDF
```

Beneficio: changelog automático, semver automático, búsqueda por tipo de cambio.

**Template de PR** (`.github/pull_request_template.md`):

```markdown
## Qué cambia
…

## Por qué
…

## Impacto en datos
- Tablas afectadas:
- Volumen estimado:
- Retención implicada:

## Checklist GDPR
- [ ] No introduzco columnas PII en `gold_*` sin Policy Tag
- [ ] La retención se mantiene ≥ 90 días para tablas con PII
- [ ] Tests/assertions añadidos donde aplica

## Cómo probarlo
…
```

El que abre el PR rellena. El reviewer revisa. Nadie se olvida del DPO.

---

# Parte 4 · Las 4 capas de defensa en BigQuery

---

## Slide 14 — Mapa mental: 4 capas con propósitos distintos

```
┌──────────────────────────────────────────────────────────────────┐
│  CAPA 1 — Time travel                          Ventana: 0 - 7d   │
│  Coste: incluido (physical billing factura)   Latencia: instant │
│  Uso: "el UPDATE de hace 2 horas borró 30 filas"                │
└──────────────────────────────────────────────────────────────────┘
                              ▼ si ya pasó la ventana
┌──────────────────────────────────────────────────────────────────┐
│  CAPA 2 — Snapshot inmutable                   Ventana: tú elig.│
│  Coste: bajo con physical billing (CoW)       Latencia: segundos│
│  Uso: cierre de Q1 inmutable para auditoría                     │
└──────────────────────────────────────────────────────────────────┘
                              ▼ si el snapshot se corrompió
┌──────────────────────────────────────────────────────────────────┐
│  CAPA 3 — Table clone                          Ventana: como tab│
│  Coste: bajo (CoW), pero MUTA si lo tocas    Latencia: segundos │
│  Uso: working copy para experimentar sin tocar prod             │
└──────────────────────────────────────────────────────────────────┘
                              ▼ desastre regional / borrado total
┌──────────────────────────────────────────────────────────────────┐
│  CAPA 4 — Export GCS (Parquet+Snappy)         Ventana: indef.   │
│  Coste: $0.0012/GB/mes en Archive            Latencia: minutos  │
│  Uso: compliance 7 años, recuperación catastrófica              │
└──────────────────────────────────────────────────────────────────┘
```

Cada capa cubre un escenario distinto. **No son alternativas, son complementos**.

---

## Slide 15 — Capa 1: Time travel

**Qué es**: BigQuery mantiene automáticamente todas las versiones de tus tablas durante una ventana de 0 a 7 días (configurable). Puedes consultar el estado pasado con `FOR SYSTEM_TIME AS OF`.

```sql
-- Hace 2 horas
SELECT COUNT(*)
FROM `predictions_retention.retention_actions`
  FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR);

-- Restaurar tabla completa al estado de hace 4 horas
CREATE OR REPLACE TABLE `predictions_retention.retention_actions` AS
SELECT *
FROM `predictions_retention.retention_actions`
  FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 4 HOUR);
```

**Configurar ventana**:

```sql
ALTER TABLE `predictions_retention.retention_actions`
SET OPTIONS (max_time_travel_hours = 168);  -- 7 días, el máximo
```

**Trampas**:
- Si la tabla NO EXISTE (DROP), time travel **sí funciona** durante 7 días vía `UNDROP`
- Si cambias retention de partición a 0 días, las particiones borradas NO se recuperan vía time travel
- En physical billing, time travel storage **se factura**

---

## Slide 16 — Capa 2: Snapshots

**Qué es**: una "foto" inmutable de la tabla en un momento dado. Es solo metadata + Copy-on-Write: ocupa casi nada hasta que la tabla original cambia, y entonces almacena solo el delta.

```sql
-- Crear snapshot
CREATE SNAPSHOT TABLE `audit_archive.retention_actions_snap_20260514`
CLONE `predictions_retention.retention_actions`
OPTIONS (
  expiration_timestamp = TIMESTAMP("2033-05-14 00:00:00 UTC"),
  description = "Snapshot mensual para auditoría DPO. Retención: 7 años."
);

-- Consultar
SELECT * FROM `audit_archive.retention_actions_snap_20260514` LIMIT 10;

-- Restaurar como tabla
CREATE OR REPLACE TABLE `predictions_retention.retention_actions` AS
SELECT * FROM `audit_archive.retention_actions_snap_20260514`;
```

**Trampas**:
- Snapshot **inmutable**: si quieres editarlo, primero clónalo como tabla normal
- Con logical billing, el snapshot ocupa el tamaño completo de la tabla (carísimo)
- Con physical billing, solo paga deltas (regla de oro: physical billing + snapshots = baratísimo)

> **Conexión con Sesión 3**: ya tienes 9 snapshots de `retention_actions` creados automáticamente por tu pipeline de retention. Lo que NO tienes es la **política versionada** que dice por qué existen. Eso es lo que vamos a corregir hoy.

---

## Slide 17 — Capa 3: Table clones

**Qué es**: igual de barato que un snapshot (CoW), pero la copia es read-write. Pensado para "ramas de datos" — experimentos sin tocar producción.

```sql
-- Crear clone
CREATE TABLE `scratch_carlos.retention_actions_experiment`
CLONE `predictions_retention.retention_actions`;

-- Modificar el clone libremente
UPDATE `scratch_carlos.retention_actions_experiment`
SET action = 'experimental_action'
WHERE risk_decile >= 9;

-- La tabla original está intacta
SELECT COUNT(*) FROM `predictions_retention.retention_actions`
WHERE action = 'experimental_action';
-- → 0
```

**Modelo mental**: un clone es a una tabla lo que un branch es a `main`. Mismo coste casi cero, mismas semánticas Copy-on-Write.

**Cuándo usarlo**:
- Probar una nueva regla de decisión sin afectar a producción
- Dar a un data scientist una working copy de 2 GB sin facturar 2 GB
- Tests de restore: clonas, verificas, dropeas

---

## Slide 18 — Capa 4: Export a GCS

**Qué es**: la única capa que sobrevive a "se borró todo BigQuery del proyecto". Independiente, durable, multi-región opcional.

```python
from google.cloud import bigquery
client = bigquery.Client()

job_config = bigquery.ExtractJobConfig(
    destination_format=bigquery.DestinationFormat.PARQUET,
    compression="SNAPPY",
)

extract = client.extract_table(
    "project-9176af0b-ecb3-4050-859.predictions_retention.retention_actions",
    "gs://project-9176af0b-ecb3-4050-859-datalake/backups/retention_actions/2026-05-14/data-*.parquet",
    job_config=job_config,
    location="europe-southwest1",
)
extract.result()
```

**Por qué Parquet+Snappy**:
- Columnar: lecturas selectivas baratísimas al restaurar
- Snappy: compresión rápida + ratio decente (3-5x)
- Reimport directo a BQ con `bigquery.SourceFormat.PARQUET`

**Lifecycle policy** que conecta con los tiers de S4:

```json
{ "lifecycle": { "rule": [
  { "action": {"type":"SetStorageClass","storageClass":"COLDLINE"}, "condition":{"age":30}},
  { "action": {"type":"SetStorageClass","storageClass":"ARCHIVE"},  "condition":{"age":90}},
  { "action": {"type":"Delete"},                                    "condition":{"age":2555}}
]}}
```

7 años de retención por $0.012/GB/mes en Archive. Comparable con cualquier solución on-prem.

---

## Slide 19 — Política de retención: cómo escribir una que aguante

Una buena `RETENTION.md` tiene **5 secciones obligatorias**:

```markdown
# Política de retención — People Analytics

## 1. Marco legal
- GDPR Art. 5(1)(e): limitación del plazo de conservación
- LOPDGDD Art. 32: bloqueo de datos
- Base legal del tratamiento: relación laboral (Art. 6.1.b)

## 2. Categorías de datos y plazos
| Categoría     | Tabla(s)                       | Plazo    | Justificación          |
|---------------|--------------------------------|----------|------------------------|
| Operativo     | bronze_personio.*              | 90 días  | Recarga sin retrabajo  |
| Histórico     | silver_personio.*              | 7 años   | Auditoría laboral      |
| Predicciones  | predictions_retention.*        | 2 años   | Trazabilidad modelo    |
| Logs runs     | pipeline_runs.*                | 1 año    | Operativa SRE          |

## 3. Métodos de respaldo
…

## 4. Pruebas de restauración
- Frecuencia: mensual (1er lunes)
- Responsable: SRE de guardia
- Criterio de éxito: checksum coincide ±0 filas

## 5. Aprobación
- DPO: …
- CISO: …
- Fecha última revisión: 2026-05-18
```

Esta `.md` vive en `backups/policies/RETENTION.md`. Cambios pasan por PR con CODEOWNERS=DPO.

---

## Slide 20 — Separación dev/test/prod en backups

```
proyecto-people-analytics-prod
  ├── silver_personio        ← PII real, backups con DLP previo
  ├── audit_archive          ← snapshots prod, solo DPO lee
  └── gs://...-backup-prod   ← Coldline → Archive, 7 años

proyecto-people-analytics-dev
  ├── silver_personio_dev    ← datos sintéticos o anonimizados
  ├── audit_archive_dev      ← snapshots dev, 30 días
  └── gs://...-backup-dev    ← Standard, 7 días
```

**Reglas duras**:

1. **Backup de prod NUNCA cruza a dev sin DLP**. Si quieres datos reales en dev, pasan por Cloud DLP (M11) con masking automático.
2. **dev y prod en proyectos GCP distintos**. Misma región sí; mismo proyecto no.
3. **Service Account de dev no tiene IAM en prod**. Cero overlap.
4. **Política de retención común** pero **plazos distintos**: dev = 30 días, prod = 7 años.

> **Anti-patrón clásico**: copiar `silver_personio` de prod a dev "para probar" → entero, sin masking → 90 días después, brecha de datos por dev expuesto.

---

## Slide 21 — Playbook de recuperación ante borrado accidental

**Escenario**: alguien hizo `DROP TABLE predictions_retention.retention_actions` a las 10:14.

**Decisión en árbol** (impreso y pegado al monitor del SRE):

```
¿Hace cuánto fue el DROP?
│
├── < 7 días, tabla no recreada
│   └── UNDROP via time travel:
│       CREATE TABLE … AS SELECT * FROM tabla
│       FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(NOW, INTERVAL 1 HOUR);
│       Tiempo: 30 segundos
│
├── < 7 días, tabla ya recreada vacía
│   └── Tabla recreada bloquea time travel del original
│       → Saltar a snapshot
│
├── Snapshot disponible (debería existir, lo creamos diariamente)
│   └── CREATE OR REPLACE TABLE … AS SELECT * FROM snapshot;
│       Tiempo: 1-5 minutos según volumen
│
└── No hay snapshot reciente
    └── Restaurar desde GCS Parquet:
        bq load --source_format=PARQUET …
        Tiempo: 10-30 minutos
```

> **Métrica de salud**: si no sabes en menos de 30 segundos qué rama te toca, tu playbook no está operativo.

---

# Parte 5 · Pruebas y continuidad

---

## Slide 22 — La pregunta que destruye reputaciones

**Auditor**: "¿Cuándo probaste por última vez tu procedimiento de restauración?"

Respuestas observadas en clientes reales:

- 😶 "Hmm, creo que nunca formalmente"
- 😬 "Hicimos uno en 2023, salió mal pero ya lo arreglamos"
- 😅 "Confiamos en BigQuery"
- 😎 "El primer lunes de cada mes, automatizado. Última corrida 2026-05-06 SUCCESS. ¿Quiere ver el run?"

Solo la última pasa la auditoría. Y solo la última te despierta dormido tranquilo cuando se cae prod.

---

## Slide 23 — Restore-test automatizado (el guion concreto)

```python
# backups/python/restore_test.py
"""
Job mensual: prueba que el último snapshot es restaurable.
- Clona el snapshot a scratch_restoretest
- Calcula checksum comparable con prod
- Reporta a pipeline_runs
- Dropea el clone
"""
from google.cloud import bigquery
from datetime import datetime, timezone

PROJECT = "project-9176af0b-ecb3-4050-859"
SOURCE  = f"{PROJECT}.predictions_retention.retention_actions"
SCRATCH = f"{PROJECT}.scratch_restoretest.retention_actions_test"

client = bigquery.Client(project=PROJECT)
run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

# 1. Encontrar snapshot más reciente
snaps = client.query(f"""
  SELECT table_name
  FROM `{PROJECT}.audit_archive`.INFORMATION_SCHEMA.TABLES
  WHERE table_type = 'SNAPSHOT'
    AND table_name LIKE 'retention_actions_%'
  ORDER BY creation_time DESC LIMIT 1
""").result()
latest_snap = list(snaps)[0].table_name
# 2. Clonar a scratch
client.query(f"CREATE OR REPLACE TABLE `{SCRATCH}` CLONE "
             f"`{PROJECT}.audit_archive.{latest_snap}`").result()
# 3. Checksums (filas + suma de risk_score)
def checksum(table):
    r = list(client.query(
      f"SELECT COUNT(*) c, ROUND(SUM(risk_score),4) s FROM `{table}`"
    ).result())[0]
    return r.c, r.s
src_c, src_s = checksum(SOURCE)
snp_c, snp_s = checksum(SCRATCH)
ok = (src_c == snp_c)  # filas iguales (score puede diferir si hay cambios)
# 4. Reportar
client.query(f"""
  INSERT `{PROJECT}.pipeline_runs.restore_tests`
  (run_id, snapshot_used, ok, src_rows, snap_rows, ts)
  VALUES ('{run_id}', '{latest_snap}', {ok},
          {src_c}, {snp_c}, CURRENT_TIMESTAMP())
""").result()
# 5. Cleanup
client.delete_table(SCRATCH, not_found_ok=True)
print(f"Restore test {run_id}: {'OK' if ok else 'FAIL'}")
```

Cron mensual en Cloud Scheduler. 0 fricción. Auditoría feliz.

---

## Slide 24 — RTO y RPO en People Analytics

**RTO (Recovery Time Objective)**: cuánto tardo en volver a operar.
**RPO (Recovery Point Objective)**: cuántos datos puedo perder como máximo.

Matriz de decisión típica:

| Tipo de dato                          | RTO    | RPO    | Estrategia                          |
|---------------------------------------|--------|--------|-------------------------------------|
| `silver_personio` (transaccional)     | 1 hora | 1 hora | Time travel + snapshot diario       |
| `gold_people_analytics` (derivado)    | 4 h    | 24 h   | Snapshot diario                     |
| `predictions_retention` (modelo)      | 4 h    | 24 h   | Snapshot diario + retrain on demand |
| `pipeline_runs` (logs)                | 24 h   | 24 h   | Snapshot semanal                    |
| Sandbox `scratch_*`                   | ∞      | ∞      | Sin backup (TTL 7 días, se pierde)  |

> **Regla práctica**: cuando alguien te diga "RTO=0", pregúntale qué presupuesto trae. RTO=0 = arquitectura multi-región activa-activa = factura ×3.

---

## Slide 25 — Checklist DPO-friendly para auditoría

Esta es la página que pegas en la sala del Comité de Seguridad. Si todos los checks están verdes, el cierre anual es ceremonia, no batalla.

```
☐ Existe RETENTION.md versionada en Git
☐ Esa RETENTION.md tiene CODEOWNERS=@dpo
☐ Último commit en RETENTION.md está firmado por DPO (no por DE)
☐ Cada tabla con PII tiene partition_expiration_days configurado
☐ Cada tabla con PII tiene snapshot diario en audit_archive
☐ Existe export semanal a GCS Coldline/Archive
☐ Existe job mensual de restore_test que registra en pipeline_runs
☐ Último restore_test reportó OK
☐ Branch protection sobre main exige CODEOWNERS review
☐ Audit logs de BigQuery están retenidos ≥ 1 año
☐ Hay playbook de borrado accidental (1 página, en el repo)
☐ Hay matriz RTO/RPO firmada por negocio
```

12 puntos. Si tienes los 12, has terminado.

---

# Parte 6 · Cierre

---

## Slide 26 — La frase que resume la sesión

> **Lo que no está versionado, no es operable.**
>
> **Lo que es operable pero no se prueba, no funciona.**

Si te llevas estas dos frases y las aplicas a tu trabajo del próximo lunes, esta sesión habrá rentado.

Concreto: revisa hoy si tu equipo:

1. Tiene la política de retención en un fichero del repo, no en Confluence
2. Ese fichero pasa por PR con revisión obligatoria
3. Tiene un job que prueba la restauración al menos una vez al mes

Si fallan los tres, tienes una conversación que tener mañana.

---

## Slide 27 — Conexión con la próxima sesión

**Sesión 6 — Gobierno del Dato y Seguridad (M11)**:

Hoy hemos versionado la **política**. La próxima sesión versionamos los **datos sensibles**:

- **Cloud DLP** identifica automáticamente PII en `bronze_personio`
- **Masking templates** que sustituyen `gross_salary` por buckets antes de que llegue a dev
- **Tag Templates** automáticos que pegan Policy Tags a columnas detectadas como PII
- **El export semanal a GCS** que generamos hoy será el input del DLP scan de la próxima sesión

> **La cadena completa empieza a verse**:
> ```
> S3 (Pipeline) → S4 (SQL/Dataform) → S5 (Backup-as-Code) → S6 (DLP)
>                                                              ↓
>                                                       S7 (FinOps) → ...
> ```
>
> Cada sesión añade una capa al producto real. Para S12, tu Proyecto Final tendrá los seis primeros bloques productivizados.

---

## Anexo A — Referencias rápidas

**Comandos `gh` que usaremos en el notebook**:

```bash
gh auth status
gh repo create people-analytics-ops --private --description "..."
gh api repos/:owner/:repo/branches/main/protection -X PUT --input protection.json
gh workflow list
gh run list --workflow=validate-backups.yml --limit 5
gh pr create --title "..." --body-file pr_body.md
```

**Comandos `bq` que usaremos**:

```bash
bq mk --dataset --location=europe-southwest1 audit_archive
bq cp --snapshot --expiration=220752000 source.tbl dest.snap
bq extract --destination_format=PARQUET --compression=SNAPPY source.tbl gs://.../*.parquet
bq query --use_legacy_sql=false --dry_run 'SELECT ...'
```

**SQL críticos**:

```sql
-- Listar snapshots
SELECT table_name, creation_time
FROM `proyecto.dataset.INFORMATION_SCHEMA.TABLES`
WHERE table_type = 'SNAPSHOT';

-- Time travel
SELECT * FROM tabla FOR SYSTEM_TIME AS OF TIMESTAMP "2026-05-13 09:00:00 UTC";

-- Cambiar retention
ALTER TABLE tabla SET OPTIONS (partition_expiration_days = 730);

-- Cambiar time travel window
ALTER TABLE tabla SET OPTIONS (max_time_travel_hours = 168);
```

---

## Anexo B — La estructura del repo que vas a construir

```
people-analytics-ops/
├── .github/
│   ├── workflows/
│   │   ├── validate-backups.yml      ← lint + dry-run en PR
│   │   └── scheduled-snapshot.yml    ← cron diario que crea snapshots
│   ├── CODEOWNERS                    ← @dpo sobre backups/policies/
│   └── pull_request_template.md
├── backups/
│   ├── sql/
│   │   ├── snapshot_retention_actions.sql
│   │   ├── snapshot_dim_employee.sql
│   │   └── retention_policies.sql
│   ├── python/
│   │   ├── export_to_gcs.py
│   │   └── restore_test.py
│   ├── policies/
│   │   └── RETENTION.md              ← el documento que firma el DPO
│   └── scripts/
│       └── check_retention_policy.py ← chequeo CI
├── dataform/                         ← código de Sesión 4 (referencia)
└── README.md
```

Cada uno de esos ficheros se crea en el notebook de la sesión. Al final tienes un repo funcional, no un ejercicio académico.
