# AI Company OS CLI

Independent CLI interface for reading and operating an AI Company OS repository.

## MVP

The first vertical slice implements:

```powershell
company status
company status --json
```

The repository remains the source of truth. The CLI only reads and reconciles state.

## Development

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[dev]"
pytest
company status --project C:\path\to\ai-company-os
```
