# Módulo 9: Integración Real con GitHub

## Información de la sesión
- **Sesión:** 8
- **Fecha:** Lunes 1 de Junio, 16:00–17:00
- **Duración:** ~60 minutos (sesión compartida con Módulo 10)
- **Prerequisitos:** Módulos 1–8 completados, repositorio de Dataform creado

---

## Tema 9.1: Control de versiones en proyectos de datos

### Conceptos clave
- El **control de versiones** con Git no es solo para desarrolladores de software: en proyectos de datos, es igualmente esencial para rastrear cambios en SQL, configuraciones de pipelines, definiciones de modelos y documentación.
- Sin control de versiones, los equipos de datos trabajan con archivos sueltos, copias manuales ("consulta_v2_final_FINAL.sql") y sin trazabilidad de quién cambió qué y cuándo.
- Git permite **auditar**, **revertir**, **colaborar** y **automatizar** los flujos de trabajo del equipo de datos.
- En el contexto de People Analytics, donde los datos son sensibles (salarios, evaluaciones), la trazabilidad de cambios en la lógica de transformación es un requisito regulatorio.

### Detalle técnico

**Qué versionar en un proyecto de People Analytics:**

| Tipo de archivo | Versionar | No versionar |
|----------------|-----------|-------------|
| Modelos SQLX de Dataform | Si | - |
| Scripts SQL de análisis | Si | - |
| Configuración (`dataform.json`) | Si | - |
| Macros y helpers (`includes/`) | Si | - |
| Documentación (README, diccionarios) | Si | - |
| `.env` con credenciales | NO | Usar Secret Manager |
| Service account keys | NO | Nunca en Git |
| Datos crudos (CSV, JSON) | NO | Usar GCS |
| Resultados de queries | NO | Usar BigQuery |
| `node_modules/` | NO | Regenerar con `npm install` |

**Archivo `.gitignore` recomendado:**

```gitignore
# Dependencias
node_modules/

# Credenciales (NUNCA versionar)
.env
*.json.key
service-account-*.json
credentials/

# Datos
data/
*.csv
*.parquet
*.avro

# Compilados de Dataform
.dataform/

# IDE
.vscode/
.idea/
*.swp

# OS
.DS_Store
Thumbs.db
```

**Flujo básico de Git para un cambio en la lógica de transformación:**

```bash
# 1. Crear rama para el cambio
git checkout -b feature/actualizar-definicion-rotacion-voluntaria

# 2. Modificar el modelo SQLX
# (editar definitions/gold/metrics/gold_tasa_rotacion_mensual.sqlx)

# 3. Verificar cambios
git diff

# 4. Añadir y commitear
git add definitions/gold/metrics/gold_tasa_rotacion_mensual.sqlx
git commit -m "feat: añadir motivo CAMBIO_SECTOR a rotación voluntaria

Se añade el motivo CAMBIO_SECTOR a la clasificación de rotación 
voluntaria, alineando la definición con la nueva política de HR.

Refs: JIRA-PA-234"

# 5. Subir rama
git push -u origin feature/actualizar-definicion-rotacion-voluntaria

# 6. Crear Pull Request (desde GitHub o gh CLI)
gh pr create --title "feat: actualizar definición de rotación voluntaria" \
    --body "Añade CAMBIO_SECTOR como motivo de baja voluntaria"
```

### Aplicación en People Analytics
- **Trazabilidad regulatoria:** Cuando un auditor pregunta "¿por qué cambió la tasa de rotación entre trimestres?", Git muestra exactamente qué cambio en la lógica SQL lo causó, quién lo hizo y cuándo.
- **Reversión segura:** Si una nueva definición de "empleado activo" genera números incorrectos, se puede revertir al commit anterior en minutos.
- **Colaboración:** Múltiples analistas pueden trabajar en diferentes métricas simultáneamente sin pisarse, gracias a las ramas.

---

## Tema 9.2: Estructura de repositorios analíticos

