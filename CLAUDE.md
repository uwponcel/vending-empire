# Vending Empire

Roblox simulator. Players place vending machines on a personal plot, machines accrue
coins, players walk up and collect, then reinvest. Shared servers so plots are visible
to other players.

Build plan and phase order: `C:\Users\uwpon\.claude\plans\good-lets-start-working-warm-wreath.md`

## Toolchain

Rokit pins every tool in `rokit.toml`. After cloning:

```powershell
rokit install
```

`~\.rokit\bin` must be on PATH. Tools: `rojo`, `lune`, `stylua`, `selene`, `luau-lsp`.

## Validation

Run all four before calling any change complete:

```powershell
stylua --check src/ tests/
selene src/
lune run tests/run
rojo build --output build/vending-empire.rbxl
```

`build/` is gitignored and Rojo will not create it, so `mkdir build` once per clone.

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

## DataStores

`ProfileStore` is vendored rather than pulled through Wally. DataStore calls fail silently
in Studio unless Game Settings -> Security -> Enable Studio Access to API Services is on.
