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
- Placement remotes carry a slot id and a type id only. The server derives the price from
  config and the final position from the slot anchor.
- Validate on every remote: ownership, distance, cooldown, rate limit. `Net/Router` does all
  four before a service sees the request, and re-checks every payload field's type, because a
  remote argument arrives as whatever the client chose to send.
- Rejection reasons cross the wire as stable codes, never sentences. Wording lives on the
  client so it can change without a server deploy.

**Collect has no remote.** It runs off `ProximityPromptService.PromptTriggered`, which the
engine raises on the server with the triggering player and no payload, so the most repeated
action in the game has nothing to forge. The prompt's `MaxActivationDistance` is a client-side
convenience, not the check: `MachineService` re-measures distance and enforces a per-machine
cooldown server-side.

That server-side distance check could not be driven from a `LocalScript`. Forcing
`prompt:InputHoldBegin()` from 313 studs does not reach the server even after raising the
local `MaxActivationDistance`, so the engine filters out-of-range activation before relaying
it. The check stays as defence against a client that sends the raw activation, but its reject
path is unverified rather than proven.

### Accrual

Machines do not tick. Each stores `lastCollectAt` from `os.time()`, and pending coins are
computed lazily on read:

```
pending = math.min(capacity, ratePerSecond * (os.time() - lastCollectAt))
```

Use `os.time()` and never `tick()` or `os.clock()`, because those do not survive a rejoin.
This is also what makes offline earnings work with no separate system, and the `capacity`
clamp is what stops offline accrual from being an exploit.

The no-tick rule reaches all the way to the display. A machine model carries `Rate`,
`Capacity` and `LastCollectAt` as replicated attributes, written only when one of them
actually changes, and `MachineDisplayController` computes the counter locally from them. A
filling machine costs the server nothing and sends no traffic between collects.

### Runtime-created instances in ReplicatedStorage race a joining client

Remotes are declared in `default.project.json`, not created with `Instance.new` at boot.

The first version created them at server boot. Measured in a live session: the server held all
three, and the client had `BuyMachine` and `Notice` but **not** `Sync`, so the shop silently
never received a snapshot. Re-parenting `Sync` on the server made it appear on the client
immediately, which rules out the instance being wrong and leaves its initial replication never
arriving.

A client's first snapshot of `ReplicatedStorage` is taken as it joins, and a server still
populating a folder at that moment is racing it. In a Studio play session the local player
joins as the server boots, so the race is close to guaranteed there. Declaring the instances
puts them in the place file, inside the initial snapshot, with no window to race.

The cost is accepted: adding a remote now needs a `rojo serve` restart. `Remotes.verify()`
runs at boot and errors naming any remote that is in the name table but not the manifest,
because creating a missing one as a fallback would silently reintroduce the race.

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
- Generalized iteration over a table type whose fields are **named** yields `unknown` values,
  even with the table explicitly annotated. `for _, name in Remotes.names do` cannot then
  assign `name` to a string field. List the entries out, or give the type an indexer and
  accept losing per-field typo checking.
- A variable reassigned inside the loop that tests it stays optional afterwards. Wrap the wait
  in a function that returns the value, so the caller's `if x == nil then return end` narrows
  it, instead of casting at every use.
- An array of mixed instance types infers from its **first element**, so `{ image, label }` is a
  `{ImageLabel}` and the TextLabel is rejected. Annotate it `local children: { Instance } = ...`.
- `UI/create` returns `Instance`. Cast at the binding whenever a property of the concrete class
  is touched later (`:: UIStroke`, `:: TextLabel`), not at each use site.

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

## UI Icon Pack

The purchased Simulator Icon Pack is catalogued in
[`docs/icon-pack-reference.md`](docs/icon-pack-reference.md). It maps all 100 premium icons to
visual descriptions and image asset ids, and records the smaller set currently assigned to
product roles.

Runtime code reads named roles from `src/shared/Config/Icons.luau`. Do not scatter raw image
ids through controllers, and do not commit the purchased catalog model into the place. Keep
text beside any icon whose meaning is not universal.

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

### A play session started right after an edit runs stale code

Rojo only patches the DataModel while Studio is in **Edit** mode. Saving a file and then starting
play immediately gives a session running the previous version, and it looks exactly like the
change not working.

