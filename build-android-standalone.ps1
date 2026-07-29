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
$embeddedSourceRoot = [IO.Path]::GetFullPath((Join-Path $androidBuildDir "standalone-source"))

if (-not $embeddedSourceRoot.StartsWith($androidBuildDir + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to recreate an unsafe standalone staging path: $embeddedSourceRoot"
}

if (Test-Path -LiteralPath $embeddedSourceRoot) {
    Remove-Item -LiteralPath $embeddedSourceRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $embeddedSourceRoot | Out-Null

$submoduleLines = @(
    & git -C $repoRoot config --file .gitmodules --get-regexp '^submodule\..*\.path$'
)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read data submodules from .gitmodules"
}

$dataSubmodules = @(
    $submoduleLines | ForEach-Object {
        ($_ -split '\s+', 2)[1]
    } | Where-Object {
        $_ -like "data/languages/*" -or $_ -like "data/voices/*"
    } | Sort-Object
)

if ($dataSubmodules.Count -eq 0) {
    throw "No language or voice submodules were found"
}

$archivePath = Join-Path $androidBuildDir "standalone-data.tar"
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
        Write-Host "Packing $relativePath"
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
if (Test-Path -LiteralPath $customVoicesRoot -PathType Container) {
    Write-Host "customvoices is present; valid voices from it will be added to the standalone APK."
} else {
    Write-Host "customvoices is absent; building the standalone APK from repository data only."
}

$arguments = @(
    ":RHVoice-core:assembleStableOptimized"
    "-PRHVoice.embeddedProfile=standalone"
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
$outputApk = Join-Path $outputDir "RHVoice-standalone.apk"
Copy-Item -LiteralPath $sourceApk -Destination $outputApk -Force
Write-Host "Standalone APK: $outputApk"
