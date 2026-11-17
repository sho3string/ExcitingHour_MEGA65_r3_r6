# Exciting Hour — for MEGA65

**Exciting Hour** is Technos Japan's 1985 arcade wrestling game, also released internationally as **Mat Mania**. It features an eight-way joystick, two action buttons and two-player alternating play.

This project is an **independently developed FPGA implementation of Exciting Hour for the MEGA65**. It uses the reusable components from **Jotego's JTFRAME/JTCORES framework**.  

The core uses [MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65) and [QNICE-FPGA](https://github.com/sy2002/QNICE-FPGA) for MEGA65 integration, SD-card ROM loading, configuration and the on-screen menu.

## Credits

- **Technos Japan** — original *Exciting Hour / Mat Mania* arcade game (1985).
- **Taito** — licensed international arcade release.
- **Jotego and JTCORES contributors** — JTFRAME infrastructure and reusable FPGA components used by this project.
- **sy2002, MJoergen and the MiSTer2MEGA65 contributors** — MEGA65 framework and related integration.

This is an unofficial, independently developed FPGA implementation, not an official Technos Japan or Taito release.

## How to install the core

### 1. Obtain the original MAME ROMs

Supply your own compatible **Exciting Hour (`excthour`)** MAME ROM set. You will normally need both of these original archives:

- `excthour.zip` — Exciting Hour-specific program and character ROMs.
- `matmania.zip` — parent set containing shared graphics, sound and colour PROMs.

**ROMs are not included in this repository.** A complete merged archive can also work if it contains all required files.

Unlike cores that load the original chip files directly, **Exciting Hour requires five combined `.rom` images**. The repository provides three independent builders for Windows, Linux and macOS. Each builder performs ROM extraction, ordering and CRC32 verification without calling either of the other scripts.

**Python — Windows / Linux / macOS** (Python 3.8+):

```bash
python3 excthour.py excthour.zip matmania.zip
```

On Windows, `python` can be used instead of `python3` if that is how Python is installed.

**Bash — Linux / macOS**:

```bash
chmod +x excthour.sh
./excthour.sh excthour.zip matmania.zip
```

**PowerShell — Windows** (Windows PowerShell 5.1+ / PowerShell 7+):

```powershell
.\excthour.ps1 .\excthour.zip .\matmania.zip -Set excthour
```

Use **any one** of these scripts; running all three is unnecessary. Run the script from a directory containing the ZIPs, or provide their paths explicitly. The scripts default to the **Exciting Hour** character set.

The five generated files are written to `arcade/matmania/` relative to your current working directory:

| ROM file | Size | CRC32 (Exciting Hour) |
|---|---:|---|
| `matmania_main.rom` | 49,152 bytes | `4FC8FCF9` |
| `matmania_char.rom` | 24,576 bytes | `0F282D69` |
| `matmania_bg.rom` | 49,152 bytes | `42BBC0DD` |
| `matmania_obj.rom` | 344,064 bytes | `348C7774` |
| `matmania_sound.rom` | 32,768 bytes | `571AABAF` |

Copy **all five** generated `.rom` files to this directory on your MEGA65 SD card:

```text
/arcade/matmania/
    matmania_main.rom
    matmania_char.rom
    matmania_bg.rom
    matmania_obj.rom
    matmania_sound.rom
```

**Do not rename the files or put them in `/arcade/excthour/`**; the current core expects the `matmania` directory and these exact filenames.

The builders also produce `jtmm_palette.mem`, a **64-entry RGB444 colour memory file** used when building the FPGA core in Vivado. It is **not** an SD-card ROM and does **not** need to be copied into `/arcade/matmania/` by users installing a compiled `.cor` file.

The optional `--set matmania` (Python/Bash) or `-Set matmania` (PowerShell) selects **Mat Mania character graphics only**. It does not convert the complete game to the Mat Mania program set. Use the default `excthour` selection for this port.

### 2. Install the MEGA65 core

Install the Exciting Hour `.cor` file using the standard MEGA65 core installation procedure. Select a build appropriate for your MEGA65 hardware revision.

### 3. Start the game

Launch the core with the five ROM images present in `/arcade/matmania/`. Press **HELP** to open the MiSTer2MEGA65 on-screen menu for game controls, display settings and the original arcade DIP switches.

## Game setup

### Controls

Exciting Hour uses an **eight-way joystick** and **two action buttons** per player. The original game's moves depend on direction, button combinations and the wrestler's position.

| Game action | MEGA65 joystick input | Keyboard (Player 1) |
|---|---|---|
| Move | Joystick directions | Cursor keys |
| Button 1 | Fire | `Z` |
| Button 2 | POTX or POTY (configurable) | `X` |
| Player 1 start | — | `1` |
| Player 2 start | — | `2` |
| Coin 1 / Coin 2 | — | `5` / `6` |

Under **Game Controls**, the on-screen menu provides:

- **Flip joystick ports** — exchange Player 1 and Player 2 joystick ports.
- **P1/P2 Fire 2 POTX|POTY** — select the physical input used for each player's second action button.
- **P1/P2 Fire 2 polarity** — adjust the active polarity of those POT inputs.
- **Joystick (P1) / Keyboard (P1 only)** — select Player 1's control method. Keyboard mode uses cursor keys and `Z`/`X`; Player 2 uses the joystick.

Start and coin inputs remain available from the keyboard in either control mode.

### DIP switches

The on-screen menu exposes the two original DIP-switch banks as **DSW SW1 & SW2**.

| SW1 | Function |
|---|---|
| SW1-1 / SW1-2 | Coin A — coinage |
| SW1-3 / SW1-4 | Coin B — coinage |
| SW1-5 | Demo Sounds — On / Off |
| SW1-6 | Cabinet — Upright / Cocktail |
| SW1-7 | Service Mode — On / Off |
| SW1-8 | Unused / VBlank-related setting |

| SW2 | Function |
|---|---|
| SW2-1 / SW2-2 | Difficulty |
| SW2-3 / SW2-4 | Match / Tournament Time |
| SW2-5 to SW2-8 | Unused |

Switches are exposed individually in the menu. Certain DIP changes may require a game restart or a new game before their effects become visible.

### Video and audio

The original game uses a **vertical (portrait) display**, with a **256×240** visible picture. The current MEGA65 implementation uses a **6 MHz pixel enable** with **384×264 total timing** (approximately **59.1856 Hz**).

The **Rotate screen 90** setting allows play on a horizontally mounted display. The MiSTer2MEGA65 framework also provides HDMI, CRT-emulation and compatible analogue / 15 kHz video settings through the on-screen menu.

Audio uses **two AY-3-8910-compatible sound generators** together with **DAC sample audio**. The outputs are combined using the **JTFRAME audio mixer**.

## Upstream projects and components

- [JTCORES / JTFRAME — Jotego](https://github.com/jotego/jtcores) (reusable FPGA infrastructure and components)
- [MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65)
- [QNICE-FPGA](https://github.com/sy2002/QNICE-FPGA)

These projects provide infrastructure or components. **The Exciting Hour game-specific FPGA implementation was developed independently for this MEGA65 project.** Individual source files retain their respective copyright notices and licences; consult the repository's licence information.


## Status and issue reports

This README documents the **Exciting Hour (`excthour`)** program and character ROM combination. The ROM builders' alternative `matmania` character option does not establish full support for the Mat Mania program set.

For problems with this MEGA65 implementation, report your MEGA65 hardware revision, ROM archive/set, selected video orientation, observed behaviour and steps to reproduce the issue to this project's issue tracker. Please do not report MEGA65-specific issues to upstream framework projects unless they are also reproducible in those components.
