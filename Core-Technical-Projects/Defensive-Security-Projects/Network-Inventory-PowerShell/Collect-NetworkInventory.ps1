[CmdletBinding()]
param(
    [string[]]$ComputerName,
    [string]$ComputerListPath,
    [switch]$UseActiveDirectory,
    [string]$NetworkCIDR,
    [string]$OutputDirectory = (Get-Location).Path
)

function ConvertTo-IPv4Int {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.IPAddress]$IpAddress
    )

    $bytes = $IpAddress.GetAddressBytes()
    [array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function ConvertTo-IPv4Address {
    param(
        [Parameter(Mandatory = $true)]
        [uint32]$Value
    )

    $bytes = [BitConverter]::GetBytes($Value)
    [array]::Reverse($bytes)
    return [System.Net.IPAddress]::new($bytes)
}

function Resolve-NetworkTargets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NetworkCIDR,
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    if ($NetworkCIDR -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})\/(\d{1,2})$') {
        throw "Invalid CIDR format: $NetworkCIDR"
    }

    $ipString = $Matches[1]
    $prefix = [int]$Matches[2]

    if ($prefix -lt 0 -or $prefix -gt 32) {
        throw "CIDR prefix must be between 0 and 32: $NetworkCIDR"
    }

    $parsedAddress = $null
    if (-not [System.Net.IPAddress]::TryParse($ipString, [ref]$parsedAddress)) {
        throw "Invalid IP address in CIDR: $NetworkCIDR"
    }

    $ipAddress = $parsedAddress
    if ($ipAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Only IPv4 CIDR ranges are supported: $NetworkCIDR"
    }
    $ipInt = ConvertTo-IPv4Int -IpAddress $ipAddress
    $mask = if ($prefix -eq 0) { [uint32]0 } else { [uint32]0xFFFFFFFF -shl (32 - $prefix) }
    $network = $ipInt -band $mask
    $hostCount = [uint64][math]::Pow(2, 32 - $prefix)

    $targets = [System.Collections.Generic.List[string]]::new()

    for ($i = [uint64]0; $i -lt $hostCount; $i++) {
        $currentIp = ConvertTo-IPv4Address -Value ([uint32]($network + [uint32]$i))
        $currentIpString = $currentIp.ToString()

        $reachable = Test-Connection -ComputerName $currentIpString -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $reachable) {
            continue
        }

        $hostname = $null
        try {
            $ptrRecord = Resolve-DnsName -Name $currentIpString -Type PTR -ErrorAction Stop
            $hostname = $ptrRecord.NameHost
        } catch {
        }

        if (-not $hostname) {
            try {
                $hostname = [System.Net.Dns]::GetHostEntry($currentIpString).HostName
            } catch {
            }
        }

        if ($hostname) {
            $targets.Add($hostname)
        } else {
            $targets.Add($currentIpString)
        }
    }

    if (-not (Test-Path -Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $targetsFile = Join-Path $OutputDirectory "targets-$timestamp.txt"
    $targets | Set-Content -Path $targetsFile

    [pscustomobject]@{
        Targets     = $targets
        TargetsFile = $targetsFile
    }
}

function Resolve-ComputerTargets {
    param(
        [string[]]$ComputerName,
        [string]$ComputerListPath,
        [switch]$UseActiveDirectory,
        [string]$NetworkTargetsPath
    )

    $targets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($name in ($ComputerName | Where-Object { $_ })) {
        [void]$targets.Add($name)
    }

    if ($ComputerListPath) {
        if (-not (Test-Path -Path $ComputerListPath)) {
            throw "Computer list path not found: $ComputerListPath"
        }

        foreach ($entry in (Get-Content -Path $ComputerListPath)) {
            if ($entry -and $entry.Trim()) {
                [void]$targets.Add($entry.Trim())
            }
        }
    }

    if ($NetworkTargetsPath) {
        if (-not (Test-Path -Path $NetworkTargetsPath)) {
            throw "Network targets path not found: $NetworkTargetsPath"
        }

        foreach ($entry in (Get-Content -Path $NetworkTargetsPath)) {
            if ($entry -and $entry.Trim()) {
                [void]$targets.Add($entry.Trim())
            }
        }
    }

    if ($UseActiveDirectory) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            foreach ($computer in (Get-ADComputer -Filter * | Select-Object -ExpandProperty Name)) {
                if ($computer) {
                    [void]$targets.Add($computer)
                }
            }
        } catch {
            Write-Warning "Active Directory lookup failed: $($_.Exception.Message)"
        }
    }

    return $targets.ToArray()
}

$networkTargetsPath = $null

if ($NetworkCIDR) {
    $networkResult = Resolve-NetworkTargets -NetworkCIDR $NetworkCIDR -OutputDirectory $OutputDirectory
    $networkTargetsPath = $networkResult.TargetsFile
    Write-Host "Network targets saved to $networkTargetsPath"
}

$resolveTargetsParams = @{
    ComputerName       = $ComputerName
    ComputerListPath   = $ComputerListPath
    UseActiveDirectory = $UseActiveDirectory
    NetworkTargetsPath = $networkTargetsPath
}

$resolvedTargets = Resolve-ComputerTargets @resolveTargetsParams

if (-not $resolvedTargets -or $resolvedTargets.Count -eq 0) {
    Write-Warning "No targets resolved. Provide -ComputerName, -ComputerListPath, -UseActiveDirectory, or -NetworkCIDR."
    return
}

Write-Host "Resolved targets:"
$resolvedTargets | ForEach-Object { Write-Host $_ }
