# Repository for Kivitendo with Docker.

## Configuration

Deployment config is driven by a `.env` file (gitignored). Pick a database
backend by copying one of the templates:

```bash
cp .env.postgres.example .env        # conventional local PostgreSQL container
# or
cp .env.neon-postgres.example .env   # Neon serverless Postgres (fill in creds)

docker compose up -d --build
```

The single switch is `DB_BACKEND`:

| `DB_BACKEND`    | Database                                | Local `db` container |
|-----------------|-----------------------------------------|----------------------|
| `postgres`      | local PostgreSQL container              | started              |
| `neon-postgres` | Neon serverless Postgres (`.env` creds) | not started          |

`COMPOSE_PROFILES=${DB_BACKEND}` in the `.env` derives the Compose profile from
the switch, so the local `db` service starts only for `postgres`. Neon TLS + the
SNI endpoint fallback are handled automatically for `*.neon.tech` hosts.

### Overriding any setting via environment (Kubernetes / 12-factor)

Any `kivitendo.conf` setting can be overridden with an environment variable —
useful for ConfigMaps and Secrets. Convention:

```text
KIVI_<SECTION>__<KEY> = value
```

- `<SECTION>`: the section, uppercased, with `/` and `-` written as `_`
  (`[authentication/database]` → `AUTHENTICATION_DATABASE`).
- `<KEY>`: the key, uppercased.
- Separator between section and key is a **double** underscore `__`.

```ini
KIVI_AUTHENTICATION__ADMIN_PASSWORD=s3cret
KIVI_AUTHENTICATION_DATABASE__HOST=postgres.default.svc.cluster.local
KIVI_MAIL_DELIVERY__HOST=smtp.example.com
KIVI_SYSTEM__DEFAULT_LANGUAGE=de
```

Only the keys you set are changed; all other defaults and the documentation
comments in `kivitendo.conf` are preserved. The convenience `DB_*` switch above
covers the common database case; `KIVI_*` reaches everything else.

## Roadmap

- [ ] **Shave the last ~180 MB off the image via a minimal `tlmgr` TeX install (later).**
  The image is currently ~1.07 GB (down from 2.5 GB). The Debian base and the
  Perl/Apache/pg-client layer are already at their practical floor; TeXLive
  (~240 MB) is the only substantial lever left. Replace the Debian `texlive-*`
  packages with a minimal `tlmgr` install shipping only the `.sty`/class files
  the templates use — could drop TeX from ~240 MB to ~60 MB.
  - Enumerate required packages with `scripts/installation_check.pl --latex`
    (all master templates) **and** against the real `druckvorlagen/cvs`
    templates (git-ignored, mounted at runtime — must be supplied to test).
  - Known-needed so far: inputenc, fontenc, eurosym, transparent, fontspec,
    embedfile, longtable, colortbl, graphicx, hyperref, geometry, ulem,
    xstring, scrartcl (KOMA), latexsym, textcomp, iftex, ifthen, german.
  - Re-run `installation_check.pl --latex` until all green.
