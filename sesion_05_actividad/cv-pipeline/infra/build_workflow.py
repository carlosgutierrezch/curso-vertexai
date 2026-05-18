"""Ensambla infra/workflow.yaml a partir de workflow_template.yaml + steps/*.yaml.

Lee todos los fragmentos en infra/steps/ en orden alfabético y los inyecta
en el marcador `# __PIPELINE_STEPS__` del template. El resultado se escribe
en infra/workflow.yaml (gitignored), que es el artefacto desplegable.
"""

from pathlib import Path

MARKER = "# __PIPELINE_STEPS__"


def build() -> Path:
    infra_dir = Path(__file__).parent
    template_path = infra_dir / "workflow_template.yaml"
    steps_dir = infra_dir / "steps"
    output_path = infra_dir / "workflow.yaml"

    template = template_path.read_text()

    step_files = sorted(steps_dir.glob("*.yaml"))
    if not step_files:
        raise RuntimeError(f"No step files found in {steps_dir}")

    steps_block = "\n".join(p.read_text().rstrip() for p in step_files)

    if MARKER not in template:
        raise RuntimeError(f"Marker {MARKER!r} not found in {template_path}")

    rendered = template.replace(MARKER, steps_block.lstrip())
    output_path.write_text(rendered)

    print(f"Wrote {output_path} ({len(step_files)} steps merged)")
    return output_path


if __name__ == "__main__":
    build()
