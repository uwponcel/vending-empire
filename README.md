# Vending Empire

A Roblox simulator. Claim a plot, place vending machines, let them fill, walk over and
collect, reinvest in more and better machines. Prestige to reset for a permanent multiplier.

## Status

Phase 0 complete: toolchain, repo skeleton, CI, and a green test harness. No gameplay yet.

## Setup

Requires [Rokit](https://github.com/rojo-rbx/rokit). On Windows:

```powershell
winget install --id Rojo.Rokit --exact
rokit self-install
```

Then from the repository root:

```powershell
rokit install
mkdir build
```

## Development

Sync into an open Roblox Studio session:

```powershell
rojo serve
```

Then open the Rojo panel in Studio and press Connect. The plugin defaults to
`localhost:34872`, which is what `rojo serve` binds.

### Installing the Studio plugin

`rojo plugin install` fails on this machine with `Couldn't find registry keys, Roblox
might not be installed`, because current Studio installs do not write the legacy registry
keys Rojo looks for. Install it from Studio instead: **Plugins -> Manage Plugins ->** find
Rojo, or grab `Rojo.rbxm` from the [7.7.0 release](https://github.com/rojo-rbx/rojo/releases/tag/v7.7.0)
and drop it in `%LOCALAPPDATA%\Roblox\Plugins`.

Keep the plugin version matched to the CLI version in `rokit.toml`. A mismatch shows up as
a protocol error on connect rather than an obvious version warning.

## Validation

```powershell
stylua --check src/ tests/
selene src/
lune run tests/run
rojo build --output build/vending-empire.rbxl
```

CI runs all four on every push and pull request to `main`.

## Layout

| Path | Maps to | Contents |
|---|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` | Config data, pure logic, remote definitions |
| `src/server/` | `ServerScriptService.Server` | Authoritative services and remote handlers |
| `src/client/` | `StarterPlayerScripts.Client` | Controllers and UI |
| `tests/` | n/a | Lune suites for the pure modules |

Modules under `src/shared/Lib/` and `src/shared/Config/` are deliberately free of Roblox
API calls so the test runner can require them directly. See `CLAUDE.md`.
