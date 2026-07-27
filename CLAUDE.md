# Vending Empire

Roblox simulator. Players place vending machines on a personal plot, machines accrue
coins, players walk up and collect, then reinvest. Shared servers so plots are visible
to other players.

Build plan and phase order: `C:\Users\uwpon\.claude\plans\good-lets-start-working-warm-wreath.md`

## This File and AGENTS.md

`CLAUDE.md` is the source of truth. `AGENTS.md` is a byte-identical copy of it, kept
around because different coding agents look for different filenames. Edit `CLAUDE.md`,
then regenerate:

```powershell
./scripts/sync-agent-docs.ps1
```

CI runs `./scripts/sync-agent-docs.ps1 -Check` and fails on drift, so the two cannot
quietly diverge. If you edited `AGENTS.md` by mistake, the script refuses to clobber it
and tells you how to promote those edits back with `-From Agents`.

## Toolchain

Rokit pins every tool in `rokit.toml`. After cloning:

```powershell
rokit install
```

`~\.rokit\bin` must be on PATH. Tools: `rojo`, `lune`, `stylua`, `selene`, `luau-lsp`.

## Validation

**Every one of these must pass before any phase, feature, or bugfix is called complete.**
Not a subset. CI runs the identical set, so a skipped gate locally just fails later:

```powershell
./scripts/sync-agent-docs.ps1 -Check
stylua --check src/ tests/
selene src/
./scripts/analyze.ps1
lune run tests/run
rojo build --output build/vending-empire.rbxl
```

`build/` is gitignored and Rojo will not create it, so `mkdir build` once per clone.

### The type check is not optional

`--!strict` at the top of a file does **nothing on its own**. Nothing reads it unless an
analyzer runs, and `selene` is a linter, not a type checker. Before `scripts/analyze.ps1`
existed the project had 22 type errors while every other gate reported green, including a
real bug: `expect(next(t))` spreads two return values into a one-argument function.

Never report work as complete on the strength of passing tests alone. Tests and the type
checker catch different things, and a green suite says nothing about the types.

Run `./scripts/analyze.ps1 -Refresh` after adding, moving, or renaming any file. The
sourcemap goes stale and otherwise reports requires that work fine at runtime as unknown.

### First-time setup

`analyze.ps1` needs generated artifacts that are deliberately not committed:

```powershell
./scripts/lsp-setup.ps1
```

That fetches `globalTypes.None.d.luau` (Roblox API types, pinned to the same tag as the
`luau-lsp` in `rokit.toml`), writes `sourcemap.json`, and runs `lune setup`. Versions are
read from `rokit.toml` rather than hardcoded so the definitions cannot drift from the
analyzer that reads them.

The `None` variant is the game-script security level, chosen so that reaching for a
plugin-only API is a type error instead of something that fails at runtime.

### Editor setup

Any editor's Luau language server needs the same three artifacts, so run
`./scripts/lsp-setup.ps1` first, then point it at:

- **Definitions**: `globalTypes.None.d.luau`
- **Sourcemap**: `sourcemap.json`
- **Platform**: `roblox`

`lune setup` writes the `lune` alias into `.luaurc`, which is why that alias is committed
while the typedefs it points at are not. If the editor reports
`Unknown require: tests/@lune/process.lua`, the typedefs are missing or the alias version no
longer matches the pinned `lune`: re-run `lsp-setup.ps1`.

`src/server/Packages` is excluded from the analyzer, `stylua`, and `selene`. It is vendored
code we may not modify, so its diagnostics would be permanent unfixable noise.

## Hard Conventions

### Purity rule

Modules under `src/shared/Lib/` and `src/shared/Config/` must have **zero requires and
zero Roblox API usage**. No `script`, no `game`, no `task`, no services.

This is what makes them requireable by the Lune test runner, which has no Roblox
environment. Composition happens in the service layer, which is Roblox-only and not
unit tested. Dependencies go in as function arguments, not requires:

```lua
-- Yes: config passed in, testable from Lune
function UpgradeCurve.costFor(machineConfig, level) end

-- No: require couples it to the Roblox tree
local Machines = require(script.Parent.Parent.Config.Machines)
```

If a Lune suite suddenly fails to require a shared module, a Roblox API call leaked in.

### Server authority

- The client renders and sends intent. It never sends an amount and never computes balance.
- Every currency mutation goes through the single `EconomyService` entry point, which logs.
- Collect remotes carry a machine id only. The server recomputes the amount from scratch.
- Placement remotes carry a slot id only. The server derives the final `CFrame` from the
  slot anchor.
- Validate on every remote: ownership, distance, cooldown, rate limit.

### Accrual

Machines do not tick. Each stores `lastCollectAt` from `os.time()`, and pending coins are
computed lazily on read:

```
pending = math.min(capacity, ratePerSecond * (os.time() - lastCollectAt))
```

Use `os.time()` and never `tick()` or `os.clock()`, because those do not survive a rejoin.
This is also what makes offline earnings work with no separate system, and the `capacity`
clamp is what stops offline accrual from being an exploit.

### Typing rules learned the hard way

These all come from real errors the analyzer found:

- A module that returns nothing **is not requireable** under strict analysis. Test suites
  register on require and must still `return {}`.
- Declare optional value types as optional. `{ [number]: Player }` compared against nil is a
  type error, because the index type is `Player`, not `Player?`.
- Never reach a runtime-built Instance by dot access. `model.Sign` is both untypeable and a
  hard error if the child is missing. Walk it with `FindFirstChild` and nil-check.
