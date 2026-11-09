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
docker run --rm -p 8080:8080 \
  -e DATABASE_URL='postgresql://user:password@host:5432/database?sslmode=require' \
  -e MENDIX_ADMIN_PASSWORD='replace-me' \
  fabricado08-mendix
```

Open [http://localhost:8080](http://localhost:8080) after the runtime starts.

The container uses these defaults:

| Setting | Default |
| --- | --- |
| Runtime port | `8080` |
| Admin port | `8090` |
| Database type | PostgreSQL |
| Database connection | `DATABASE_URL` |
| Admin password | `MENDIX_ADMIN_PASSWORD` |

The image does not include PostgreSQL. Set `DATABASE_URL` to the pooled Neon
connection string (including `sslmode=require`) and set
`MENDIX_ADMIN_PASSWORD` before starting the container. The startup script
parses the connection string, enables PostgreSQL SSL, and uses Render's
`PORT` value when it is provided.

## Render deployment

The `Deploy to Render` workflow triggers a Render deploy hook after the
`Build and Commit MDA` workflow succeeds on `main`. Configure the
`RENDER_DEPLOY_HOOK_URL` repository secret with the deploy-hook URL from the
Render service. In the Render web service, configure these environment
variables:

- `DATABASE_URL`: Neon pooled PostgreSQL connection string
- `MENDIX_ADMIN_PASSWORD`: strong Mendix admin password

The workflow can also be started manually from the Actions tab.

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
