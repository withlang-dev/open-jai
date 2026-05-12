# Public Sources

OpenJai is a clean-room implementation. Implementation work, tests,
diagnostics, examples, and compatibility claims must be derived only from
public information or independently written source code.

This document records acceptable public-source categories and known references.
It is not a complete language specification. When a contribution relies on
non-obvious Jai behavior, cite the relevant public source in the issue, pull
request, commit message, or code comment.

## Acceptable Source Categories

- Public talks, demos, interviews, conference videos, and livestreams.
- Public blog posts and articles.
- Public repositories intentionally published by their authors.
- Public example code and book examples.
- Public screenshots or diagnostics posted by authorized sources.
- Independently written contributor code and tests.
- OpenJai's own source, tests, and documentation.

## Not Acceptable

- Leaked Jai compiler binaries.
- Leaked documentation.
- Private Jai beta materials.
- Private beta forum, Discord, issue-tracker, or chat content.
- Private standard library source.
- Copied diagnostics, screenshots, traces, generated outputs, or binary dumps
  from non-public Jai compiler builds or tools.
- Behavioral claims derived from non-public materials.

## Known Public References

- The OpenJai repository itself.
- `docs/open_jai_spec.md` and other OpenJai docs in this repository.
- Public examples from `The_Way_to_Jai`:
  <https://github.com/Ivo-Balbaert/The_Way_to_Jai>
- Public Focus editor source:
  <https://github.com/focus-editor/focus>
- Public Jai-related posts from The Witness blog, including the testing
  framework article:
  <http://the-witness.net/news/2018/03/testing-the-jai-compiler/>

## Contributor Guidance

If you are unsure whether a source is public enough to use, do not include it.
Instead, reduce the report to independently written source code, a plain-language
expectation, and OpenJai's observed behavior.

Authorized Jai beta users may contribute original source code and reports, but
must not include private Jai materials or copied official compiler output unless
that output is already public and cited.
