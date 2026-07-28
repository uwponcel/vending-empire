# Simulator Icon Pack Reference

Purchased asset:
[Simulator Icon Pack (100+ Icons)](https://create.roblox.com/store/asset/72859083217455/Simulator-Icon-Pack-100-Icons)
by Hyper_verse.

The source model gives every icon part the same generic name. This reference maps the premium
10 by 10 catalog by visual meaning and image asset id so UI work does not require reinserting
the model into Studio.

## Usage

- Use icons at 32 by 32 through 64 by 64 pixels when practical. This is the size range
  recommended by the pack author.
- Keep icons paired with text when the action is not universally obvious.
- Do not use icon 60 for normal coins. It is specifically a Robux symbol.
- Add product-facing roles to `src/shared/Config/Icons.luau` instead of scattering ids through
  controllers.
- Do not commit the purchased catalog model into the place. The source-controlled asset ids
  are sufficient.

## Active Product Roles

| Role | Catalog | Asset id | Usage |
|---|---:|---|---|
| Shop | 12 | `rbxassetid://92353483125582` | Shop button and panel title |
| Currency / collect | 69 | `rbxassetid://113631549631728` | Coin HUD and collect action |
| Upgrade | 99 | `rbxassetid://99044944223614` | Machine upgrade action |
| Money | 62 | `rbxassetid://77216298800748` | Coin bank, buy buttons, collect prompt, floating gain |
| Close | 19 | `rbxassetid://105424546466549` | Shop panel close button |
| Error | 6 | `rbxassetid://114895557904611` | Rejection and error states |
| Success | 30 | `rbxassetid://113242667524418` | Successful action states |

One glyph per concept. Money used to be two icons, a cash stack on buy buttons and a money bag
on the coin bank, which asked a player to learn that both meant coins. Error used to be catalog
19, the close X, so a rejection toast was fronted by a dismiss glyph while the close button that
actually wanted it had a text "X" instead.

## Full Premium Catalog

| # | Visual description | Asset id |
|---:|---|---|
| 1 | Refresh arrows | `rbxassetid://140356888995605` |
| 2 | Backpack | `rbxassetid://97654479655992` |
| 3 | Sword | `rbxassetid://95675199069972` |
| 4 | Playing cards | `rbxassetid://109242849766217` |
| 5 | Winged timer | `rbxassetid://131334338282798` |
| 6 | Warning triangle | `rbxassetid://114895557904611` |
| 7 | Stacked crates | `rbxassetid://84868341913252` |
| 8 | Bullseye target | `rbxassetid://77208545157515` |
| 9 | Locked padlock | `rbxassetid://101702189763739` |
| 10 | Colour wheel | `rbxassetid://107151528258661` |
| 11 | Cannon | `rbxassetid://116118569409287` |
| 12 | Market stall | `rbxassetid://92353483125582` |
| 13 | Winged heart | `rbxassetid://81067899128123` |
| 14 | Key | `rbxassetid://80630008232905` |
| 15 | Profile portrait | `rbxassetid://91953524875050` |
| 16 | OK button | `rbxassetid://111321965052456` |
| 17 | Trophy | `rbxassetid://100076280689425` |
| 18 | Unlocked padlock | `rbxassetid://73740957850346` |
| 19 | Close X | `rbxassetid://105424546466549` |
| 20 | Paint brush | `rbxassetid://134410683696651` |
| 21 | Hourglass | `rbxassetid://94219343719885` |
| 22 | Chat bubbles | `rbxassetid://91903195156010` |
| 23 | Pause button | `rbxassetid://85880826366176` |
| 24 | Microphone | `rbxassetid://121227464738617` |
| 25 | Megaphone | `rbxassetid://134825208327956` |
| 26 | Magnifying glass | `rbxassetid://124851414845916` |
| 27 | Blueprint tools | `rbxassetid://135598088617740` |
| 28 | Plus | `rbxassetid://71797729371557` |
| 29 | Minus | `rbxassetid://80594865043649` |
| 30 | Checked box | `rbxassetid://113242667524418` |
| 31 | Boxing gloves | `rbxassetid://102718234122110` |
| 32 | Storefront | `rbxassetid://116910537774896` |
| 33 | Knife | `rbxassetid://131664151676481` |
| 34 | Flag | `rbxassetid://71561100193031` |
| 35 | Safe | `rbxassetid://135439314093671` |
| 36 | Fullscreen arrows | `rbxassetid://92920623809751` |
| 37 | Crossed wrench and screwdriver | `rbxassetid://115569927236965` |
| 38 | Play triangle | `rbxassetid://70425581096292` |
| 39 | Dumbbell | `rbxassetid://84635774310557` |
| 40 | Information | `rbxassetid://74137000206933` |
| 41 | Coloured blocks | `rbxassetid://73424075031045` |
| 42 | Puzzle | `rbxassetid://75388368173897` |
| 43 | Gold medal | `rbxassetid://132994120180048` |
| 44 | Pickaxe | `rbxassetid://72722427346761` |
| 45 | Gear | `rbxassetid://75567049874328` |
| 46 | Red round button | `rbxassetid://79681913557488` |
| 47 | Speaker | `rbxassetid://117065366227232` |
| 48 | Sword and shield | `rbxassetid://89157996882459` |
| 49 | First-place podium | `rbxassetid://114167207357375` |
| 50 | Bar chart | `rbxassetid://138656738978264` |
| 51 | Heart | `rbxassetid://109396934425057` |
| 52 | Stop hand | `rbxassetid://136571780595280` |
| 53 | PLAY button | `rbxassetid://90548263515709` |
| 54 | First-aid kit | `rbxassetid://113921777369195` |
| 55 | Ticket | `rbxassetid://98136676128149` |
| 56 | Purple crystal | `rbxassetid://98197360470262` |
| 57 | Crossed swords | `rbxassetid://80261468450266` |
| 58 | Play circle | `rbxassetid://126403737102020` |
| 59 | Dark dumbbell | `rbxassetid://105439046476340` |
| 60 | Robux token | `rbxassetid://127269406927879` |
| 61 | Video | `rbxassetid://70373138578668` |
| 62 | Cash stack | `rbxassetid://77216298800748` |
| 63 | Blue gamepad | `rbxassetid://88101680879675` |
| 64 | Circular profile | `rbxassetid://122070223162584` |
| 65 | Group | `rbxassetid://80494043379929` |
| 66 | Orange back arrow | `rbxassetid://105190581125353` |
| 67 | Shovel | `rbxassetid://138945223030907` |
| 68 | Axe | `rbxassetid://134623875820240` |
| 69 | Money bag | `rbxassetid://113631549631728` |
| 70 | Alert star | `rbxassetid://112746099389120` |
| 71 | Video play button | `rbxassetid://136567491223452` |
| 72 | Exclamation mark | `rbxassetid://93443107130725` |
| 73 | Question mark | `rbxassetid://111781689666930` |
| 74 | Balloon | `rbxassetid://91847488398922` |
| 75 | Egg | `rbxassetid://133978087775350` |
| 76 | Robot | `rbxassetid://121081872707618` |
| 77 | Board-game pawns | `rbxassetid://73431219101776` |
| 78 | Boots | `rbxassetid://78174365684317` |
| 79 | Paw-print cards | `rbxassetid://71484449023331` |
| 80 | Blue crossed tools | `rbxassetid://71448093123902` |
| 81 | Two-person group | `rbxassetid://104503042904374` |
| 82 | Blue undo arrow | `rbxassetid://89392549186681` |
| 83 | Home tools | `rbxassetid://107985512793560` |
| 84 | Music note | `rbxassetid://89818182632754` |
| 85 | Crosshair | `rbxassetid://75739826570262` |
| 86 | Dark gamepad | `rbxassetid://95161328651775` |
| 87 | Server stack | `rbxassetid://73604738534724` |
| 88 | Gear and wrench | `rbxassetid://91535537160383` |
| 89 | Blue diamond medal | `rbxassetid://134919090653225` |
| 90 | Calendar | `rbxassetid://90184202498507` |
| 91 | Portal | `rbxassetid://95066901271471` |
| 92 | Swap arrows | `rbxassetid://123917199753934` |
| 93 | Joystick | `rbxassetid://99787499016048` |
| 94 | Blue back arrow | `rbxassetid://105738318221560` |
| 95 | Red undo button | `rbxassetid://81845304553755` |
| 96 | Cube | `rbxassetid://92380995156671` |
| 97 | Hammer | `rbxassetid://118396702325240` |
| 98 | Target reticle | `rbxassetid://80117795490625` |
| 99 | Up arrow | `rbxassetid://99044944223614` |
| 100 | Purple medal | `rbxassetid://130023142874187` |
