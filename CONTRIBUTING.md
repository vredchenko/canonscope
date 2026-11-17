# Contributing

Thanks for your interest. This is a small hardware project, so the most
valuable contributions are often **reports from real hardware**: a CHDK
camera other than the SX200 IS, a Raspberry Pi model, a distribution the
`.deb` does or doesn't install on. Open an issue with what you ran and what
happened.

## Before you change code

Read [CLAUDE.md](CLAUDE.md). It applies to human contributors as much as to
coding agents. The rules that matter most:

- `tools/` is **bash + coreutils only**.
- The CLI's `--json` output is the contract. A new or changed verb needs a
  matching entry in `tools/canonscope.tools.json`, and the schema test will
  tell you if it is missing.
- Everything must be testable **without a camera**. Extend the fake chdkptp
  in `tools/tests/fake-chdkptp/` rather than skipping a test.
- Docs label every claim **Researched** or **Verified `<date>`**, with the
  source named. Don't claim hardware testing that didn't happen.
- Never test SD-card code against a real card; use a loopback image.

## Running the checks

```sh
./tools/tests/run-tests.sh                                          # CLI + schema
uv run --no-project --with 'mcp==2.3.0' python mcp/test-server.py   # MCP server
tools/check-private.sh --install-hook                               # pre-commit guard
```

`.devcontainer/verify.sh`, inside the dev container, runs everything CI runs,
including shellcheck at warning level. See the README's Development section.

## Commits and pull requests

- Use [Conventional Commit](https://www.conventionalcommits.org/) style
  (`feat:`, `fix:`, `docs:`, `chore:`), matching the history.
- Keep pull requests focused, and say in the description what was tested on
  hardware and what wasn't.
- Releases are cut by maintainers with `packaging/bump-version.sh` and a
  `vX.Y.Z` tag; see the README's Releasing section.

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE).