### Conceptos clave
- La decisión entre **monorepo** (un solo repositorio para todo el proyecto) y **polyrepo** (repositorios separados por componente) afecta la organización, los permisos y los flujos de CI/CD.
- Para equipos pequeños de People Analytics (2-5 personas), el **monorepo** es generalmente la mejor opción: simplicidad, visibilidad completa y facilidad de gestión.
- La estructura de carpetas debe ser intuitiva y reflejar la arquitectura de datos (ingesta, transformación, consumo).
- Los archivos de configuración y documentación tienen ubicaciones estándar que facilitan el onboarding.

### Detalle técnico

**Comparación monorepo vs. polyrepo:**

| Aspecto | Monorepo | Polyrepo |
|---------|----------|----------|
| **Estructura** | Un repo con todo | Repos separados: dataform, functions, infra |
| **Visibilidad** | Cambios cross-capa visibles en un PR | Cambios distribuidos en PRs separados |
| **Permisos** | Un solo nivel de acceso | Permisos granulares por repo |
| **CI/CD** | Un pipeline, múltiples triggers | Pipelines independientes |
| **Complejidad** | Baja (para equipos pequeños) | Media-alta |
| **Ideal para** | Equipos de 1-8 personas | Equipos de 10+ personas |

**Estructura de monorepo recomendada:**

```
people-analytics/
├── README.md                           # Documentación principal del proyecto
├── CHANGELOG.md                        # Historial de cambios relevantes
├── .gitignore                          # Archivos excluidos
├── .github/                            # Configuración de GitHub
│   ├── PULL_REQUEST_TEMPLATE.md        # Template para PRs
│   ├── CODEOWNERS                      # Asignación automática de reviewers
│   └── workflows/                      # GitHub Actions
│       ├── validate-dataform.yml       # Validar compilación de Dataform
│       └── deploy-prod.yml             # Deploy a producción
├── dataform/                           # Transformaciones (Módulo 8)
│   ├── dataform.json
│   ├── package.json
│   ├── definitions/
│   │   ├── bronze/
│   │   ├── silver/
│   │   ├── gold/
│   │   └── assertions/
│   └── includes/
├── cloud-functions/                    # Ingesta (Módulos 3-4)
│   ├── fn-ingesta-empleados/
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── test_main.py
│   └── fn-procesar-eventos/
│       ├── main.py
│       ├── requirements.txt
│       └── test_main.py
├── infrastructure/                     # Infraestructura como código
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── bigquery.tf
│   │   └── iam.tf
│   └── cloudbuild/
│       ├── cloudbuild-dataform.yaml
│       └── cloudbuild-functions.yaml
├── docs/                               # Documentación extendida
│   ├── data-dictionary.md              # Diccionario de datos
│   ├── architecture.md                 # Arquitectura técnica
│   └── runbooks/                       # Procedimientos operativos
│       ├── carga-mensual.md
│       └── rollback.md
├── scripts/                            # Scripts de utilidad
│   ├── backup-dataset.sh
│   ├── validate-data-quality.sql
│   └── setup-dev-environment.sh
└── notebooks/                          # Notebooks de análisis
    ├── exploratorio/
    └── reportes/
```

**Archivo CODEOWNERS (asignación automática de reviewers):**

```
# .github/CODEOWNERS

# Todo el repositorio requiere review del lead
* @people-analytics-lead

# Cambios en Dataform requieren review del equipo de datos
dataform/ @data-engineering-team

# Cambios en infraestructura requieren review del SRE
infrastructure/ @sre-team

# Cambios en Cloud Functions requieren review del backend
cloud-functions/ @backend-team
```

### Aplicación en People Analytics
- **Onboarding de 15 minutos:** Un nuevo miembro del equipo puede entender toda la arquitectura del proyecto navegando la estructura de carpetas del repositorio.
- **Búsqueda eficiente:** Cuando se necesita cambiar una definición de negocio, la estructura indica exactamente dónde buscar (`dataform/definitions/gold/`).
- **Gobernanza:** Los CODEOWNERS aseguran que los cambios críticos (definiciones de métricas, infraestructura) siempre sean revisados por la persona adecuada.

---

## Tema 9.3: Ramas y flujos de trabajo — Git flow para equipos de datos

