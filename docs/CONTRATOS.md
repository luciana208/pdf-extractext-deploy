# Contratos entre servicios

Referencia común para los cinco repos. Si un contrato cambia, se cambia acá primero y después en el código y los tests de los dos lados.

## Mapa de servicios

| Servicio | Repo | Host público (HTTPS) | Host interno (red `mired`) | Base de datos |
|---|---|---|---|---|
| Orquestador | `pdf-extractext-orchestrator` | `api.pdfextractext.localhost` | — | — |
| Validación | `pdf-validation-service` | — | `validation.internal:8000` | — |
| Extracción | `pdf-extract-service` | `extract.pdfextractext.localhost` | `extract.internal:8000` | — |
| Persistencia | `pdf-extractext` | — | `documents.internal:8000` | MongoDB |
| Traefik | `pdf-extractext-deploy` | `traefik.pdfextractext.localhost` | entrypoint `internal` (:8000) | — |
| Consul | `pdf-extractext-deploy` | `consul.pdfextractext.localhost` | `consul:8500` | — |

- Los nombres `*.internal` son alias de red del contenedor de Traefik. Cuando un servicio llama a `http://validation.internal:8000`, entra al entrypoint `internal` de Traefik, que balancea entre las réplicas registradas en Consul y aplica el circuit breaker y los reintentos.
- El entrypoint `internal` no se publica en el host: desde afuera solo se llega a `api` y `extract` por HTTPS.
- Extracción es pública porque el TP de carga le pega directo a `/extract`.

## Estándares comunes a los cuatro servicios Python

| Tema | Decisión |
|---|---|
| Python | 3.14 |
| Servidor | Granian (`GRANIAN_PORT`, `GRANIAN_WORKERS`, etc. por entorno) |
| Puerto interno | 8000 (variable `GRANIAN_PORT`; la app la lee para registrarse en Consul) |
| Logs | stdout, formato `fecha nivel modulo: mensaje` |
| Errores | RFC 9457 (`application/problem+json`) en todas las respuestas de error |
| Health | `GET /health`, siempre 200, contrato de abajo |
| Registro | La app se registra sola en Consul al arrancar y se da de baja al apagarse |
| ID de instancia | `<nombre-servicio>-<8 hex aleatorios>`, único por réplica |
| Zona horaria | `America/Argentina/Buenos_Aires` en la imagen; las fechas viajan en ISO 8601 con zona |
| Imagen | Multi-stage, usuario `appuser` sin privilegios, `HEALTHCHECK`, versión semver en el tag |

### Contrato de `/health`

```json
{
  "status": "ok",
  "service": "pdf-extractext",
  "version": "1.0.0",
  "instance_id": "pdf-extractext-1a2b3c4d",
  "uptime_seconds": 120.5,
  "memory_mb": 74.2,
  "requests_in_flight": 0,
  "dependencies": {"mongodb": "ok"}
}
```

- `status` es `ok` si todas las dependencias están `ok`, si no `degraded`. El status HTTP es siempre 200: una dependencia caída se informa, no tumba la instancia.
- `dependencies`: persistencia informa `mongodb`; el orquestador informa los tres servicios internos; validación y extracción no tienen.

### Formato de error (RFC 9457)

```json
{
  "type": "about:blank",
  "title": "Conflict",
  "status": 409,
  "detail": "ya existe un documento con checksum '…'",
  "instance": "https://api.pdfextractext.localhost/api/v1/documents/"
}
```

### Tags de Traefik que manda cada servicio al registrarse

Se arman en `app/infrastructure/traefik_tags.py` a partir de `ROUTER_NAME`, `PUBLIC_HOST` e `INTERNAL_HOST`:

- `traefik.enable=true`
- Middleware `<router>-cb`: circuit breaker con `CIRCUIT_BREAKER_EXPRESSION` (por defecto `NetworkErrorRatio() > 0.5 || ResponseCodeRatio(500, 600, 0, 600) > 0.25`).
- Middleware `<router>-retry`: `RETRY_ATTEMPTS` intentos con `RETRY_INITIAL_INTERVAL`.
- Router `<router>-internal` en el entrypoint `internal` si hay `INTERNAL_HOST`.
- Router `<router>` en `https` con TLS si hay `PUBLIC_HOST`.

## Orquestador (API pública)

Base: `https://api.pdfextractext.localhost/api/v1/documents`. Es la misma API de la Etapa 1, así que el cliente no nota la migración.

| Método | Ruta | Respuesta OK | Errores |
|---|---|---|---|
| `POST` | `/` (multipart: `file`, `custom_name` opcional) | `201` documento | `400`, `409`, `413`, `422`, `503`, `504` |
| `GET` | `/?skip=0&limit=20` | `200` lista | `422` |
| `GET` | `/{id}` | `200` documento | `404` |
| `PUT` | `/{id}` (`{"custom_name": "…"}`) | `200` documento | `404`, `422` |
| `DELETE` | `/{id}` | `200` `{"message": "…"}` | `404` |
| `GET` | `/{id}/download` | `200` `text/plain` con `Content-Disposition` | `404` |

Documento:

```json
{
  "id": "664f2a1b3e8c1a2b3c4d5e6f",
  "name": "informe.pdf",
  "checksum": "a3f1…(64 hex)",
  "extracted_text": "…",
  "text_preview": "… (primeros 500 caracteres)",
  "created_at": "2026-11-13T12:00:00+00:00",
  "updated_at": "2026-11-13T12:00:00+00:00"
}
```

Errores de los servicios internos que traduce el orquestador:

