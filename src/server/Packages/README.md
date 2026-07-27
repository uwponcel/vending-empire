# Vendored packages

Third-party modules, committed rather than fetched at build time so a clone builds
offline and a dependency cannot change under us between builds.

Do not edit these files. To update one, re-download at a new pinned commit and record it
here, so the diff is reviewable as "upstream changed" rather than mixed with local edits.

## ProfileStore.luau

| | |
|---|---|
| Upstream | https://github.com/MadStudioRoblox/ProfileStore |
| Pinned commit | `45c9847cbcf1fc260369c50eb335aba7c35aecdd` |
| Commit date | 2025-07-31 |
| SHA-256 | `AD43737203688B8E88CAB34EBE8C483000C157E53BFB41E35F1B49EE89D0C95F` |
| Size | 64654 bytes |
| Modified | No, byte-identical to upstream |

Chosen over ProfileService, which is stable but no longer supported. ProfileStore is the
successor by the same author and resolves session conflicts faster via MessagingService.

Re-download exactly this revision with:

```powershell
curl.exe -fsSL -o src/server/Packages/ProfileStore.luau `
  https://raw.githubusercontent.com/MadStudioRoblox/ProfileStore/45c9847cbcf1fc260369c50eb335aba7c35aecdd/ProfileStore.luau
```

### Constraints it imposes on our schema

Straight from its own header, and the reason `Lib/ProfileSchema` is shaped the way it is:

- No numeric tables with gaps. Saving one is an error, not a silent problem. This is why
  placed machines are a dense array where each record carries its own `slot`, rather than
  a table indexed by slot number.
- No mixed tables. A table is either array-like or string-keyed, never both.
- No Roblox userdata. No `Vector3`, `Color3`, or `CFrame` anywhere in saved data, so plot
  and slot positions are stored as plain numbers and rebuilt at runtime.
- No Instances and no functions.