### Conceptos clave
- Un **flujo de ramas** (branching strategy) define cómo el equipo organiza el trabajo en paralelo, las revisiones y los despliegues.
- Para equipos de datos, un flujo simplificado basado en Git Flow con ramas `main`, `develop` y `feature/*` es suficiente.
- La rama `main` siempre refleja el estado de **producción**: lo que está desplegado y ejecutándose en BigQuery.
- Las ramas `feature/*` son efímeras: se crean para un cambio específico, se revisan en un PR y se eliminan tras el merge.

### Detalle técnico

**Flujo de ramas para People Analytics:**

```
main (producción)
  │
  ├── develop (integración)
  │     │
  │     ├── feature/nueva-metrica-absentismo
  │     │     │
  │     │     ├── commit: "feat: modelo fact_absentismo"
  │     │     ├── commit: "feat: assertion de rango válido"
  │     │     └── commit: "docs: actualizar diccionario"
  │     │     │
  │     │     └──── PR → develop (review + aprobación)
  │     │
  │     ├── feature/fix-brecha-salarial
  │     │     │
  │     │     └── commit: "fix: excluir becarios del cálculo"
  │     │     │
  │     │     └──── PR → develop
  │     │
  │     └──── PR → main (release mensual)
  │
  └── hotfix/corregir-headcount-abril
        │
        └── commit: "fix: filtrar duplicados en carga abril"
        │
        └──── PR → main (deploy urgente)
                │
                └──── merge back → develop
```

**Convenciones de nombres de ramas:**

| Tipo | Patrón | Ejemplo |
|------|--------|---------|
| **Feature** | `feature/descripcion-corta` | `feature/modelo-dim-tiempo` |
| **Fix** | `fix/descripcion-corta` | `fix/duplicados-silver-empleados` |
| **Hotfix** | `hotfix/descripcion-corta` | `hotfix/headcount-abril-incorrecto` |
| **Docs** | `docs/descripcion-corta` | `docs/diccionario-datos-gold` |
| **Refactor** | `refactor/descripcion-corta` | `refactor/simplificar-ctes-rotacion` |

**Convenciones de mensajes de commit (Conventional Commits):**

```
feat: añadir modelo fact_evaluaciones con assertions
fix: corregir cálculo de FTE para jornada parcial 80%
docs: actualizar diccionario de datos con nuevas columnas gold
refactor: simplificar CTEs en gold_tasa_rotacion_mensual
test: añadir assertion de integridad referencial empleados-movimientos
chore: actualizar Dataform core a versión 2.9.0
```

**Ciclo de vida de una feature:**

```bash
# 1. Partir de develop actualizado
git checkout develop
git pull origin develop

# 2. Crear rama feature
git checkout -b feature/modelo-dim-tiempo

# 3. Desarrollar (múltiples commits)
git add definitions/gold/dimensions/dim_tiempo.sqlx
git commit -m "feat: crear modelo dim_tiempo con rango 2020-2026"

git add definitions/assertions/assert_dim_tiempo_completa.sqlx
git commit -m "test: assertion para verificar completitud de dim_tiempo"

# 4. Subir y crear PR
git push -u origin feature/modelo-dim-tiempo
gh pr create --base develop \
    --title "feat: modelo dim_tiempo para capa gold" \
    --body "$(cat <<'EOF'
## Resumen
- Crea la dimensión de tiempo para el modelo estrella
- Rango: 2020-01-01 a 2026-12-31
- Incluye campos: año, trimestre, mes, semana, día, flags

## Test plan
- [ ] Compilar Dataform sin errores
- [ ] Ejecutar en entorno dev
- [ ] Verificar assertion de completitud
- [ ] Verificar JOINs con fact tables existentes
EOF
)"

# 5. Tras aprobación, merge
gh pr merge --squash

# 6. Limpiar rama local
git checkout develop
git pull
git branch -d feature/modelo-dim-tiempo
```

