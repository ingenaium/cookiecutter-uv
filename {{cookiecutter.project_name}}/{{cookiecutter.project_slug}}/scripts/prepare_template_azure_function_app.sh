#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Bootstrap script for:
# - creating a reusable module under src/<project_name>/example_module
# - creating an example Azure Function App under apps/example_function_app
# - wiring the Function App to depend on the root project via uv
#
# Assumptions:
# - You are running this from the root of the repo
# - Root project was created with cookiecutter-uv
#   (override with PROJECT_NAME env var if needed)
# - `uv` and `func` (Azure Functions Core Tools) are installed and on PATH
# -------------------------------------------------------------------

# Auto-detect PROJECT_NAME from pyproject.toml if not provided
if [ -z "${PROJECT_NAME:-}" ]; then
  PROJECT_NAME="$(python - << 'EOF'
import tomllib, pathlib
data = tomllib.loads(pathlib.Path("pyproject.toml").read_text("utf-8"))
name = data["project"]["name"]
print(name.replace("-", "_"))
EOF
)"
fi
MODULE_NAME="${MODULE_NAME:-example_module}"          # reusable module name
APP_DIR_NAME="${APP_DIR_NAME:-example_function_app}"  # folder under apps/
FUNC_NAME="${FUNC_NAME:-ExampleAzureFunctionApp}"     # Azure Function name
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"              # uv Python version

echo "Bootstrapping with:"
echo "  PROJECT_NAME  = ${PROJECT_NAME}"
echo "  MODULE_NAME   = ${MODULE_NAME}"
echo "  APP_DIR_NAME  = ${APP_DIR_NAME}"
echo "  FUNC_NAME     = ${FUNC_NAME}"
echo "  PYTHON_VERSION= ${PYTHON_VERSION}"
echo

# 0) Basic sanity checks
if [ ! -f "pyproject.toml" ]; then
  echo "ERROR: No pyproject.toml found in current directory."
  echo "       Please run this from the root of the cookiecutter-uv project."
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "ERROR: uv not found on PATH. Install uv before running this script."
  exit 1
fi

if ! command -v func >/dev/null 2>&1; then
  echo "ERROR: Azure Functions Core Tools ('func') not found on PATH."
  echo "       Install them before running this script."
  exit 1
fi

# 1) Add a reusable module under src/<project_name>/<module_name>
echo "Creating reusable module src/${PROJECT_NAME}/${MODULE_NAME}..."

mkdir -p "src/${PROJECT_NAME}/${MODULE_NAME}"

cat > "src/${PROJECT_NAME}/${MODULE_NAME}/__init__.py" << 'EOF'
from .example_file import example_function
EOF

cat > "src/${PROJECT_NAME}/${MODULE_NAME}/example_file.py" << 'EOF'
from typing import Any


def example_function() -> bool:
    """
    Example reusable function.
    Replace this with project-specific logic.
    """
    # TODO: implement real logic here
    return True
EOF

echo "Reusable module created at src/${PROJECT_NAME}/${MODULE_NAME}"
echo

# 2) Add the apps directory and scaffold an example Function App inside it
echo "Creating Function App project under apps/${APP_DIR_NAME}..."

mkdir -p "apps/${APP_DIR_NAME}"
cd "apps/${APP_DIR_NAME}"

# 3) Initialise uv for the example Function App project
echo "Initialising uv project for the Function App..."
uv init --python "${PYTHON_VERSION}" >/dev/null

echo "Adding Azure Functions-related dependencies via uv..."
uv add azure-functions azure-ai-documentintelligence azure-storage-blob >/dev/null

# Make the app depend on the root <project_name> package (local editable)
echo "Linking Function App to root package '${PROJECT_NAME}'..."

python - << EOF
from pathlib import Path

pyproj = Path("pyproject.toml")
text = pyproj.read_text(encoding="utf-8")

needle = "dependencies = ["
if needle not in text:
    raise SystemExit("ERROR: Could not find 'dependencies = [' in pyproject.toml. Please add a [project] dependencies list then rerun.")

insert_line = '"${PROJECT_NAME} @ file://../..",\\n    '
text = text.replace(needle, needle + "\\n    " + insert_line)

pyproj.write_text(text, encoding="utf-8")
EOF

echo "Project dependency on '${PROJECT_NAME}' added."
echo

# Initialise Azure Functions in this folder and create a Blob-triggered function
echo "Initialising Azure Functions project (func init)..."
uv run func init . --python >/dev/null

echo "Creating Blob-triggered function '${FUNC_NAME}'..."
uv run func new --name "${FUNC_NAME}" --template "Blob trigger" >/dev/null

echo
echo "Done!"

echo "Created:"
echo "  - Reusable module: src/${PROJECT_NAME}/${MODULE_NAME}/"
echo "  - Function App:    apps/${APP_DIR_NAME}/"
echo "      • Azure Functions scaffolding (host.json, local.settings.json, etc.)"
echo "      • Blob-triggered function: ${FUNC_NAME}"
echo
echo "Next steps:"
echo "  1) Edit the generated function code in apps/${APP_DIR_NAME}/ (inside the function folder)"
echo "  2) Import and use example_function from ${PROJECT_NAME}.${MODULE_NAME}.example_file"
echo "  3) Add any extra dependencies via 'uv add' and then 'uv export' for deployment"