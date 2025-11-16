# prepare_template_azure_function_app.sh

Helper script to bootstrap a **reusable module** and an **example Azure Function App** inside a cookiecutter-uv project.

## Usage

From the repo root:

```bash
./scripts/init_example_function_app.sh
```
`

If you get a permissions error, you may need to run `chmod +x scripts/prepare_template_azure_function_app.sh` first.


## What it does

When run from the **root of your project**, the script will:

1. Create a reusable Python module:

   - Location: `src/<PROJECT_NAME>/example_module/`
   - Files:
     - `__init__.py` – exports `example_function`
     - `example_file.py` – contains a simple `example_function()` you can replace

2. Create an Azure Functions app:

   - Location: `apps/example_function_app/` (configurable)
   - Initialises a uv project for this app (`pyproject.toml`)
   - Adds dependencies:
     - `azure-functions`
     - `azure-ai-documentanalysis`
     - `azure-storage-blob`
   - Adds a dependency on the root package:
     - `<PROJECT_NAME> @ file://../..`
   - Runs:
     - `func init . --python`
     - `func new --name ExampleAzureFunctionApp --template "Blob trigger"`

After running, you have:

- A **reusable module** you can import from anywhere in the repo:
  - `from project_xyz.example_module import example_function` (default name)
- A **Function App** ready to be wired to Blob Storage:
  - `apps/example_function_app/...`

You can then implement your real Azure Function logic and call into the shared module.

---

## Assumptions & prerequisites

- The root project was created with **cookiecutter-uv** and has:
  - A `pyproject.toml` at the repo root
  - Source package under `src/project_xyz/` (by default)
- You are running the script from the **root of the repo**.
- Tools installed and on PATH:
  - [`uv`](https://github.com/astral-sh/uv)
  - Azure Functions Core Tools (`func` CLI)

---
