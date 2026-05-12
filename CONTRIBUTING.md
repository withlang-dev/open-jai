# Contributing To OpenJai

OpenJai is intended to be a clean-room implementation developed only from
public information.

## Clean-Room Rule

Do not submit issues, tests, patches, diagnostics, screenshots, traces,
generated outputs, behavioral claims, or compatibility reports derived from:

- leaked Jai compiler builds
- leaked documentation
- private Jai beta materials
- private beta forum, Discord, or issue-tracker content
- copied output from any non-public Jai compiler or tool
- any other non-public source

If you are an authorized Jai beta user, you may report compatibility issues
using your own source code, but do not include proprietary/private Jai materials
or copied compiler output. Avoid claims like "Jai currently does X" unless the
claim is sourced from public material. Describe the problem in terms of source
you have the right to share, public language information, and OpenJai's observed
behavior.

Contributions should be based on public sources such as public talks, public
blog posts, public example code, public repositories, and independently written
tests. When in doubt, leave the private material out.

Tests should assert behavior from public specifications, public examples, or
independent reasoning. Do not create tests by comparing against non-public
official compiler output. Official Jai output is acceptable only when it appears
in public material that can be cited.

## Public Sources

When a change depends on non-obvious language behavior, cite a public source in
the issue, pull request, commit message, or code comment. The project maintains
a bibliography of acceptable source categories and known references in
[`docs/public_sources.md`](docs/public_sources.md).

## Maintainer Policy

The project may reject or remove contributions that appear to rely on
non-public Jai materials, even if the contribution is technically useful.

Maintainers may close issues or pull requests that do not satisfy the
clean-room rule. If non-public material is submitted, maintainers may delete the
content and, when necessary, remove it from git history.

Use a `cleanroom` label for issues or pull requests that need provenance review,
and `needs-public-source` when a behavioral claim needs a public citation.