| Lo que pasa adentro | Lo que ve el cliente |
|---|---|
| El servicio responde 400 / 404 / 409 / 413 / 422 | El mismo status, con el `detail` original |
| El servicio responde 5xx, o no se puede conectar | `503 Service Unavailable` |
| El servicio no responde a tiempo | `504 Gateway Timeout` |
| Otro status inesperado | `502 Bad Gateway` |

## Saga de subida

| Paso | Llamada | Si falla | Compensación |
|---|---|---|---|
| 1. validación | `POST validation.internal/api/v1/validations` | termina, no hay nada que deshacer | — |
| 2. reserva | `POST documents.internal/api/v1/documents/reservations` | termina (409 si es duplicado) | `DELETE …/reservations/{id}?saga_id=…` |
| 3. extracción | `POST extract.internal/extract?format=text` | compensa el paso 2 | — |
| 4. confirmación | `PUT documents.internal/api/v1/documents/{id}/content` | compensa el paso 2 | — |

- `saga_id`: UUID hex que genera el orquestador por cada subida. Viaja en la reserva, la confirmación y la compensación, y aparece en todos los logs del orquestador (`saga=… paso=… inicio|ok|fallo`).
- Si la compensación también falla (por ejemplo, persistencia caída), la reserva queda `pending` y la borra el índice TTL de Mongo cuando vence (`RESERVATION_TTL_SECONDS`, 300 por defecto).
- Reintentar una reserva con el mismo `saga_id` devuelve la misma reserva, y reintentar una confirmación ya hecha devuelve el mismo documento. Las dos operaciones son idempotentes.

## Validación (interno)

`POST /api/v1/validations` con el PDF como body binario (`Content-Type: application/pdf`).

```json
{"checksum": "…(64 hex)", "size_bytes": 102400, "page_count": 3}
```

| Status | Cuándo |
|---|---|
| `200` | Pasó todo |
| `400` | Body vacío, no empieza con `%PDF`, no se puede abrir, está protegido con contraseña o no tiene páginas |
| `413` | Supera `MAX_PDF_SIZE_MB` |

Orden: tamaño → firma `%PDF` → apertura (pypdf) → checksum SHA-256.

## Extracción (público e interno)

`POST /extract?format=markdown|text` (por defecto `markdown`). El PDF va como multipart (campo `file`) o como body binario (`application/pdf`).

```json
{"content": "# Título\n\ntexto…", "page_count": 292}
```

| Status | Cuándo |
|---|---|
| `200` | OK |
| `400` | No es PDF, está dañado o protegido |
| `413` | Supera `MAX_PDF_SIZE_MB` |
| `422` | `format` desconocido |
| `503` + `Retry-After` | Hay `MAX_IN_FLIGHT` extracciones en curso (backpressure) |

- El orquestador pide `format=text`, porque la Etapa 1 pide "solamente el texto".
- El TP de carga usa el default `markdown`.
- La extracción corre en un pool de `EXTRACT_WORKERS` procesos, separado del runtime HTTP.

## Persistencia (interno)

Base: `/api/v1/documents`.

| Método | Ruta | Body | Respuesta |
|---|---|---|---|
| `POST` | `/reservations` | `{"saga_id", "checksum", "filename"}` | `201` `{"id", "status": "pending", "expires_at"}`; `409` duplicado; `422` checksum inválido |
| `PUT` | `/{id}/content` | `{"saga_id", "extracted_text"}` | `200` documento; `404` si la reserva no existe, venció o es de otra saga |
| `DELETE` | `/reservations/{id}?saga_id=…` | — | `204` siempre (idempotente) |
| `GET` | `?skip&limit` | — | `200` lista de completados |
| `GET` | `/{id}` | — | `200` documento completado; `404` |
| `PUT` | `/{id}` | `{"custom_name"}` | `200`; `404` |
| `DELETE` | `/{id}` | — | `200` `{"message"}`; `404` |

Colección `documents` en MongoDB:

| Campo | Tipo | Nota |
|---|---|---|
| `name` | string | nombre visible |
| `checksum` | string | índice único `checksum_unique` |
| `extracted_text` | string | vacío mientras está `pending` |
| `status` | `pending` \| `completed` | el CRUD solo ve `completed` |
| `saga_id` | string | dueño de la reserva |
| `expires_at` | fecha \| null | índice TTL `reservation_ttl`; `null` en los completados |
| `created_at`, `updated_at` | fecha UTC | |

## Variables de entorno comunes

| Variable | Ejemplo | Descripción |
|---|---|---|
| `SERVICE_NAME` | `pdf-extract-service` | Nombre en Consul y en los logs |
| `SERVICE_VERSION` | `1.0.0` | Va en `/health` y en la metadata de Consul |
| `LOG_LEVEL` | `INFO` | |
| `GRANIAN_PORT` | `8000` | Puerto del servidor y del registro |
| `CONSUL_ENABLED` | `true` | `false` en tests y desarrollo local |
| `CONSUL_URL` | `http://consul:8500` | |
| `CONSUL_TOKEN` | vacío | Solo si se activa una política ACL restrictiva |
| `SERVICE_ADDRESS` | vacío | Por defecto, la IP del contenedor |
| `HEALTH_CHECK_INTERVAL` | `10s` | Cada cuánto Consul llama a `/health` |
| `ROUTER_NAME` | `extract` | Prefijo de routers y middlewares en Traefik |
| `PUBLIC_HOST` | `extract.pdfextractext.localhost` | Vacío = no se expone por HTTPS |
| `INTERNAL_HOST` | `extract.internal` | Vacío = no tiene router interno |
| `CIRCUIT_BREAKER_EXPRESSION` | ver arriba | |
| `RETRY_ATTEMPTS`, `RETRY_INITIAL_INTERVAL` | `3`, `100ms` | Middleware retry de Traefik |

Las variables propias de cada servicio están en el `.env.example` de cada repo.
