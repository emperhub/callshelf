# install.ps1 - put the callshelf panel inside the OpenCode app.
#
# Copies the GUI bundle, its source, and rotate.ps1 into the OpenCode plugin
# directory, then prints what to do. Run it, rerun it after an update.

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$target = Join-Path $env:USERPROFILE '.config\opencode\plugins\callshelf'

New-Item -ItemType Directory -Force $target | Out-Null
New-Item -ItemType Directory -Force (Join-Path $target 'src') | Out-Null

Copy-Item (Join-Path $here 'gui-experimental.cjs') $target -Force
Copy-Item (Join-Path $here 'package.json') $target -Force
Copy-Item (Join-Path $here 'vite.config.ts') $target -Force
Copy-Item (Join-Path $here 'src\*') (Join-Path $target 'src') -Force
Copy-Item (Join-Path $root 'rotate.ps1') $target -Force

Write-Host ''
Write-Host "  installed to $target" -ForegroundColor Green
Write-Host ''
Write-Host '  Open OpenCode Desktop. The panel is under the layout menu on the right'
Write-Host '  edge of a session, listed as "การเชื่อมต่อ". The globe button in the'
Write-Host '  titlebar changes the IP without opening the panel.'
Write-Host ''
