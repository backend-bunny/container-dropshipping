# Renovate: "Error updating branch: update failure"

## Symptom

The Dependency Dashboard lists the melange upstream bump (first seen:
`opentofu/opentofu` 1.13.1 → 1.13.2) under **Errored**, with the repository
problem `WARN: Error updating branch: update failure`. No branch or PR is
created.

## Cause

The regex custom manager used `matchStringsStrategy: "combination"` with two
matchStrings: `# renovate: … version: "…"` and `expected-commit: <sha>`.
With `combination`, Renovate merges the matches into one dependency, and
`replaceString` is the **last** match's text (`mergeExtractionTemplate`:
`addition.replaceString ?? base.replaceString`). It was just the
`expected-commit: …` line. Auto-replace swapped the digest in that line,
couldn't find the version in it, and the post-replace re-extraction then
didn't show the new version, so Renovate aborted with "update failure".

## Fix

There is now one matchString that spans the version and an optional
`vars.expected-commit` right after it, so `replaceString` covers both:

```yaml
package:
  ...
  # renovate: datasource=github-tags depName=opentofu/opentofu
  version: "1.13.1"        # last key of package:
vars:
  expected-commit: <40-hex sha>
pipeline:
  - uses: git-checkout
    with:
      expected-commit: ${{vars.expected-commit}}
```

A component without a pinned commit (signal-cli) just matches the version
part. Keep comments and other keys out of the span between `version:` and
`expected-commit:`, and make sure the version string doesn't appear again
inside that span.
