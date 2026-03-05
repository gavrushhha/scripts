# VersionedCopyWatcher.ps1
# Мониторинг папки и копирование изменённых файлов с версионным именем: имя_файла_дата_время.расширение

param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Dest,
    [string]$LogFile = "",
    [int]$StabilizationMs = 2000
)

$ErrorActionPreference = "Continue"
$Source = $Source.TrimEnd('\')
$Dest = $Dest.TrimEnd('\')

function Write-Log {
    param([string]$Message)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message
    Write-Host $line
    if ($LogFile) {
        Add-Content -LiteralPath $LogFile -Value $line -ErrorAction SilentlyContinue
    }
}

# Очередь файлов для копирования (путь -> время последнего изменения)
$pendingFiles = @{}
$lock = [System.Object]::new()

function Copy-FileVersioned {
    param([string]$FullPath)
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) { return }
    try {
        $rel = $FullPath
        if ($FullPath.StartsWith($Source, [StringComparison]::OrdinalIgnoreCase)) {
            $rel = $FullPath.Substring($Source.Length).TrimStart('\', '/')

        $dir = [System.IO.Path]::GetDirectoryName($rel)
        $fileName = [System.IO.Path]::GetFileName($FullPath)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FullPath)
        $ext = [System.IO.Path]::GetExtension($FullPath)
        $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $versionedName = "${baseName}_${timestamp}${ext}"
        $destDir = if ($dir) { Join-Path $Dest $dir } else { $Dest }
        $destPath = Join-Path $destDir $versionedName
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $FullPath -Destination $destPath -Force
        Write-Log "OK: $rel -> $versionedName"
    } catch {
        Write-Log "ERROR: $FullPath - $_"
    }
}

function Process-PendingFiles {
    $toCopy = @()
    [System.Threading.Monitor]::Enter($lock)
    try {
        $now = Get-Date
        foreach ($path in $pendingFiles.Keys) {
            $lastChange = $pendingFiles[$path]
            if (($now - $lastChange).TotalMilliseconds -ge $StabilizationMs) {
                $toCopy += $path
            }
        }
        foreach ($p in $toCopy) { $pendingFiles.Remove($p) | Out-Null }
    } finally {
        [System.Threading.Monitor]::Exit($lock)
    }
    foreach ($path in $toCopy) {
        Copy-FileVersioned -FullPath $path
    }
}

function Add-ToQueue {
    param([string]$FullPath)
    if (-not $FullPath -or -not (Test-Path -LiteralPath $FullPath -PathType Leaf)) { return }
    [System.Threading.Monitor]::Enter($lock)
    try {
        $pendingFiles[$FullPath] = Get-Date
    } finally {
        [System.Threading.Monitor]::Exit($lock)
    }
}

$timer = [System.Timers.Timer]::new([Math]::Max(500, [Math]::Min($StabilizationMs, 5000)))
$timer.AutoReset = $true
$timer.Add_Elapsed({
    Process-PendingFiles
})
$timer.Start()

$fsw = [System.IO.FileSystemWatcher]::new()
$fsw.Path = $Source
$fsw.IncludeSubdirectories = $true
$fsw.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite

$onChange = {
    $path = $Event.SourceEventArgs.FullPath
    if ([System.IO.File]::Exists($path)) {
        Add-ToQueue -FullPath $path
    }
}

Register-ObjectEvent -InputObject $fsw -EventName Created -Action $onChange | Out-Null
Register-ObjectEvent -InputObject $fsw -EventName Changed -Action $onChange | Out-Null
$fsw.EnableRaisingEvents = $true

Write-Log "Versioned copy watcher started. Source: $Source , Dest: $Dest (format: name_yyyy-MM-dd_HHmmss.ext). Press Ctrl+C to stop."

try {
    while ($true) { Start-Sleep -Seconds 10; Process-PendingFiles }
} finally {
    $timer.Stop()
    $fsw.EnableRaisingEvents = $false
    Get-EventSubscriber | Unregister-Event -ErrorAction SilentlyContinue
    Process-PendingFiles
    Write-Log "Stopped."
}
