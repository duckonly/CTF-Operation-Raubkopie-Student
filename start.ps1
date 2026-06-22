$ErrorActionPreference = "Stop"

function Add-PathIfPresent {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return
    }

    if (Test-Path $Candidate) {
        $pathEntries = $env:PATH -split ';'
        if ($pathEntries -notcontains $Candidate) {
            $env:PATH = "$Candidate;$env:PATH"
        }
    }
}

function Ensure-ToolPaths {
    if ($env:ProgramFiles) {
        Add-PathIfPresent (Join-Path $env:ProgramFiles 'RedHat\Podman')
    }
    if (${env:ProgramFiles(x86)}) {
        Add-PathIfPresent (Join-Path ${env:ProgramFiles(x86)} 'RedHat\Podman')
    }
}

function Find-PodmanComposeExecutable {
    $command = Get-Command podman-compose -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $searchRoots = @(
        (Join-Path $env:APPDATA 'Python'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python')
    )

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) {
            continue
        }

        $match = Get-ChildItem -Path $root -Filter 'podman-compose.exe' -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if ($match) {
            Add-PathIfPresent $match.Directory.FullName
            return $match.FullName
        }
    }

    return $null
}

function Install-PodmanComposeProvider {
    $existing = Find-PodmanComposeExecutable
    if ($existing) {
        return $existing
    }

    $pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
    $python = Get-Command python -ErrorAction SilentlyContinue
    $pipInstalled = $false

    if ($pythonLauncher) {
        Write-Host "Installiere fehlenden Podman Compose Provider über 'py -m pip install --user podman-compose' ..."
        & $pythonLauncher.Source -m pip install --user podman-compose
        $pipInstalled = ($LASTEXITCODE -eq 0)
    } elseif ($python) {
        Write-Host "Installiere fehlenden Podman Compose Provider über 'python -m pip install --user podman-compose' ..."
        & $python.Source -m pip install --user podman-compose
        $pipInstalled = ($LASTEXITCODE -eq 0)
    }

    if (-not $pipInstalled) {
        return $null
    }

    return Find-PodmanComposeExecutable
}

