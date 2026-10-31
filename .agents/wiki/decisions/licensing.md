---
title: Licensing of the repo and the images
category: decision
tags: [license, gpl, agpl, mpl, sbom, compliance]
date: 2026-10-29
---

# Licensing of the repo and the images

## Context

Publishing public images distributes binaries. That brings obligations for
the copyleft software in them: glibc (LGPL) in every image, busybox/git
(GPL-2.0-only) in tofu-ci, HAProxy (GPL-2.0-or-later), signal-cli
(GPL-3.0-only) with libsignal-client (AGPL-3.0-only) and an OpenJDK runtime
(GPL-2.0 WITH Classpath exception), and OpenTofu (MPL-2.0). This page records
an engineering reading, not legal advice.

## Decision

- **Repo: Apache-2.0** (`LICENSE`), matching Wolfi's recipes. It covers the
  configs and scripts only, not the software in the images.
- **Per image:** `org.opencontainers.image.licenses` lists the main
  software's licenses, including bundled copyleft parts (signal-cli:
  `GPL-3.0-only AND AGPL-3.0-only AND GPL-2.0-only WITH
  Classpath-exception-2.0`). melange packages declare `copyright:` so their
  SBOM entry isn't NOASSERTION. The full per-package list is the SPDX SBOM
  attestation.
- **Each component README has a License section**, and the root README has a
  Licenses section with the SBOM query and an "unofficial builds / trademarks"
  notice.
- **User-responsibility disclaimer** in the root README, modelled on Docker
  official images' common license text ("it is the image user's
  responsibility to ensure that any use of this image complies with any
  relevant licenses for all software contained within").
- **Comparison (2026-10-30):** neither Docker official images nor
  images.linuxcontainers.org publish source bundles. Docker lists licenses,
  exact source URLs + SHA256 and snapshot.debian.org links per package in
  `docker-library/repo-info`. linuxcontainers relies on the distros, whose
  packages ship license texts (`/usr/share/doc/*/copyright`) and whose
  archives keep source. Our gaps relative to them: no license texts in the
  images, coarse source pointers, no source archive.

## Open gap

- **Corresponding source is not published by us.** The READMEs point to the
  upstream tags and the wolfi-dev/os recipes. That is a third-party source
  pointer: acceptable under GPLv3 §6(d) with clear directions, weak under
  GPLv2 §3 (busybox, git) and dependent on others keeping old versions up.
- **Done (2026-10-30):** a per-image source manifest attestation
  (`hack/sources.py`, see [[components/build-pipeline]]). It gives exact
  source pins per package plus bundled jars and JDK, with archived copies on
  `tarballs.cgr.dev` for most Wolfi sources. Still a pointer, but exact and
  mostly archived. The archive is Chainguard's, not ours.
- **Stronger fix:** a publish step that collects each image's sources (every
  Wolfi APK embeds its `.melange.yaml` with source URL + commit) and pushes
  them as an OCI artifact attached to the image digest.
- **No license texts in the images:** Wolfi packages don't ship them. A
  melange package that installs them into `/usr/share/licenses` would close
  this.

## Consequences

- New components: set `copyright:` in `melange.yaml`, list bundled copyleft
  licenses in the annotation, and add a README License section.
- Changing the annotation changes `apko.yaml`, so the component needs a
  relock in the same PR.
