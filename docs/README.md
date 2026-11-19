# Docs

Plans and normal documentation for the InferiseAnalytics package live in this
directory, and must stay in sync with the code.

- [CONTRIBUTING.md](CONTRIBUTING.md) — commit-message conventions and the
  pull-request process.
- [RELEASING.md](RELEASING.md) — version bump, tagging, and release steps.

Component-local docs stay next to the component (`Examples/README.md`,
`e2e-cli/README.md`, the `VENDORED.md` files). The generated API reference
(DocC, `make docs`) is written to `.build/docs` and is not committed.
