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
MODULE_NAME="${MODULE_NAME:-example_module}"        # reusable module name
APP_DIR_NAME="${APP_DIR_NAME:-example_function_app}" # folder under apps/
FUNC_NAME="${FUNC_NAME:-ExampleAzureFunctionApp}"   # Azure Function name
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"            # uv Python version

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
from .example_file import example_function as example_function
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
if [ ! -f "pyproject.toml" ]; then
  echo "Initialising uv project for the Function App..."
  uv init --python "${PYTHON_VERSION}" >/dev/null
else
  echo "Function App project already initialised (pyproject.toml exists), skipping uv init..."
fi

echo "Adding Azure Functions-related dependencies via uv..."
uv add azure-functions azure-ai-documentintelligence azure-storage-blob >/dev/null 2>&1 || echo "  (dependencies may already exist)"

# Make the app depend on the root <project_name> package (workspace-style)
echo "Linking Function App to root package '${PROJECT_NAME}' via workspace..."

# Convert underscore to hyphen for package name in dependencies
PACKAGE_NAME=$(echo "${PROJECT_NAME}" | tr '_' '-')

python - << EOF
import tomllib
from pathlib import Path

pyproj = Path("pyproject.toml")
text = pyproj.read_text(encoding="utf-8")

# Check if the dependency is already added
if '"${PACKAGE_NAME}"' in text or "'${PACKAGE_NAME}'" in text:
    print("  Root package dependency already exists in app pyproject.toml, skipping...")
else:
    needle = "dependencies = ["
    if needle not in text:
        raise SystemExit("ERROR: Could not find 'dependencies = [' in pyproject.toml. Please add a [project] dependencies list then rerun.")
    
    insert_line = '"${PACKAGE_NAME}",\\n    '
    text = text.replace(needle, needle + "\\n    " + insert_line)
    
    pyproj.write_text(text, encoding="utf-8")
    print(f"  Added '${PACKAGE_NAME}' to app dependencies.")
EOF

# Now configure the root pyproject.toml for workspace
cd ../..
echo "Configuring root pyproject.toml for workspace..."

python - << EOF
import tomllib
from pathlib import Path

pyproj = Path("pyproject.toml")
text = pyproj.read_text(encoding="utf-8")

# 1. Add workspace member if not present
workspace_member = "apps/${APP_DIR_NAME}"
if "[tool.uv.workspace]" not in text:
    # Add workspace section
    text += '\\n[tool.uv.workspace]\\nmembers = ["' + workspace_member + '"]\\n'
    print(f"  Added [tool.uv.workspace] with member '{workspace_member}'")
elif workspace_member not in text:
    # Workspace exists but this member isn't listed
    # Find the members line and add to it
    lines = text.split("\\n")
    for i, line in enumerate(lines):
        if "members = [" in line and "[tool.uv.workspace]" in "\\n".join(lines[:i+1]):
            # Add to existing members list
            if line.strip().endswith("]"):
                # Single-line members list
                lines[i] = line.replace("]", f', "{workspace_member}"]')
            else:
                # Multi-line members list - add before the closing bracket
                for j in range(i+1, len(lines)):
                    if "]" in lines[j]:
                        lines.insert(j, f'  "{workspace_member}",')
                        break
            text = "\\n".join(lines)
            print(f"  Added '{workspace_member}' to workspace members")
            break
else:
    print(f"  Workspace member '{workspace_member}' already exists")

# 2. Add tool.uv.sources for the root package
package_name = "${PACKAGE_NAME}"
source_entry = f'{package_name} = {{ workspace = true }}'

if "[tool.uv.sources]" not in text:
    # Add sources section
    text += f'\\n[tool.uv.sources]\\n{package_name} = {{ workspace = true }}\\n'
    print(f"  Added [tool.uv.sources] with '{package_name} = {{ workspace = true }}'")
elif source_entry not in text and f'{package_name} =' not in text:
    # Sources section exists but this entry doesn't
    lines = text.split("\\n")
    for i, line in enumerate(lines):
        if "[tool.uv.sources]" in line:
            # Add after this line
            lines.insert(i+1, source_entry)
            text = "\\n".join(lines)
            print(f"  Added '{package_name} = {{ workspace = true }}' to [tool.uv.sources]")
            break
else:
    print(f"  Workspace source for '{package_name}' already exists")

pyproj.write_text(text, encoding="utf-8")
EOF

echo "Workspace configuration complete."
echo

cd "apps/${APP_DIR_NAME}"

# Initialise Azure Functions in this folder and create a Blob-triggered function
if [ ! -f "host.json" ]; then
  echo "Initialising Azure Functions project (func init)..."
  uv run func init . --python --worker-runtime python >/dev/null 2>&1
else
  echo "Azure Functions project already initialised (host.json exists), skipping func init..."
fi

if [ ! -d "${FUNC_NAME}" ]; then
  echo "Creating Blob-triggered function '${FUNC_NAME}'..."
  uv run func new \
    --template "Blob trigger" \
    --name "${FUNC_NAME}" \
    --language Python \
    --authlevel anonymous
else
  echo "Function '${FUNC_NAME}' already exists, skipping func new..."
fi

cd ../..

echo
echo "Syncing workspace dependencies..."
uv sync --all-packages

echo
echo "Done!"

echo "Setup complete:"
echo "  - Reusable module: src/${PROJECT_NAME}/${MODULE_NAME}/"
echo "  - Function App:    apps/${APP_DIR_NAME}/"
echo "      • Azure Functions scaffolding (host.json, local.settings.json, etc.)"
echo "      • Blob-triggered function: ${FUNC_NAME}"
echo "      • Workspace dependency on '${PACKAGE_NAME}' configured"
echo
echo "Next steps:"
echo "  1) Edit the generated function code in apps/${APP_DIR_NAME}/ (inside the function folder)"
echo "  2) Import and use example_function from ${PROJECT_NAME}.${MODULE_NAME}.example_file"
echo "  3) Test locally: cd apps/${APP_DIR_NAME} && uv run func start"
echo "  4) Add any extra dependencies via 'uv add' in the appropriate directory"