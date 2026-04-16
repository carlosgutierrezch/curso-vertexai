# Curso Vertex AI — People Analytics

## Descripción

Curso práctico de People Analytics utilizando Google Cloud Vertex AI. Se trabaja con datos sintéticos de RRHH para explorar sesgos, fairness en modelos de ML y el stack de GCP.

## Requisitos previos

- Python 3.9+
- Una cuenta de Google Cloud con un proyecto y facturación habilitada
- [Google Cloud CLI (`gcloud`)](https://cloud.google.com/sdk/docs/install) instalado

## Configuración del entorno local

### 1. Clonar el repositorio e instalar dependencias

```bash
cd curso-vertexai-people-analytics
pip install pandas numpy matplotlib seaborn scikit-learn faker google-cloud-aiplatform google-cloud-bigquery
```

### 2. Autenticarse con Google Cloud

```bash
# Iniciar sesión con tu cuenta de Google
gcloud auth login

# Configurar las credenciales por defecto para las librerías de Python
gcloud auth application-default login

# Establecer el proyecto por defecto
gcloud config set project TU_PROJECT_ID
```

### 3. Habilitar las APIs necesarias

```bash
gcloud services enable aiplatform.googleapis.com
gcloud services enable bigquery.googleapis.com
```

### 4. Verificar la configuración

```python
from google.cloud import aiplatform

aiplatform.init(project="TU_PROJECT_ID", location="europe-west1")
print("Conexión con Vertex AI establecida correctamente")
```

## Estructura del curso

| Archivo | Descripción |
|---------|-------------|
| `modulo1_notebook_vertexai.ipynb` | Notebook práctico: datos sintéticos, sesgos, fairness y k-anonimidad |
| `modulo1_contenido_sesion.md` | Contenido teórico de la sesión 1 |
| `modulo1_diapositivas.md` | Diapositivas del Módulo 1 |

## Módulo 1 — Contenido

1. Generación de datos sintéticos de RRHH (2.000 empleados)
2. Introducción de sesgos realistas (brecha salarial, techo de cristal)
3. Exploración y visualización de la plantilla
4. Detección de sesgos con análisis estadístico
5. Proxy discrimination (correlaciones con categorías protegidas)
6. Análisis de k-anonimidad (riesgo de re-identificación)
7. Modelo de predicción de rotación + fairness check
8. Código de referencia para Vertex AI y BigQuery

## Ejecutar el notebook

```bash
# Opción A: Jupyter Notebook
jupyter notebook modulo1_notebook_vertexai.ipynb

# Opción B: VS Code
# Abrir el archivo .ipynb directamente en VS Code

# Opción C: Vertex AI Workbench
# Subir el notebook a tu instancia de Workbench en la consola de GCP
```

## Notas

- El Módulo 1 se puede ejecutar **completamente en local** sin conexión a GCP. La sección 7 del notebook contiene código de referencia para Vertex AI que se usará a partir del Módulo 2.
- El dataset generado se guarda como `people_analytics_sintetico.csv` para su uso en módulos posteriores.