This cost real time twice in one session, including a wrong conclusion about a fix that was
already correct. Confirm the edit landed before starting play, by reading the script's own source
out of the Edit datamodel:

```lua
local source = StarterPlayer.StarterPlayerScripts.Client.UI.Sunburst.Source
return { rayCount = source:match("RAY_COUNT = (%d+)") }
```

The same applies in reverse: files edited while a play session is running do not sync into it, and
stopping play does not always re-apply them.

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

### Slot order is walking order

Slots are handed out lowest-first, so slot 1 has to be the slot nearest the spawn. Spawns sit
at `+spawnForwardOffset` on z, which makes `+z` the front of a plot, so `PlotLayout.slotOffset`
negates its row offset and the rows march away from the player.

Without that negation a new player's first machine appeared at the far edge of their plot, 36
studs away, with eleven empty slots between them and it. **Every layout test still passed**,
because the grid is symmetric under a row flip and every assertion was about centring,
containment or spacing. Only a screenshot showed it. There is now a test for the ordering
itself, and it fails if the negation is removed.

### Screen UI conventions

**Animate `UIScale`, never `Size`.** Tweening `Size` on anything inside a `UIListLayout` re-runs
layout every frame of the tween and shoves its neighbours around. A `UIScale` scales the rendered
result and leaves the layout box alone, so a button can overshoot its own bounds without moving
anything else. `UI/MenuButton` does every state and bounce through one.

**The screen has fixed zones**, so nothing has to negotiate position with anything else:

| Zone | Owner |
|---|---|
| Bottom left | the launcher column, `UI/MenuButton` in a `UIListLayout` |
| Bottom right | the coin bank |
| Bottom centre | the rejection toast |
| Top edge | Roblox. Chat and the player list live there and will sit on top of anything we put there |

**Attention motion is budgeted, not banned.** See the anti-references in `PRODUCT.md` for the
rules and why the original blanket ban was lifted. The short version: launchers only, jittered
interval, never while hovered, pressed, or open, and always skipped under
`GuiService.ReducedMotionEnabled`.

**One glyph per concept.** `Config/Icons.money` is the single money icon, on the bank, the buy
buttons, the collect prompt, and the floating gain. There were two before, and two glyphs for one
concept means a player has to learn that both mean coins.

### `ClipsDescendants` does not clip a rotated descendant

`UI/Sunburst` draws rays as rotated rectangles. The first version overshot them past the container
and set `ClipsDescendants = true` to trim them. The clip was **silently ignored**, because every
ray was rotated, and the rays sprayed out across the world past the edge of the shop panel.

Rotated children have to be bounded by construction. A rectangle no longer than its container is
tall, pinned to the container's centre, stays inside the circle of that diameter at every
rotation, so the container is what guarantees containment and the caller must size it to fit. A
test that measures each ray's half-diagonal against the card bounds is cheaper than trusting it.

### A SpecialMesh inherits its Part's Transparency

`MachineModel` builds an invisible collision `Body` and a separate `Visual` part that carries the
`SpecialMesh`. Only the Body is transparent. Copying `Transparency = 1` onto a mesh carrier makes
the mesh itself render fully transparent, which is how `UI/MachineThumbnail` first shipped nine
blank shop cards with a correctly framed camera pointed at a correctly positioned mesh.

A `FileMesh` SpecialMesh replaces the Part's geometry, so an opaque carrier draws no box. Carriers
are opaque; only a separate collision body is hidden.

### BillboardGui: pixels for identity, studs for detail

A stud-sized BillboardGui grows as you approach it, and there is no minimum-distance property
to stop it. Which sizing is right depends on what the label is for:

- **Plot signs are pixel-sized** (`UDim2.fromOffset`). They are identity labels meant to be
  read from anywhere, so constant screen size is the goal and there are only twelve. Stud
  sizing was tried at 10 and at 5 studs; both filled a third of the screen when the camera sat
  a few studs behind a sign, which is exactly where it sits for a player on the plot in front.
  Shrinking it enough to survive that made it unreadable across the map.
- **Machine labels stay stud-sized.** There can be 144 of them, and the distance falloff is
  what stops a neighbour's plot becoming a wall of text. Nobody needs to read a stranger's
  pending count.

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
