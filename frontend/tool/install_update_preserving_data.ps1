# File Name: install_update_preserving_data.ps1
# Role: Installs a MedBuddy APK as an in-place update without clearing app data.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,

    [string]$Device
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageName = 'com.medbuddy.app'
$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
$adb = (Get-Command adb -ErrorAction Stop).Source
$androidSdkRoot = Split-Path -Parent (Split-Path -Parent $adb)

# Function Name: Resolve-AndroidSdkTool
# Description:
# - Resolves an Android command from PATH or from the SDK that supplied adb.
# - Selects the newest installed build-tools version without changing PATH.
# Parameters:
# - Name: Tool basename without the .bat suffix.
# - SdkRoot: Android SDK root inferred from the selected adb executable.
# Returns:
# - Absolute path to the requested Android SDK tool.
function Resolve-AndroidSdkTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$SdkRoot
    )

    $pathCommand = Get-Command "$Name.bat" -ErrorAction SilentlyContinue
    if ($null -ne $pathCommand) {
        return $pathCommand.Source
    }

    $candidates = if ($Name -eq 'apksigner') {
        Get-ChildItem -LiteralPath (Join-Path $SdkRoot 'build-tools') `
            -Directory -ErrorAction SilentlyContinue |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'apksigner.bat' }
    } elseif ($Name -eq 'apkanalyzer') {
        $latest = Join-Path $SdkRoot 'cmdline-tools\latest\bin\apkanalyzer.bat'
        @($latest) + @(
            Get-ChildItem -LiteralPath (Join-Path $SdkRoot 'cmdline-tools') `
                -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'latest' } |
                Sort-Object { [version]$_.Name } -Descending |
                ForEach-Object { Join-Path $_.FullName 'bin\apkanalyzer.bat' }
        )
    } else {
        @()
    }

    $resolved = $candidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        throw "Could not locate $Name in PATH or Android SDK '$SdkRoot'."
    }
    return $resolved
}

$apkAnalyzer = Resolve-AndroidSdkTool -Name 'apkanalyzer' -SdkRoot $androidSdkRoot
$apkSigner = Resolve-AndroidSdkTool -Name 'apksigner' -SdkRoot $androidSdkRoot

# Function Name: Get-ApkCertificateDigest
# Description:
# - Extracts the first signer SHA-256 certificate digest from apksigner output.
# - Accepts both legacy "Signer #1" and current "V2 Signer" labels.
# Parameters:
# - Apk: Absolute path to an APK that must pass apksigner verification.
# Returns:
# - Lowercase SHA-256 digest without separators.
function Get-ApkCertificateDigest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Apk
    )

    $signerOutput = (& $apkSigner verify --print-certs $Apk 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        throw "APK signature verification failed for '$Apk'."
    }
    $digestMatch = [regex]::Match(
        $signerOutput,
        'certificate SHA-256 digest:\s*([0-9a-fA-F:]+)'
    )
    if (-not $digestMatch.Success) {
        throw "Could not read the APK signing certificate for '$Apk'."
    }
    return $digestMatch.Groups[1].Value.Replace(':', '').ToLowerInvariant()
}

# Step 1: Select exactly one explicitly connected Android device.
if ([string]::IsNullOrWhiteSpace($Device)) {
    $connectedDevices = & $adb devices |
        Select-Object -Skip 1 |
        ForEach-Object { ($_ -split '\s+')[0] } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($connectedDevices.Count -ne 1) {
        throw 'Specify -Device when zero or multiple Android devices are connected.'
    }
    $Device = $connectedDevices[0]
}

# Step 2: Refuse a different package or a version downgrade before installation.
$candidatePackage = (& $apkAnalyzer manifest application-id $resolvedApk).Trim()
if ($candidatePackage -ne $packageName) {
    throw "APK package '$candidatePackage' is not '$packageName'."
}
$candidateVersionCode = [int](& $apkAnalyzer manifest version-code $resolvedApk)
$beforeDump = (& $adb -s $Device shell dumpsys package $packageName) -join "`n"
if ($LASTEXITCODE -ne 0 -or $beforeDump -notmatch 'userId=(\d+)') {
    throw 'MedBuddy is not installed. This command is update-only by design.'
}
$beforeUserId = $Matches[1]
if ($beforeDump -notmatch 'firstInstallTime=([^\r\n]+)') {
    throw 'Could not read MedBuddy first-install metadata.'
}
$beforeFirstInstallTime = $Matches[1].Trim()
if ($beforeDump -notmatch 'versionCode=(\d+)') {
    throw 'Could not read the installed MedBuddy version code.'
}
$installedVersionCode = [int]$Matches[1]
if ($candidateVersionCode -lt $installedVersionCode) {
    throw "Refusing version downgrade $installedVersionCode -> $candidateVersionCode."
}

# Step 3: Compare signing certificates. A mismatch must never trigger uninstall.
$remotePackagePath = (& $adb -s $Device shell pm path $packageName |
    Select-Object -First 1).Trim()
if (-not $remotePackagePath.StartsWith('package:')) {
    throw 'Could not locate the installed MedBuddy APK.'
}
$remotePackagePath = $remotePackagePath.Substring('package:'.Length)
$tempDirectory = Join-Path ([IO.Path]::GetTempPath()) (
    'medbuddy-update-check-' + [Guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $tempDirectory | Out-Null
try {
    $installedApk = Join-Path $tempDirectory 'installed-medbuddy.apk'
    & $adb -s $Device pull $remotePackagePath $installedApk | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not copy the installed APK for signature verification.'
    }

    $candidateCertificate = Get-ApkCertificateDigest -Apk $resolvedApk
    $installedCertificate = Get-ApkCertificateDigest -Apk $installedApk
    if ($candidateCertificate -ne $installedCertificate) {
        throw 'Signing certificate mismatch. Existing app and data were left untouched.'
    }

    # Step 4: Use replace mode only. Never uninstall, clear, or retry destructively.
    & $adb -s $Device install -r $resolvedApk
    if ($LASTEXITCODE -ne 0) {
        throw 'In-place update failed. Existing app and data were left untouched.'
    }
} finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
}

# Step 5: Prove Android retained the package identity and original install time.
$afterDump = (& $adb -s $Device shell dumpsys package $packageName) -join "`n"
if ($afterDump -notmatch 'userId=(\d+)' -or $Matches[1] -ne $beforeUserId) {
    throw 'Package UID changed unexpectedly after installation.'
}
if (
    $afterDump -notmatch 'firstInstallTime=([^\r\n]+)' -or
    $Matches[1].Trim() -ne $beforeFirstInstallTime
) {
    throw 'First-install time changed; this was not a safe in-place update.'
}

Write-Host (
    "MedBuddy updated in place on $Device. " +
    "Package UID $beforeUserId and app data were retained."
)