### Aplicación en People Analytics
- **Paralelismo seguro:** Un analista puede trabajar en la nueva métrica de absentismo mientras otro corrige la brecha salarial, sin conflictos.
- **Releases controladas:** Los cambios se acumulan en `develop` y se despliegan a producción de forma controlada (no cada commit individual).
- **Hotfixes rápidos:** Si el reporte mensual tiene un error, el hotfix se aplica directamente a `main` sin esperar al ciclo normal.
- **Historial limpio:** El squash merge en PRs mantiene un historial lineal y fácil de auditar.

---

## Tema 9.4: Pull requests y revisión de código SQL

### Conceptos clave
- Los **pull requests (PRs)** son el mecanismo para que los cambios sean revisados antes de integrarse. En equipos de datos, sustituyen la revisión informal ("¿puedes echarle un ojo a esta query?").
- Un PR bien estructurado incluye: título descriptivo, resumen de cambios, plan de test, y evidencia de que las assertions pasan.
- La **revisión de código SQL** tiene particularidades: verificar lógica de negocio, rendimiento, documentación y adherencia a estándares del equipo.
- Los templates de PR estandarizan la información requerida y reducen las idas y vueltas.

### Detalle técnico

**Template de Pull Request (.github/PULL_REQUEST_TEMPLATE.md):**

```markdown
## Tipo de cambio
- [ ] Nueva métrica/modelo (feature)
- [ ] Corrección de lógica (bugfix)
- [ ] Refactoring (sin cambio de comportamiento)
- [ ] Documentación
- [ ] Infraestructura/configuración

## Descripción
<!-- Describir qué cambia y por qué -->

## Tablas afectadas
<!-- Listar todas las tablas que se crean, modifican o eliminan -->
- [ ] `pa_silver.silver_xxx`
- [ ] `pa_gold.xxx`

## Checklist de revisión
### Lógica de negocio
- [ ] La definición de negocio es correcta (validado con HR)
- [ ] Los filtros son coherentes con las definiciones canónicas
- [ ] Los cálculos numéricos son correctos (denominador, redondeo)

### Calidad del código SQL
- [ ] Usa CTEs con nombres descriptivos (prefijos src_, flt_, agg_, calc_)
- [ ] No hay `SELECT *`
- [ ] Los JOINs tienen condiciones completas (no cartesianos)
- [ ] Se usan `SAFE_DIVIDE` donde hay riesgo de división por cero
- [ ] Las columnas tienen alias explícitos con `AS`

### Rendimiento
- [ ] Hay filtro de partición (`WHERE fecha_snapshot = ...`)
- [ ] No hay correlated subqueries
- [ ] No se escanean más datos de los necesarios

### Calidad del dato
- [ ] Se han añadido assertions apropiadas (uniqueKey, nonNull, rowConditions)
- [ ] Los assertions existentes siguen pasando
- [ ] Se ha verificado la integridad referencial

### Documentación
- [ ] Las columnas tienen descripción en el bloque `config`
- [ ] Se ha actualizado el diccionario de datos si es necesario
- [ ] Los tags del modelo son correctos

## Evidencia de testing
<!-- Pegar resultados de `dataform compile` y ejecución en dev -->

## Screenshot / Resultados
<!-- Si aplica, pegar resultado de la query o captura del dashboard -->
```

**Ejemplo de revisión de código SQL — Comentarios del reviewer:**

```sql
-- COMENTARIO REVIEWER: Este LEFT JOIN puede generar duplicados si un empleado
-- tiene múltiples movimientos en el mismo mes. Considerar usar una subquery
-- con ROW_NUMBER para quedarse con el último movimiento.

-- ORIGINAL (con bug):
SELECT e.*, m.tipo_movimiento
FROM silver_empleados e
LEFT JOIN silver_movimientos m
    ON e.empleado_id = m.empleado_id
    AND DATE_TRUNC(e.fecha_snapshot, MONTH) = DATE_TRUNC(m.fecha_cambio, MONTH);

-- SUGERENCIA DEL REVIEWER:
WITH ultimo_movimiento AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY empleado_id, DATE_TRUNC(fecha_cambio, MONTH)
            ORDER BY fecha_cambio DESC
        ) AS rn
    FROM silver_movimientos
)
SELECT e.*, um.tipo_movimiento
FROM silver_empleados e
LEFT JOIN ultimo_movimiento um
    ON e.empleado_id = um.empleado_id
    AND DATE_TRUNC(e.fecha_snapshot, MONTH) = DATE_TRUNC(um.fecha_cambio, MONTH)
    AND um.rn = 1;
```

