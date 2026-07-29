[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $GradleArguments
)

$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$androidDir = Join-Path $repoRoot "src\android"
$gradleWrapper = Join-Path $androidDir "gradlew.bat"

$configuredJava = if ($env:JAVA_HOME) {
    Join-Path $env:JAVA_HOME "bin\java.exe"
} else {
    $null
}
if (-not $configuredJava -or -not (Test-Path -LiteralPath $configuredJava -PathType Leaf)) {
    $androidStudioJava = "C:\Program Files\Android\Android Studio\jbr\bin\java.exe"
    if (Test-Path -LiteralPath $androidStudioJava -PathType Leaf) {
        $env:JAVA_HOME = Split-Path (Split-Path $androidStudioJava -Parent) -Parent
        $env:Path = (Join-Path $env:JAVA_HOME "bin") + ";" + $env:Path
    }
}

$androidBuildDir = [IO.Path]::GetFullPath((Join-Path $androidDir "build"))
$embeddedSourceRoot = [IO.Path]::GetFullPath((Join-Path $androidBuildDir "standard-source"))
if (-not $embeddedSourceRoot.StartsWith($androidBuildDir + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to recreate an unsafe standard staging path: $embeddedSourceRoot"
}

if (Test-Path -LiteralPath $embeddedSourceRoot) {
    Remove-Item -LiteralPath $embeddedSourceRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $embeddedSourceRoot | Out-Null

$dataSubmodules = @(
    "data/languages/English"
    "data/languages/Russian"
    "data/voices/aleksandr-hq"
    "data/voices/yuriy"
)
$archivePath = Join-Path $androidBuildDir "standard-data.tar"
try {
    foreach ($relativePath in $dataSubmodules) {
        $sourcePath = Join-Path $repoRoot ($relativePath -replace '/', '\')
        if (-not (Test-Path -LiteralPath (Join-Path $sourcePath ".git"))) {
            Write-Host "Initializing $relativePath"
            & git -C $repoRoot submodule update --init --depth 1 -- $relativePath
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to initialize $relativePath"
            }
        }

        $treeEntry = & git -C $repoRoot ls-tree HEAD -- $relativePath
        if ($LASTEXITCODE -ne 0 -or -not $treeEntry) {
            throw "Unable to resolve the pinned commit for $relativePath"
        }
        $commit = ($treeEntry -split '\s+')[2]

        & git -C $sourcePath cat-file -e "$commit`^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Fetching the pinned commit for $relativePath"
            & git -C $repoRoot submodule update --init --depth 1 -- $relativePath
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to fetch the pinned commit for $relativePath"
            }
        }

        $targetPath = Join-Path $embeddedSourceRoot ($relativePath -replace '/', '\')
        New-Item -ItemType Directory -Force -Path $targetPath | Out-Null
        & git -C $sourcePath archive --format=tar "--output=$archivePath" $commit
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to archive $relativePath"
        }
        & tar.exe -xf $archivePath -C $targetPath
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to extract $relativePath"
        }
        Remove-Item -LiteralPath $archivePath -Force
    }
} finally {
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
}

$customVoicesRoot = Join-Path (Split-Path $repoRoot -Parent) "customvoices"
$nestedCustomVoicesDir = Join-Path $customVoicesRoot "data\voices"
$customVoicesDir = if (Test-Path -LiteralPath $nestedCustomVoicesDir -PathType Container) {
    $nestedCustomVoicesDir
} else {
    $customVoicesRoot
}

$customVoiceCount = 0
if (Test-Path -LiteralPath $customVoicesDir -PathType Container) {
    $customVoiceCount = @(
        Get-ChildItem -LiteralPath $customVoicesDir -Directory | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName "voice.info") -PathType Leaf
        }
    ).Count
}

if ($customVoiceCount -gt 0) {
    Write-Host "Building the standard APK with $customVoiceCount custom voice(s)."
} elseif (Test-Path -LiteralPath $customVoicesRoot -PathType Container) {
    Write-Host "customvoices is empty; building the standard APK with the two repository voices."
} else {
    Write-Host "customvoices is absent; building the standard APK with the two repository voices."
}

$arguments = @(
    ":RHVoice-core:assembleStableOptimized"
    "-PRHVoice.embeddedProfile=standard"
    "-PRHVoice.embeddedSourceRoot=$embeddedSourceRoot"
    "--stacktrace"
    "--no-daemon"
) + $GradleArguments

Push-Location $androidDir
try {
    & $gradleWrapper @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$sourceApk = Join-Path $androidDir "RHVoice-core\build\outputs\apk\stable\optimized\RHVoice-core-stable-optimized.apk"
if (-not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) {
    throw "Gradle completed without producing $sourceApk"
}

$outputDir = Join-Path $repoRoot "build\android-packages"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$outputApk = Join-Path $outputDir "RHVoice-standard.apk"
Copy-Item -LiteralPath $sourceApk -Destination $outputApk -Force
Write-Host "Standard APK: $outputApk"
