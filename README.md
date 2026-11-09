# FABRICADO08 Mendix App

This repository contains the **FABRICADO08** Mendix application and its
deployment artifacts. The application model is stored in `App.mpr`; the
exported Mendix deployment package is available at `deployment/app.mda`.

## Requirements

- Mendix Studio Pro compatible with the project version
- Docker, for containerized runtime builds
- PostgreSQL for the Mendix runtime

## Run with Docker

Build the runtime image from the repository root:

```bash
docker build -t fabricado08-mendix .
```

The image exposes the Mendix runtime on port `8080`. Start it with:

```bash
docker run --rm -p 8080:8080 fabricado08-mendix
```

Open [http://localhost:8080](http://localhost:8080) after the runtime starts.

The current container configuration uses these development defaults:

| Setting | Default |
| --- | --- |
| Runtime port | `8080` |
| Admin port | `8090` |
| Database type | PostgreSQL |
| Database host | `127.0.0.1:5432` |
| Database name | `app` |
| Database user | `app` |
| Database password | `app` |

The Docker image does not include PostgreSQL. Before using it in a real
environment, update the generated `m2ee.yaml` configuration in the
`Dockerfile` (or provide an equivalent runtime configuration) with the
database connection details. Replace the default admin password as well.

## Local development

Open `App.mpr` in Mendix Studio Pro to work on the application model. Changes
to the model should be committed together with any relevant generated or
deployment artifacts required by the project workflow.

## Repository layout

| Path | Purpose |
| --- | --- |
| `App.mpr` | Mendix application model |
| `deployment/app.mda` | Exported Mendix deployment package |
| `Dockerfile` | Multi-stage Mendix runtime image |
| `javasource/` | Custom Java actions and generated Java sources |
| `javascriptsource/` | Custom JavaScript and widget sources |
| `userlib/` | Application-specific libraries |
| `vendorlib/` | Third-party libraries |
| `widgets/` | Mendix widget packages |

## Security

Do not use the default database or admin credentials outside local
development. See [SECURITY.md](SECURITY.md) for the vulnerability reporting
policy.