### Aplicación en People Analytics
- **Calidad garantizada:** Cada cambio en la lógica de cálculo de métricas pasa por al menos una revisión, reduciendo errores que podrían llegar a los dashboards de dirección.
- **Transferencia de conocimiento:** Las revisiones de PRs son la forma más efectiva de compartir conocimiento sobre la lógica de negocio de HR.
- **Evidencia de control:** Los PRs quedan registrados permanentemente, proporcionando evidencia de que los cambios fueron revisados y aprobados.

---

## Tema 9.5: Versionado de transformaciones en Dataform

### Conceptos clave
- Dataform tiene **integración nativa con GitHub**: el repositorio de Dataform en GCP se sincroniza con un repositorio de GitHub.
- Cada cambio en los modelos SQLX pasa por Git: branch, commit, PR, merge. Dataform en producción solo ejecuta el código de la rama `main`.
- La sincronización permite que el equipo trabaje localmente (con IDE y herramientas de Git) y que los cambios se reflejen automáticamente en Dataform de GCP.
- Las **release configurations** de Dataform permiten vincular una rama específica de Git a un entorno de ejecución.

### Detalle técnico

**Configuración de la integración Dataform-GitHub:**

```
Consola GCP > Dataform > Repositorios > Crear repositorio:

1. Nombre: people-analytics-dataform
2. Región: europe-west1
3. Git provider: GitHub
4. Repository URL: https://github.com/mi-org/people-analytics.git
5. Branch: main
6. Secret: projects/pa-prod/secrets/github-token/versions/latest

Release Configurations:
  - Nombre: prod-release
    Git branch: main
    Frecuencia de compilación: Cada hora
    Variables: env=prod
  
  - Nombre: dev-release
    Git branch: develop
    Frecuencia de compilación: Manual
    Variables: env=dev
```

**Flujo completo Dataform + GitHub:**

```
┌─────────────┐     ┌──────────┐     ┌──────────┐     ┌─────────────┐
│  Analista   │────>│  Git     │────>│  GitHub  │────>│  Dataform   │
│  (local)    │     │  Push    │     │  PR +    │     │  (GCP)      │
│             │     │          │     │  Merge   │     │             │
│  Edita SQLX │     │  branch  │     │  to main │     │  Compila +  │
│  en VS Code │     │  feature │     │          │     │  Ejecuta    │
└─────────────┘     └──────────┘     └──────────┘     └─────────────┘
                                          │
                                          ▼
                                    ┌──────────┐
                                    │  Cloud   │
                                    │  Build   │
                                    │  (CI)    │
                                    │          │
                                    │ Compila  │
                                    │ Dataform │
                                    │ + Tests  │
                                    └──────────┘
```

### Aplicación en People Analytics
- **Flujo profesional:** El equipo de People Analytics trabaja con las mismas herramientas y flujos que los equipos de software, elevando el nivel de madurez del equipo.
- **Entorno local productivo:** Los analistas pueden usar VS Code con extensiones de SQL, autocompletado y linting, mejorando la productividad.
- **Deployment automático:** Al mergear a `main`, Dataform automáticamente compila y ejecuta las transformaciones actualizadas.

---

## Tema 9.6: Integración CI/CD básica

### Conceptos clave
- **CI (Continuous Integration)** ejecuta validaciones automáticas cuando se crea o actualiza un PR: compilación de Dataform, linting de SQL, tests unitarios.
- **CD (Continuous Deployment)** despliega automáticamente a producción cuando se mergea a `main`: ejecución de Dataform, actualización de dashboards.
- En GCP, **Cloud Build** es el servicio de CI/CD nativo que se integra con GitHub y Dataform.
- El objetivo es que cada cambio se valide automáticamente, reduciendo errores humanos y acelerando el ciclo de desarrollo.

