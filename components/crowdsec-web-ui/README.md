# crowdsec-web-ui

[TheDuffman85/crowdsec-web-ui](https://github.com/TheDuffman85/crowdsec-web-ui),
a web UI for a CrowdSec LAPI (alerts, decisions, allowlists, notifications),
built from source into a **distroless**, non-root image on Wolfi's Node.js 24.

Image: `ghcr.io/backend-bunny/crowdsec-web-ui` (pin by digest).

## Build

- Upstream release tag (CalVer, e.g. `2026.11.3`, `expected-commit` pinned),
  tracked by Renovate. Upstream releases often, sometimes daily, so Renovate
  opens at most one PR a week (Monday, with the lock refresh), for the newest
  release that's at least 3 days old.
- `corepack pnpm install --frozen-lockfile`: pnpm is the version in upstream's
  `packageManager` field, fetched by corepack with npm registry signature
  checks. Every npm package is pinned by `pnpm-lock.yaml`'s integrity hash.
- **better-sqlite3 is compiled here.** The npm package ships prebuilt addons
  for 8 platforms; they are deleted and the addon (with its bundled SQLite)
  is built with Wolfi's `node-gyp` against Wolfi's node headers and glibc.
  Only `build/Release/better_sqlite3.node` is installed.
- `vite build` (client) and `tsup` (server) as in upstream's Dockerfile, then
  `pnpm prune --prod`. Vite's `build.license` lists the packages compiled
  into the client bundle. The server bundle holds only app code: its npm
  dependencies stay in `node_modules`.
- **GeoNames snapshot** (`cities5000`, `admin1CodesASCII`) is downloaded at
  build time by upstream's script, so reverse geocoding works offline as in
  upstream's image. GeoNames publishes no versioned dumps, so each build gets
  that day's data. Its SHA256 and date are recorded in
  `bundled-sources.json`.
- `/usr/share/doc/crowdsec-web-ui/bundled-sources.json` declares all ~280
  npm packages (shipped in `node_modules` or compiled into the client) with
  `pkg:npm` purl, registry tarball and sha512, and the GeoNames files.
  `hack/sources.py` and `hack/notices.py` read it. notices.py takes license
  files from each registry tarball after checking its sha512.

## Runtime contract

- uid/gid 65532, no shell, `HOME=/home/nonroot`, work dir `/app`.
- Entrypoint: `node --env-file=/app/build.env /app/dist/server/index.js`.
  Upstream's `docker-entrypoint.sh` (chown `/app/data`, drop root via gosu)
  is not used: the image never runs as root.
- `/app/build.env` holds the `VITE_VERSION`/`VITE_COMMIT_HASH`/... values
  upstream sets as image env. The UI uses them for the version display and
  the update check (which reads upstream's GitHub releases). Real env vars
  override them; turn the check off with `updates.enabled: false`.
- Port **3000**, health check `GET /api/health`.
- `/app/data` (0750, uid 65532): `config.yaml`, `state.db` (users,
  notification rules, settings: back it up) and `cache.db`. Mount a PVC here.
  The paths are upstream's, so its docs and `CONFIG_*` variables apply as is.
- `readOnlyRootFilesystem: true` works with `/app/data` mounted: the
  GeoNames snapshot in `/app/geonames` is only read.
- `SSL_CERT_FILE` points at the Wolfi CA bundle (LAPI over TLS, OIDC,
  notification targets).

## Tests

`melange test` loads the better-sqlite3 addon, checks `bundled-sources.json`
and `build.env`, and starts the server against an unreachable LAPI until
`/api/health` answers. `test.sh` checks there is no shell, uid 65532, the
addon and build version in the image, then runs the server with
`--read-only`, `--cap-drop ALL` and a tmpfs `/app/data`, and checks
`/api/health` and the client at `/`.

## License

- crowdsec-web-ui: AGPL-3.0-only (upstream's `LICENSE`; no "or later"
  notice). The image runs it unmodified. Its corresponding source is the
  upstream tag and commit named in `melange.yaml`, also listed in the
  image's source manifest attestation.
- GeoNames data in `/app/geonames`: CC-BY-4.0, © GeoNames
  (<https://www.geonames.org/>).
- npm packages: their own licenses (MIT, ISC, BSD, Apache-2.0, 0BSD, …),
  listed with their texts in the notices attestation. `buffers@0.1.1`, a
  transitive dependency of `local-reverse-geocoder` that upstream's image
  also ships, declares no license, and its repository no longer exists. It
  is recorded as `NOASSERTION` with a review note. It's the only package
  allowed that way (`NO_LICENSE_REVIEWED` in `melange.yaml`): any other
  package without a license fails the build until it's reviewed and added.
- Node.js and the other Wolfi packages: listed per package in the SBOM.

This is an unofficial build, not affiliated with the upstream author or with
CrowdSec.
