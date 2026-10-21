# EXP Synced

One click in the Mod Configuration Menu raises the experience of every party member to the highest in the party.

A mod for Baldur's Gate 3 (Patch 8), made with game version 4.1.1.7398727. It needs
[Norbyte's Script Extender](https://github.com/Norbyte/bg3se) and the
[Mod Configuration Menu](https://github.com/AtilioA/BG3-MCM) (MCM) 1.41. This README is for developers. What the mod
does, how to install it and its compatibility are in [openmods.md](openmods.md), the mod page on
[openmods](https://openmods.nexus).

## How it works

The Mod Configuration Menu page (`MCM_blueprint.json`) has one button, `sync_now` (an `event_button`, no stored
value). MCM runs button callbacks on the client: `Client/Buttons.lua` sends the click over the net channel `Sync`
(`Shared/Common.lua`), and `Server/Sync.lua` answers with the text that MCM shows next to the button.

The server reads the party from the Osiris database `DB_Players` (the active party, the characters of every player
in multiplayer), skips summons (`Osi.IsSummon`) and characters listed twice, and reads each total from the
`Experience` component. Every member below the highest total gets the difference with
`Osi.AddExplorationExperience`, which gives to the named character only; the game flags the level-up itself. The game
adds that experience a moment later, so the server refuses a new sync until the totals arrived or `Sync.WaitTicks`
ticks passed: a second click in between would read the old totals and raise again.

`meta.lsx` lists MCM 1.41.0.0 (`755a8a72-407f-4f0d-9a33-274ac0f0b53d`) as a dependency, so the mod managers load MCM
first; only then does MCM put its `MCM` table into this mod. Without MCM the client log says that the button does
nothing.

## Build

Requirements: Windows PowerShell and [LSLib](https://github.com/Norbyte/lslib/releases) (`Divine.exe`).
`build.ps1` looks for `_tools\lslib\Packed\Tools\Divine.exe` in the parent folders of the project; set `BG3_TOOLS` to
a folder that holds `lslib\` to use another place.

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1             # dist\bg3_expsynced.pak
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Deploy     # build, then copy the .pak to the Mods folder
powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Wait      # copy the .pak when the game is closed
```

`deploy.ps1` copies the .pak to the `Mods` folder below `BG3_DATA_DIR` (the BG3 user-data folder), else to
`%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods`; `-ModsDir` overrides both. The running game locks the .pak, so
the script stops (exit code 2) or, with `-Wait`, waits until the game is closed.

## Project layout

```
src/                                     Mod files (packed into the .pak)
  Mods/bg3_expsynced/meta.lsx           Mod metadata (UUID af368b08-3264-4b59-b4d3-7904864848e2), MCM dependency
  Mods/bg3_expsynced/MCM_blueprint.json The Mod Configuration Menu page (the Sync now button)
  Mods/bg3_expsynced/ScriptExtender/
    Config.json
    Lua/BootstrapServer.lua              Server entry point
    Lua/BootstrapClient.lua              Client entry point
    Lua/Shared/Common.lua                Shared helpers (mod version), button ids, the net channel Sync
    Lua/Shared/FileWriter.lua            Throttled file output in the Script Extender folder
    Lua/Server/Sync.lua                  The sync: party, highest total, raises, the wait for them
    Lua/Server/ServerLog.lua             server.log
    Lua/Client/Buttons.lua               The button callback: sends the click, shows the reply
    Lua/Client/ClientLog.lua             client.log
docs/                                    Cover and screenshots for openmods.md
tests/                                   Offline tests (Lua 5.4 through lupa)
scripts/bump_version.py                  Raises the last version digit in meta.lsx
scripts/show_log.py                      Prints the mod's log files and MCM settings
build.ps1                                Builds dist/bg3_expsynced.pak from src/ (.loca.xml -> .loca, .lsf.lsx -> .lsf)
deploy.ps1                               Copies the .pak to the Mods folder
openmods.json, openmods.md               Data and mod page for openmods.nexus
```

Versioning: every change raises the last version digit (1.0.0.0 -> 1.0.0.1):

```powershell
python scripts\bump_version.py           # both Version64 values in meta.lsx
python scripts\bump_version.py --show
```

Logs: the mod writes `server.log` and `client.log` to
`%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\bg3_expsynced\`. Each load writes a line like
`EXP Synced 1.0.0.1 loaded.`, so the logs show which version runs. Each sync writes one line to server.log, for
example `Sync by peer 65536: highest 6500 (Tav). Gale 2600 -> 6500 (+3900).`, and a second one when the totals
arrived (`Sync arrived after 4 tick(s): Gale 6500.`) or not. The files keep the lines of earlier loads and game
starts (the newest 500 in server.log, 200 in client.log). `python scripts\show_log.py` prints the newest log lines
(from `BG3_DATA_DIR`, if set).

Tests:

```powershell
python -m pip install lupa
python tests\run_tests.py
```

The tests run every mod script against mocks of the Script Extender API (`tests/harness.lua`). The IMGUI, audio and
resource mocks are checked against the Script Extender IDE helpers (`tests/gen_extui_api.py` refreshes
`tests/extui_api.json`), so a property or method that does not exist in the real API fails the tests.

## License

MIT, see [LICENSE](LICENSE).