### Detalle técnico

**Pipeline CI con Cloud Build (cloudbuild-dataform.yaml):**

```yaml
# infrastructure/cloudbuild/cloudbuild-dataform.yaml

# Trigger: Se ejecuta en cada PR contra develop o main
# Propósito: Validar que los cambios en Dataform compilan correctamente

steps:
  # Paso 1: Instalar dependencias de Dataform
  - name: 'node:18'
    id: 'install-dependencies'
    entrypoint: 'npm'
    args: ['install']
    dir: 'dataform'

  # Paso 2: Compilar Dataform (sin ejecutar)
  - name: 'node:18'
    id: 'compile-dataform'
    entrypoint: 'npx'
    args: ['dataform', 'compile', '--json']
    dir: 'dataform'
    env:
      - 'GOOGLE_CLOUD_PROJECT=pa-dev'

  # Paso 3: Verificar que no hay errores de compilación
  - name: 'node:18'
    id: 'validate-compilation'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        RESULT=$(npx dataform compile --json 2>&1)
        if echo "$RESULT" | grep -q '"graphErrors":\[\]'; then
          echo "Compilacion exitosa: sin errores"
        else
          echo "ERROR: La compilacion tiene errores"
          echo "$RESULT" | jq '.graphErrors'
          exit 1
        fi
    dir: 'dataform'

  # Paso 4: Ejecutar en entorno dev (dry-run)
  - name: 'node:18'
    id: 'dry-run-dev'
    entrypoint: 'npx'
    args: [
      'dataform', 'run',
      '--dry-run',
      '--vars', '{"env":"dev"}',
      '--default-schema', 'pa_dataform_ci'
    ]
    dir: 'dataform'

options:
  logging: CLOUD_LOGGING_ONLY

timeout: '600s'
```

**Pipeline CD para producción (deploy-prod.yaml):**

```yaml
# infrastructure/cloudbuild/deploy-prod.yaml

# Trigger: Se ejecuta cuando se mergea a main
# Propósito: Ejecutar Dataform en producción

steps:
  - name: 'node:18'
    id: 'install'
    entrypoint: 'npm'
    args: ['install']
    dir: 'dataform'

  - name: 'node:18'
    id: 'run-production'
    entrypoint: 'npx'
    args: [
      'dataform', 'run',
      '--vars', '{"env":"prod"}',
      '--tags', 'silver',
      '--tags', 'gold'
    ]
    dir: 'dataform'
    env:
      - 'GOOGLE_CLOUD_PROJECT=pa-prod'

  # Notificar resultado
  - name: 'gcr.io/cloud-builders/gcloud'
    id: 'notify-success'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        gcloud pubsub topics publish pa-notifications \
          --message="Dataform deploy exitoso en produccion. Commit: $COMMIT_SHA"

timeout: '1800s'
```

**Configurar trigger en Cloud Build:**

```bash
# Crear trigger para PRs (CI)
gcloud builds triggers create github \
    --name="dataform-ci" \
    --repo-name="people-analytics" \
    --repo-owner="mi-org" \
    --pull-request-pattern="^(develop|main)$" \
    --build-config="infrastructure/cloudbuild/cloudbuild-dataform.yaml"

# Crear trigger para merge a main (CD)
gcloud builds triggers create github \
    --name="dataform-deploy-prod" \
    --repo-name="people-analytics" \
    --repo-owner="mi-org" \
    --branch-pattern="^main$" \
    --build-config="infrastructure/cloudbuild/deploy-prod.yaml"
```

### Aplicación en People Analytics
- **Validación automática:** Cada PR se valida automáticamente (compilación sin errores, assertions definidas), eliminando la posibilidad de mergear código roto.
- **Deploy sin intervención manual:** Al mergear a `main`, el pipeline de producción se ejecuta automáticamente, reduciendo el tiempo entre el cambio y su disponibilidad en dashboards.
- **Notificaciones:** El equipo recibe notificaciones de éxito o fallo, permitiendo actuar rápidamente si algo no funciona.

---

## Tema 9.7: Documentación en repositorio

