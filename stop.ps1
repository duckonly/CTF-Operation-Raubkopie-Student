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
        return
    }

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

        throw "Podman Machine konnte nicht gestartet werden."
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

function Get-ComposeCommand {
    Ensure-ToolPaths

    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($docker) {
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

        $provider = Find-PodmanComposeExecutable
        $podmanReady = (Invoke-NativeQuiet { & $podman.Source info }) -eq 0
        if ($provider -and $podmanReady -and (Test-ComposeCommand -Executable $provider -Type "podman-compose")) {
            return @{
                Type = "podman-compose"
                Executable = $provider
                Label = "podman-compose"
            }
        }
    }

    throw "Kein Compose-Backend gefunden."
}

$compose = Get-ComposeCommand

Invoke-Compose -Compose $compose -ComposeArgs @("down")
if ($LASTEXITCODE -ne 0) {
    throw "Stoppen mit $($compose.Label) fehlgeschlagen."
}

Write-Host "Challenge gestoppt."
