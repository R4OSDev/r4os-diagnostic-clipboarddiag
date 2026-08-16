CLIPD.R4X
=========

CLIPD.R4X ist die Clipboard- und Desktop-Service-Diagnose.

Projektstruktur seit 0.51.21:
- `build.zig` baut die Diagnose als eigenes SDK-Projekt.
- `build.zig.zon` bindet `r4os_sdk` als Paket.
- `module.R4MF` beschreibt Artefakt, Zielpfad, R4L-Imports und Contract.

Build:

    cd Code\System\Diagnostics\ClipboardDiag
    ..\..\..\DevTools\Zig\zig.exe build

Ergebnis:

    Code\System\Diagnostics\ClipboardDiag\zig-out\CLIPD.R4X

Contract:
- Build-Profil: `Zig/R4XStart`
- R4XStart-Entry: `clipd_main`
- App-Klasse: `console`
- R4L-Imports: `R4SYS`, `R4DESK`
- Zielpfad im Image: `C:\R4OS\SOFTWARE\TERMINAL\DIAG\CLIPD.R4X`