### Conceptos clave
- La **documentación viva** reside en el mismo repositorio que el código, se versiona junto con él y se revisa en los mismos PRs.
- Los archivos esenciales son: `README.md` (entrada al proyecto), `CHANGELOG.md` (historial de cambios), y el diccionario de datos.
- La documentación no sustituye a la autodocumentación del código (nombres claros, comentarios, descriptions en SQLX), sino que la complementa.
- El diccionario de datos es el documento más importante para el equipo de People Analytics: define cada campo, su origen, su lógica de cálculo y sus valores válidos.

### Detalle técnico

**Estructura del README.md:**

```markdown
# People Analytics — Pipeline de Datos

## Arquitectura
Este repositorio contiene el pipeline completo de datos de People Analytics:
- **Ingesta:** Cloud Functions que cargan datos desde SAP/Workday a BigQuery (bronze)
- **Transformación:** Modelos Dataform que transforman bronze → silver → gold
- **Consumo:** Vistas gold optimizadas para Looker Studio

## Estructura del repositorio
[Diagrama de carpetas]

## Setup local
1. Clonar repositorio: `git clone https://github.com/mi-org/people-analytics.git`
2. Instalar dependencias: `cd dataform && npm install`
3. Configurar credenciales: `gcloud auth application-default login`
4. Compilar: `npx dataform compile`
5. Ejecutar en dev: `npx dataform run --vars='{"env":"dev"}'`

## Flujo de trabajo
1. Crear rama: `git checkout -b feature/mi-cambio`
2. Desarrollar y testear localmente
3. Crear PR contra `develop`
4. Revisión + aprobación
5. Merge → deploy automático a dev
6. Release mensual: merge develop → main → deploy a prod

## Contacto
- Lead: Ana García (ana.garcia@empresa.com)
- Equipo: #people-analytics en Slack
```

**Estructura del diccionario de datos (docs/data-dictionary.md):**

```markdown
# Diccionario de Datos — People Analytics

## pa_silver.silver_empleados

| Campo | Tipo | Descripción | Origen | Valores válidos |
|-------|------|-------------|--------|-----------------|
| empleado_id | STRING | ID único del empleado | SAP HCM | Formato: EMP-XXXX |
| fecha_snapshot | DATE | Fecha del snapshot mensual | Generado | Primer día del mes |
| departamento | STRING | Departamento normalizado | SAP → normalizado en Dataform | Ver lista aprobada |
| salario_bruto | INT64 | Salario bruto anual (EUR) | SAP Nómina | 15.000 - 500.000 |
| rotacion | BOOL | Indicador de baja | Derivado de fecha_baja | TRUE/FALSE |

## pa_gold.gold_tasa_rotacion_mensual

| Campo | Tipo | Definición de negocio | Fórmula |
|-------|------|----------------------|---------|
| tasa_vol_pct | FLOAT64 | Tasa de rotación voluntaria | bajas_voluntarias / headcount_activo * 100 |
| headcount_activo | INT64 | Empleados activos | Excluye: rotacion=TRUE, BAJA_TEMPORAL, EXCEDENCIA |
```

### Aplicación en People Analytics
- **Autonomía de los stakeholders:** Los business partners de HR pueden consultar el diccionario de datos para entender qué significan las métricas del dashboard, sin depender del equipo de datos.
- **Onboarding eficiente:** Un nuevo analista puede ser productivo en días en lugar de semanas gracias a la documentación completa.
- **Definiciones compartidas:** El diccionario es la referencia única para preguntas como "¿qué incluye headcount activo?" o "¿qué motivos son rotación voluntaria?".

---

## Temas 9.8–9.10: Gestión de cambios, auditoría y buenas prácticas colaborativas

### Conceptos clave
- La **gestión de cambios en producción** requiere un proceso formal: no se modifica producción directamente, sino a través de PRs revisados.
- La **auditoría de cambios** se basa en el historial de Git: cada commit, PR y merge queda registrado con autor, fecha y descripción.
- Las **buenas prácticas colaborativas** incluyen: comunicación asíncrona via PRs, documentación de decisiones, y automatización de lo repetitivo.

### Detalle técnico

**Protección de la rama main:**

```
GitHub > Settings > Branches > Branch protection rules:

