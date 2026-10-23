---
title: Ephemeral melange keys + keyless cosign
category: decision
tags: [supply-chain, signing, melange, cosign, sigstore]
date: 2026-10-23
---

# Ephemeral melange keys + keyless cosign

## Context

melange signs the APKs it builds, and apko refuses unsigned or untrusted
packages. In `kitty-couple-public/repack` that key was long-lived:
`keys/melange.rsa.pub` committed, private half in the GitLab CI variable
`MELANGE_SIGNING_KEY`. A long-lived key is a secret to rotate, leak and
protect, and nothing outside the build ever verifies those APK signatures.

## Decision

1. **Each build generates a fresh melange keypair** (`melange keygen` in a
   temp dir), signs the APKs, and **deletes the private key immediately**.
   The public half is passed to apko with `--keyring-append` and discarded
   with the job. No melange key is committed, stored as a secret, or reused.
2. **Images are signed keylessly with cosign** using the GitHub Actions OIDC
   token (Sigstore public-good Fulcio + Rekor). The certificate identity is
   the workflow in `backend-bunny/container-dropshipping`.
3. **Attestations:** the apko SPDX SBOM (`cosign attest --type spdxjson`) and
   SLSA provenance (`actions/attest-build-provenance`, pushed to the registry).

The APK signature only bridges melange → apko inside one job. The trust
anchor for consumers is the cosign signature on the image digest.

### Why not a stored melange key?

It would add a secret with no consumer. The APKs are never published, so no
one but the same job verifies their signatures.

### Why not `apko build --ignore-signatures`?

It would also disable verification of Wolfi packages. Wolfi's signature check
still runs with the ephemeral key appended.

### Why not a cosign key pair?

Same rotation and leak problem. Keyless ties signatures to this repo's
workflow identity, recorded in Rekor.

## Implementation

| Piece | Location |
|-------|----------|
| keygen / sign / delete | `hack/lib.sh` `build_packages` |
| pubkey to apko | `--keyring-append out/<c>/melange.rsa.pub` in `hack/build.sh`, `hack/publish.sh` |
| sign + SBOM | `.github/workflows/publish.yml` (cosign from devbox) |
| provenance | `actions/attest-build-provenance` in `publish.yml` |

Verify:

```sh
cosign verify ghcr.io/backend-bunny/<c>@<digest> \
  --certificate-identity-regexp '^https://github.com/backend-bunny/container-dropshipping/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```