- Wrap multi-return calls in parentheses when passing them as one argument.
  `expect(next(t))` passes **two** arguments; `expect((next(t)))` passes one.
- Annotate function parameters. An unannotated parameter used in arithmetic is a type error,
  not an implicit `any`.
- Prefer a vendored module's exported generic type over `typeof(someCall(...))`. The latter
  is arity-checked and breaks on incomplete upstream annotations.

### Style

- `--!strict` at the top of every module.
- Tabs, 100 column limit, enforced by stylua.
- Types are exported from the module that owns the data (`export type Machine = ...`).
- Comments explain why, not what.
- No emojis, no AI attribution, and no em dashes in code, commits, or PR descriptions.

## Repository Layout

```
src/shared/   -> ReplicatedStorage.Shared   Config (data), Lib (pure logic), Net (remote names)
src/server/   -> ServerScriptService.Server  Services (authoritative), Net (handlers)
src/client/   -> StarterPlayerScripts.Client Controllers, UI
tests/        Lune suites. Add a suite to the explicit list in tests/run.luau.
```

## Studio Workflow

`rojo serve` syncs `src/` into the open Studio session. Verify live behavior through the
Roblox Studio MCP tools rather than by clicking:

- `execute_luau` with `datamodel_type` of `Edit`, `Server`, or `Client`
- `start_stop_play` to reach the `Server` and `Client` datamodels
- `get_console_output` for runtime errors
- `character_navigation` plus `user_keyboard_input` to drive an actual collect
- `screen_capture` to confirm visuals

Pass `path` to `search_game_tree`, for example `"Workspace"`. An unfiltered call returns
roughly 150 services before reaching real content. With two Studio windows open, call
`set_active_studio` first or writes land in the wrong place.

### MCP cannot read service state

`execute_luau` runs in its own script context, so `require` returns a **separate module
instance** from the one the running server loaded. `DataService.get(player)` called through
MCP returns nil even while the server log shows the profile loaded, because the module
table it sees is a fresh empty one.

Verify runtime state through things that actually cross contexts:

- **Instances and attributes** are shared. This is why `PlotService` mirrors ownership onto
  a `Model` attribute even though the server keeps the real table in memory.
- **`print` output**, read back with `get_console_output`.
- **The DataStore itself**, via `ProfileStore:GetAsync(key)`, which reads without taking a
  session lock and so is safe against a live server.

Prefer verifying through production code paths over adding debug hooks. Session playtime is
accumulated by `DataService` on the way out, so a rejoin showing a non-zero playtime proves
the whole save and load round-trip with no test-only code involved.

### Geometry only exists during play

`PlotGeometry.build()` runs on the server at runtime, so Edit mode shows a bare baseplate
and the plot grid appears only in a play session. That is the cost of keeping layout in
source control instead of authoring it in Studio.

### Restarting rojo serve after a manifest change

`rojo serve` reads `default.project.json` once at startup. Editing `$properties` or adding
an instance to the manifest does nothing until the server is restarted and the plugin
reconnects. Source file edits sync normally without a restart.

### Screenshots can beat replication

`screen_capture` taken immediately after `start_stop_play` renders before the client has
finished replicating. Two captures showed 2 and 4 plots on a map that programmatically had
all 12. Confirm object counts with `execute_luau` against the `Client` datamodel before
concluding anything is missing from a screenshot.

## The Place

| | |
|---|---|
| PlaceId | `119229638326166` |
| UniverseId | `10580491481` |
| Baseplate | 2048 studs square, not the 512 a default place suggests |

World settings that must not drift live in `default.project.json`, not in Studio:

- **`StreamingEnabled` is pinned off.** The map is 280 x 208 studs with under 200 parts, so
  streaming buys nothing and only adds replication failure modes. It also has to stay off
  for plots to be visible across the map, which is the comparison mechanic the design rests
  on.
- **Atmosphere density is 0.05.** The default 0.3 hid plots past roughly 200 studs on a grid
  280 wide, so a player on one corner plot could not see the opposite corner.

Pad colour is a functional requirement, not decoration. The first pass used a mid grey that
matched the baseplate's value, making plots invisible from any distance no matter what the
haze was doing.

## DataStores

`ProfileStore` is vendored rather than pulled through Wally, pinned to a commit, and
excluded from both `stylua` and `selene` so it stays byte-identical to upstream. See
`src/server/Packages/README.md`.

DataStore calls fail silently in Studio unless Game Settings -> Security -> Enable Studio
Access to API Services is on. `DataService.start` logs `ProfileStore.DataStoreState` at boot
so a misconfigured place says `NoAccess` instead of looking like saves that do nothing.

### Gapped numeric tables are silently truncated, not rejected

ProfileStore's header warns that saving a numeric table with gaps "will result in an error".
**It does not.** Measured directly against the live DataStore:

| Saved shape | Result | Read back |
|---|---|---|
| `{ {slot=5,...}, {slot=1,...} }` | no error | intact, both records |
| `{ [1]=..., [5]=... }` | no error | **only `[1]`, the slot 5 record is gone** |

The serializer truncates at the first gap and reports nothing. This is why placed machines
are a dense array where each record carries its own `slot`, and it is worse than an error
would have been: a player owning slots 1 and 5 would silently lose a machine on every save
with nothing in any log to trace.

The same class of rule applies to the rest of saved data. No mixed tables, no userdata, no
Instances, no functions. `receipts` is string-keyed for exactly this reason.