Rama: main
  ✅ Require pull request reviews before merging
     - Required approving reviews: 1
  ✅ Require status checks to pass before merging
     - Status checks: "dataform-ci"
  ✅ Require branches to be up to date before merging
  ✅ Do not allow bypassing the above settings
  ❌ Allow force pushes (NUNCA)
  ❌ Allow deletions (NUNCA)
```

**Ejemplo de CHANGELOG.md:**

```markdown
# Changelog

## [2025-04-01] — Release Abril 2025

### Nuevas métricas
- Añadido `gold_absentismo_mensual`: tasa de absentismo por departamento
- Añadida dimensión `dim_tiempo` con rango 2020-2026

### Correcciones
- Fix: cálculo de FTE para jornada PARCIAL_80 (era 0.75, corregido a 0.80)
- Fix: duplicados en silver_empleados para snapshot marzo 2025

### Cambios en definiciones
- "Rotación voluntaria" ahora incluye motivo CAMBIO_SECTOR (alineado con nueva política HR)
- "Empleado activo" ahora excluye estado EXCEDENCIA

## [2025-03-01] — Release Marzo 2025
...
```

**Flujo de auditoría:**

```bash
# ¿Quién cambió la definición de rotación voluntaria y cuándo?
git log --follow -p -- dataform/definitions/gold/metrics/gold_tasa_rotacion_mensual.sqlx

# ¿Qué cambios se desplegaron en el último release?
git log main --oneline --since="2025-03-01"

# ¿Quién aprobó el PR que modificó la brecha salarial?
gh pr list --state merged --search "brecha salarial" --json number,mergedBy,mergedAt
```

**Buenas prácticas del equipo:**

| Práctica | Descripción | Beneficio |
|----------|-------------|-----------|
| **PR pequeños** | Un cambio por PR (no mezclar features) | Revisión rápida y focalizada |
| **Commits atómicos** | Cada commit compila correctamente | Revertir es seguro |
| **Conventional commits** | Prefijos `feat:`, `fix:`, `docs:` | Changelog automático |
| **Branch protection** | main protegida, requires review | No se salta la revisión |
| **CI obligatorio** | Status checks deben pasar | No se mergea código roto |
| **Squash merge** | Un commit por PR en main | Historial limpio |
| **Delete branch** | Eliminar rama tras merge | Repositorio ordenado |

### Aplicación en People Analytics
- **Cumplimiento de auditorías:** Las auditorías de protección de datos y de igualdad requieren trazabilidad completa de cambios en las definiciones de métricas. Git proporciona esta trazabilidad.
- **Gestión del riesgo:** La protección de ramas y los status checks obligatorios eliminan el riesgo de que un cambio no revisado llegue a producción y genere reportes incorrectos.
- **Cultura de equipo:** Las prácticas colaborativas (PRs, reviews, documentación) construyen un equipo de datos maduro y profesional, independientemente de su tamaño.

---

## Resumen del módulo

| Tema | Concepto clave | Herramienta |
|------|---------------|-------------|
| 9.1 | Control de versiones para datos | Git, `.gitignore` |
| 9.2 | Estructura de repositorios | Monorepo, carpetas por capa |
| 9.3 | Flujo de ramas | Git flow: main, develop, feature/* |
| 9.4 | Pull requests | Templates, checklist de revisión SQL |
| 9.5 | Versionado Dataform | Integración nativa GitHub-Dataform |
| 9.6 | CI/CD básica | Cloud Build, triggers automáticos |
| 9.7 | Documentación | README, CHANGELOG, diccionario datos |
| 9.8-9.10 | Gobernanza | Branch protection, auditoría, CODEOWNERS |

---

## Preparación para el siguiente módulo

En el **Módulo 10: Backups y Recuperación de Datos en GCP**, aprenderemos a proteger los datos procesados por nuestro pipeline contra pérdida accidental, configurando snapshots, exportaciones y planes de recuperación.
