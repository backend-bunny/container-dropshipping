---
title: crowdsec-web-ui image
category: component
tags: [crowdsec, nodejs, pnpm, npm, melange, distroless, agpl, geonames]
---

# crowdsec-web-ui image

[TheDuffman85/crowdsec-web-ui](https://github.com/TheDuffman85/crowdsec-web-ui)
(TypeScript: Hono server + React/Vite client, SQLite via better-sqlite3)
built from source with melange on Wolfi `nodejs-24`. Distroless.

## Key Facts

- Configs: `components/crowdsec-web-ui/{melange.yaml,apko.yaml,apko.lock.json,test.sh,README.md}`.
- Version **2026.11.3** (CalVer tags without `v`), `expected-commit:
  b04d7a18…`. Renovate: `datasource=github-tags`, default semver versioning
  (`2026.11.3` parses as semver). Upstream releases nearly daily (3 releases
  on 2026-11-02/03, ~13 in October), so a package rule sets schedule
  `* 0-5 * * 1` (Monday morning UTC, around lock-refresh's 05:17) and
  `minimumReleaseAge: 3 days`: at most one PR a week, for a release upstream
  didn't immediately supersede.
- Runtime: `crowdsec-web-ui@local` (deps: `nodejs-24` → glibc, libstdc++,
  icu, openssl …) + `ca-certificates-bundle`. Entrypoint
  `node --env-file=/app/build.env /app/dist/server/index.js`, work dir `/app`.
- Upstream layout kept: app in `/app`, data in `/app/data` (65532, 0750),
  GeoNames in `/app/geonames`. Port 3000, `GET /api/health`.
- Licenses: `AGPL-3.0-only AND CC-BY-4.0` (app + GeoNames). See
  [[decisions/licensing]].

## Build choices

- **pnpm via corepack.** Wolfi's `pnpm` is 10.33; upstream pins 12.16.1 in
  `packageManager`. `corepack pnpm` fetches exactly that, checking npm
  registry signatures. `COREPACK_HOME` and the pnpm store live in the melange
  cache (`/var/cache/melange/{corepack,pnpm-store}`).
- **pnpm 12 lockfiles have two YAML documents**: the first is pnpm's own
  dependencies (`packageManagerDependencies`), the second the project.
  `YAML.parse` throws `MULTIPLE_DOCS`. The bundled-sources script merges the
  `packages:` maps of all documents.
- **better-sqlite3 13 bundles prebuilt addons** (`prebuilds/<platform>.node`,
  8 platforms, 17 MB) and loads them before `build/Release`. Its install
  script builds nothing when a prebuild exists, so
  `npm_config_build_from_source` has no effect. We delete `prebuilds/` and run
  Wolfi's `node-gyp rebuild --release --force_build=1` with
  `npm_config_nodedir=/usr` (`nodejs-24` ships `/usr/include/node`). Only
  `better_sqlite3.node` is installed (SQLite 3.53.4, statically linked).
- **Client licenses from Vite**: a wrapper config
  (`vite.dropship.config.ts`) merges `build.license: {fileName:
  '.vite/license.json'}` into upstream's config. The file is read, then
  deleted from `dist/client` so it isn't served.
- **tsup externalizes every dependency**: the server source maps list only
  `server/` files. The script still scans them, in case that changes.
- **GeoNames** comes from upstream's `scripts/download-geonames-data.mjs` at
  build time. Decided 2026-11-04 to keep it, rather than drop it (that needs
  runtime egress + a writable dir) or self-host a pinned snapshot (manual
  refreshes). It is unversioned upstream, so it's "pinned" by recording
  sha256 + date in `bundled-sources.json`, and two builds on different days
  differ. Without it, reverse geocoding would download at runtime
  (network + writable dir). Lookups work offline with `/app` read-only
  (tested: Stockholm → SE).
- `build.env`: `VITE_*` values as upstream's Dockerfile passes them
  (`VITE_BUILD_DATE` = the tag commit's date, so it's reproducible). Vite
  bakes them into the client. The server reads them through
  `--env-file` (Node ≥ 20.6; process env wins).
- Not shipped: `scripts/`, `pnpm-workspace.yaml`, upstream's entrypoint
  script (chown + gosu: we never run as root). The load-test entry points
  in `dist/server` are, as in upstream's image.

## bundled-sources.json

281 entries on 2026-11-04: 230 npm packages in `node_modules` (7 also in
the client bundle), 49 in the client bundle only, and 2 GeoNames files.
Licenses: MIT 243, ISC 22, BSD-3-Clause 7, Apache-2.0 2, 0BSD 2, 1 combined,
`buffers` NOASSERTION. Packages without any license must be listed in the
script's `NO_LICENSE_REVIEWED` (name@version → note), or the build fails.
The note goes into the entry, and `notices.py` accepts a no-text item only
with one. `chainsaw`'s legacy `MIT/X11` is mapped to `MIT`.
Each entry has `pkg:npm` purl, registry tarball, `sha512:<hex>` checksum and
`where` (node_modules / client bundle).

## Testing locally

melange's `git-checkout` can't reach GitHub from the agent sandbox. The
pipeline was rehearsed step by step in an `apko build-minirootfs` Wolfi
rootfs (the build packages) under nested `bwrap`, with
`NODE_USE_ENV_PROXY=1` for the proxy. Steps were extracted from
`melange.yaml` with `yq`. Every build and test step passed there,
and `hack/notices.py` passed on the generated bundled list.

## Upstream comparison (grype 0.120.0, 2026-11-04)

Upstream `ghcr.io/theduffman85/crowdsec-web-ui:2026.11.3` (node:24
trixie-slim): 200 matches, 103 unique ids (65 High, 76 Medium). 178 are
Debian packages, 18 are npm's own global install
(`/usr/local/lib/node_modules/npm`: undici 6, ip-address, brace-expansion
…), 2 are Go stdlib in `gosu`, and 1 is from the app itself (`csv-parse` 6.2.1,
GHSA-8cw4-87c7-c6xx), which ours ships too.

Ours (same tag, first local build): **1 match**, that same `csv-parse`
Medium (fixed in 7.0.2; it's local-reverse-geocoder's dependency, so it's
upstream's to bump). No Wolfi package matched. The image tarball is 95 MB.

## Gotchas

- **notices.json is 964,349 bytes: 92% of the 1 MiB attestation budget**
  (82 KiB headroom). The largest texts are nodejs-24's 153 KiB `LICENSE`,
  glibc's COPYINGv3 and the AGPL twice (upstream file + canonical). Growth in
  upstream's npm dependencies could fail the build. Options then: drop
  canonical texts when an identical upstream file exists, or compress the
  predicate.