function Invoke-NativeQuiet {
    param([scriptblock]$Command)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Command 1>$null 2>$null
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Get-DockerReadyTimeoutSeconds {
    $defaultTimeout = 120
    $configured = $env:DOCKER_READY_TIMEOUT_SECONDS
    if ([string]::IsNullOrWhiteSpace($configured)) {
        return $defaultTimeout
    }

    try {
        $parsed = [int]$configured
        if ($parsed -gt 0) {
            return $parsed
        }
    } catch {}

    return $defaultTimeout
}

function Test-DockerComposeAvailable {
    param([string]$Executable)

    return ((Invoke-NativeQuiet { & $Executable compose version }) -eq 0)
}

function Test-DockerEngineReady {
    param([string]$Executable)

    return ((Invoke-NativeQuiet { & $Executable info }) -eq 0)
}

function Find-DockerDesktopExecutable {
    $candidates = @()

    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe')
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\Docker Desktop.exe')
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA 'Docker\Docker Desktop.exe')
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Start-DockerDesktopIfAvailable {
    param([string]$DockerExecutable)

    if ($IsMacOS) {
        $open = Get-Command open -ErrorAction SilentlyContinue
        if ($open) {
            Write-Host "Docker CLI gefunden, aber Docker Desktop antwortet noch nicht. Starte Docker Desktop ..."
            $exitCode = Invoke-NativeQuiet { & $open.Source -ga Docker }
            if ($exitCode -ne 0) {
                $exitCode = Invoke-NativeQuiet { & $open.Source -a Docker }
            }
            return ($exitCode -eq 0)
        }
        return $false
    }

    $dockerDesktop = Find-DockerDesktopExecutable
    if (-not $dockerDesktop) {
        return $false
    }

    Write-Host "Docker CLI gefunden, aber Docker Desktop antwortet noch nicht. Starte Docker Desktop ..."
    try {
        Start-Process -FilePath $dockerDesktop | Out-Null
        return $true
    } catch {
        Write-Warning "Docker Desktop konnte nicht automatisch gestartet werden: $($_.Exception.Message)"
        return $false
    }
}

function Wait-DockerEngineReady {
    param(
        [string]$Executable,
        [int]$TimeoutSeconds = 120
    )

    $elapsed = 0
    Write-Host "Warte auf Docker Desktop" -NoNewline
    while ($elapsed -lt $TimeoutSeconds) {
        if (Test-DockerEngineReady -Executable $Executable) {
            Write-Host ""
            return $true
        }

        Write-Host "." -NoNewline
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Host ""

    return $false
}

function Test-ComposeCommand {
    param(
        [string]$Executable,
        [string]$Type
    )

    $exitCode = 1
    switch ($Type) {
        'docker' {
            $composeExit = Invoke-NativeQuiet { & $Executable compose version }
            $engineExit = Invoke-NativeQuiet { & $Executable info }
            return ($composeExit -eq 0 -and $engineExit -eq 0)
        }
        'podman' {
            $engineExit = Invoke-NativeQuiet { & $Executable info }
            $composeExit = Invoke-NativeQuiet { & $Executable compose version }
            return ($engineExit -eq 0 -and $composeExit -eq 0)
        }
        'podman-compose' {
            $exitCode = Invoke-NativeQuiet { & $Executable --version }
        }
        default { return $false }
    }

    return ($exitCode -eq 0)
}

function Ensure-PodmanMachine {
    $podman = Get-Command podman -ErrorAction SilentlyContinue
    if (-not $podman) {
        throw "Podman wurde nicht gefunden."
    }

    $machineJson = & $podman.Source machine list --format json 2>$null
    $needsInit = $false

    if ($LASTEXITCODE -ne 0) {
        $needsInit = $true
    } else {
        try {
            $machines = @($machineJson | ConvertFrom-Json)
            if (-not $machines -or $machines.Count -eq 0) {
                $needsInit = $true
            }
        } catch {
            $needsInit = $true
        }
    }

    if ($needsInit) {
        Write-Host "Keine Podman Machine gefunden. Initialisiere Podman ..."
        & $podman.Source machine init
        if ($LASTEXITCODE -ne 0) {
            throw "Podman Machine konnte nicht initialisiert werden. Unter Windows braucht Podman WSL2. Falls WSL fehlt: PowerShell als Administrator öffnen, 'wsl --install --no-distribution' ausführen und Windows neu starten."
        }
    }

    $machineJson = & $podman.Source machine list --format json 2>$null
    $machines = @()
    if ($LASTEXITCODE -eq 0) {
        try {
            $machines = @($machineJson | ConvertFrom-Json)
        } catch {
            $machines = @()
        }
    }

    $runningMachine = $machines | Where-Object { $_.Running -eq $true } | Select-Object -First 1
    if ($runningMachine) {
        return
    }

    Write-Host "Starte Podman Machine ..."
    $startExitCode = Invoke-NativeQuiet { & $podman.Source machine start }
    if ($startExitCode -ne 0) {
        $machineJson = & $podman.Source machine list --format json 2>$null
        if ($LASTEXITCODE -eq 0) {
            try {
                $machines = @($machineJson | ConvertFrom-Json)
                $runningMachine = $machines | Where-Object { $_.Running -eq $true } | Select-Object -First 1
                if ($runningMachine) {
                    return
                }
            } catch {}
        }

        throw "Podman Machine konnte nicht gestartet werden. Falls WSL2 gerade erst installiert wurde, Windows neu starten und erneut versuchen."
    }
}

function Invoke-Compose {
    param(
        [hashtable]$Compose,
        [string[]]$ComposeArgs
    )

    switch ($Compose.Type) {
        'docker' { & $Compose.Executable compose @ComposeArgs }
        'podman' { & $Compose.Executable compose @ComposeArgs }
        'podman-compose' { & $Compose.Executable @ComposeArgs }
        default { throw "Unbekannter Compose-Typ: $($Compose.Type)" }
    }
}

function Ensure-EnvFile {
    param(
        [string]$EnvFile,
        [string]$ExampleFile
    )

    if (-not (Test-Path $EnvFile)) {
        Copy-Item $ExampleFile $EnvFile
        Write-Host "'.env' wurde aus '.env.example' erstellt."
    }

    $lines = Get-Content $EnvFile
    $secretLine = $lines | Where-Object { $_ -match '^CTF_SECRET=' } | Select-Object -First 1
    $secretValue = if ($secretLine) { $secretLine.Split('=', 2)[1] } else { '' }

    if ([string]::IsNullOrWhiteSpace($secretValue) -or $secretValue -eq 'ERSETZE_MICH_MIT_EINEM_ZUFAELLIGEN_GEHEIMNIS') {
        $generatedSecret = [guid]::NewGuid().ToString('N')
        $updated = @()
        $replaced = $false

        foreach ($line in $lines) {
            if ($line -match '^CTF_SECRET=') {
                $updated += "CTF_SECRET=$generatedSecret"
                $replaced = $true
            } else {
                $updated += $line
            }
        }

        if (-not $replaced) {
            $updated += "CTF_SECRET=$generatedSecret"
        }

        Set-Content -Path $EnvFile -Value $updated
        Write-Host "CTF_SECRET wurde automatisch gesetzt."
    }

    $lines = Get-Content $EnvFile
    $imageLine = $lines | Where-Object { $_ -match '^WEB_IMAGE=' } | Select-Object -First 1
    $imageValue = if ($imageLine) { $imageLine.Split('=', 2)[1] } else { '' }
    $exampleLines = Get-Content $ExampleFile
    $templateImageLine = $exampleLines | Where-Object { $_ -match '^WEB_IMAGE=' } | Select-Object -First 1
    $templateImage = if ($templateImageLine) { $templateImageLine.Split('=', 2)[1] } else { '' }
    $officialImagePrefix = 'ghcr.io/duckonly/operation-raubkopie-student:'
    $shouldUpdateImage = $false

    if (-not [string]::IsNullOrWhiteSpace($templateImage) -and $imageValue -ne $templateImage) {
        $shouldUpdateImage = [string]::IsNullOrWhiteSpace($imageValue) `
            -or $imageValue -like "${officialImagePrefix}git-*" `
            -or $imageValue -eq "${officialImagePrefix}latest"
    }

    if ($shouldUpdateImage) {
        $updated = @()
        $replaced = $false

        foreach ($line in $lines) {
            if ($line -match '^WEB_IMAGE=') {
                $updated += "WEB_IMAGE=$templateImage"
                $replaced = $true
            } else {
                $updated += $line
            }
        }

        if (-not $replaced) {
            $updated += "WEB_IMAGE=$templateImage"
        }

        Set-Content -Path $EnvFile -Value $updated
        Write-Host "WEB_IMAGE wurde aus .env.example übernommen."
        $imageValue = $templateImage
    }

    if ([string]::IsNullOrWhiteSpace($imageValue)) {
        throw "WEB_IMAGE ist leer. Nutze ein exportiertes Student-Release oder setze WEB_IMAGE in .env."
    }
}

function Get-ComposeCommand {
    Ensure-ToolPaths

    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($docker) {
        if (Test-DockerComposeAvailable -Executable $docker.Source) {
            if (Test-DockerEngineReady -Executable $docker.Source) {
                return @{
                    Type = "docker"
                    Executable = $docker.Source
                    Label = "docker compose"
                }
            }

            if ((Start-DockerDesktopIfAvailable -DockerExecutable $docker.Source) -and
                (Wait-DockerEngineReady -Executable $docker.Source -TimeoutSeconds (Get-DockerReadyTimeoutSeconds))) {
                return @{
                    Type = "docker"
                    Executable = $docker.Source
                    Label = "docker compose"
                }
            }

            Write-Warning "Docker ist installiert, aber der Docker-Daemon ist nicht bereit. Versuche Podman als Fallback."
        }

        if (Test-ComposeCommand -Executable $docker.Source -Type "docker") {
            return @{
                Type = "docker"
                Executable = $docker.Source
                Label = "docker compose"
            }
        }
    }

    $podman = Get-Command podman -ErrorAction SilentlyContinue
    if ($podman) {
        Ensure-PodmanMachine

        if (Test-ComposeCommand -Executable $podman.Source -Type "podman") {
            return @{
                Type = "podman"
                Executable = $podman.Source
                Label = "podman compose"
            }
        }

        $provider = Install-PodmanComposeProvider
        $podmanReady = (Invoke-NativeQuiet { & $podman.Source info }) -eq 0
        if ($provider -and $podmanReady -and (Test-ComposeCommand -Executable $provider -Type "podman-compose")) {
            return @{
                Type = "podman-compose"
                Executable = $provider
                Label = "podman-compose"
            }
        }
    }

    throw "Kein Compose-Backend gefunden. Installiere Docker Desktop oder Podman Desktop. Für Podman unter Windows kann zusätzlich 'podman-compose' nötig sein."
}

$envFile = Join-Path $PSScriptRoot ".env"
$exampleFile = Join-Path $PSScriptRoot ".env.example"

Ensure-EnvFile -EnvFile $envFile -ExampleFile $exampleFile

$compose = Get-ComposeCommand

Invoke-Compose -Compose $compose -ComposeArgs @("pull")
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Pull mit $($compose.Label) fehlgeschlagen. Fahre mit lokal verfügbaren Images fort."
}

Invoke-Compose -Compose $compose -ComposeArgs @("up", "-d")
if ($LASTEXITCODE -ne 0) {
    throw "Start mit $($compose.Label) fehlgeschlagen."
}

# Ports wie Compose aufloesen: eine gesetzte Umgebungsvariable hat Vorrang vor
# .env, sonst .env, sonst der Standard. Haelt Readiness-Check und URLs konsistent.
$webPort = if ($env:WEB_PORT) { $env:WEB_PORT } else { "8080" }
if (-not $env:WEB_PORT) {
    $portLine = Get-Content $envFile | Where-Object { $_ -match '^WEB_PORT=' } | Select-Object -First 1
    if ($portLine) { $webPort = $portLine.Split("=", 2)[1] }
}

$helperPort = if ($env:HELPER_PORT) { $env:HELPER_PORT } else { "8081" }
if (-not $env:HELPER_PORT) {
    $helperLine = Get-Content $envFile | Where-Object { $_ -match '^HELPER_PORT=' } | Select-Object -First 1
    if ($helperLine) { $helperPort = $helperLine.Split("=", 2)[1] }
}

# Auf Bereitschaft warten (die Datenbank braucht beim ersten Start ~30 Sekunden).
$ready = $false
Write-Host "Starte Dienste" -NoNewline
for ($i = 0; $i -lt 60; $i++) {
    try {
        $w = Invoke-WebRequest -UseBasicParsing -TimeoutSec 6 -Uri "http://localhost:$webPort/index.php" -ErrorAction SilentlyContinue
        $h = Invoke-WebRequest -UseBasicParsing -TimeoutSec 6 -Uri "http://localhost:$helperPort/submit.php" -ErrorAction SilentlyContinue
        if ($w.StatusCode -eq 200 -and $h.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 2
}
Write-Host ""

Write-Host ""
Write-Host "Verwendet: $($compose.Label)"
Write-Host "Webseite: http://localhost:$webPort"
Write-Host "Helper-Portal: http://localhost:$helperPort"
if (-not $ready) {
    Write-Host "Hinweis: Die Dienste antworten noch nicht. Beim ersten Start kann die Datenbank ~30s brauchen; lade die Seite gleich neu. Logs: '$($compose.Label) logs'."
}
Write-Host "Stoppen mit: .\stop.cmd"
