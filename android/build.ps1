# 构建比赛计时 APK（不依赖 Gradle，直接用 SDK 的 aapt2 / d8 / apksigner）
# 注意：aapt2 对非 ASCII 路径不友好，所以所有编译都在英文临时目录里进行，最后再拷回。
param(
    [string]$Toolchain = "",
    [string]$OutFile   = ""
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $OutFile) { $OutFile = Join-Path (Split-Path $here -Parent) '比赛计时.apk' }

# 工具链默认放在用户目录下（与工作区无关，任何项目都能用）
if (-not $Toolchain) {
    foreach ($c in @("$env:USERPROFILE\AndroidTools", "$env:TEMP\android-build")) {
        if (Test-Path (Join-Path $c 'jdk')) { $Toolchain = $c; break }
    }
}
if (-not $Toolchain -or -not (Test-Path (Join-Path $Toolchain 'jdk'))) {
    throw "找不到 Android 构建工具链。应包含 jdk / bt / platform 三个目录，放在 $env:USERPROFILE\AndroidTools 或 %TEMP%\android-build"
}

function Find-Dir($path) {
    $d = Get-ChildItem $path -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $d) { throw "找不到目录: $path" }
    return $d.FullName
}

$jdk  = Find-Dir (Join-Path $Toolchain 'jdk')
$bt   = Find-Dir (Join-Path $Toolchain 'bt')
$plat = Find-Dir (Join-Path $Toolchain 'platform')
$androidJar = Join-Path $plat 'android.jar'

$env:JAVA_HOME = $jdk
$env:PATH = "$jdk\bin;$env:PATH"

$work = Join-Path $env:TEMP 'apk-build-work'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
$stage = Join-Path $work 'proj'
New-Item -ItemType Directory -Force "$work\classes", "$work\dex", "$stage\assets" | Out-Null

Write-Host "[1/7] 准备源码到英文路径"
Copy-Item "$here\res" "$stage\res" -Recurse -Force
Copy-Item "$here\src" "$stage\src" -Recurse -Force
Copy-Item "$here\AndroidManifest.xml" "$stage\AndroidManifest.xml" -Force
Copy-Item (Join-Path (Split-Path $here -Parent) 'index.html') "$stage\assets\index.html" -Force
if (-not (Test-Path "$stage\res\values\styles.xml")) { throw "res 目录复制失败" }

# 之后全是外部命令（javac/d8/aapt2/apksigner），它们会把提示写到 stderr，
# 不能让它触发 PowerShell 的终止错误，统一改成按退出码判断。
$ErrorActionPreference = 'Continue'

Write-Host "[2/7] 编译 Java"
$srcs = Get-ChildItem "$stage\src" -Recurse -Filter *.java | ForEach-Object { $_.FullName }
& "$jdk\bin\javac.exe" -encoding UTF-8 -source 8 -target 8 -nowarn -Xlint:none -classpath $androidJar -d "$work\classes" $srcs
if ($LASTEXITCODE -ne 0) { throw "javac 失败" }

Write-Host "[3/7] 转成 dex"
$classes = Get-ChildItem "$work\classes" -Recurse -Filter *.class | ForEach-Object { $_.FullName }
& "$bt\d8.bat" --release --min-api 24 --lib $androidJar --output "$work\dex" $classes
if ($LASTEXITCODE -ne 0) { throw "d8 失败" }
$dex = Join-Path "$work\dex" 'classes.dex'
if (-not (Test-Path $dex)) { throw "未生成 classes.dex" }

Write-Host "[4/7] 编译资源"
& "$bt\aapt2.exe" compile --dir "$stage\res" -o "$work\res.zip"
if ($LASTEXITCODE -ne 0) { throw "aapt2 compile 失败" }
& "$bt\aapt2.exe" link -o "$work\base.apk" -I $androidJar --manifest "$stage\AndroidManifest.xml" -R "$work\res.zip" -A "$stage\assets" --auto-add-overlay
if ($LASTEXITCODE -ne 0) { throw "aapt2 link 失败" }

Write-Host "[5/7] 写入 dex 并对齐"
$unsigned = "$work\unsigned.apk"
Copy-Item "$work\base.apk" $unsigned -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($unsigned, 'Update')
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $dex, 'classes.dex', [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
$zip.Dispose()
& "$bt\zipalign.exe" -f -p 4 $unsigned "$work\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "zipalign 失败" }

Write-Host "[6/7] 签名"
$ks = Join-Path $Toolchain 'matchtimer.keystore'
if (-not (Test-Path $ks)) {
    $ErrorActionPreference = 'Continue'
    & "$jdk\bin\keytool.exe" -genkeypair -keystore $ks -alias matchtimer -keyalg RSA -keysize 2048 `
        -validity 10950 -storepass matchtimer -keypass matchtimer `
        -dname "CN=Match Timer, O=Local, C=CN" 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
}
if (-not (Test-Path $ks)) { throw "keystore 生成失败" }

$signed = "$work\app-signed.apk"
$ErrorActionPreference = 'Continue'
& "$bt\apksigner.bat" sign --ks $ks --ks-key-alias matchtimer `
    --ks-pass pass:matchtimer --key-pass pass:matchtimer `
    --out $signed "$work\aligned.apk"
$signExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($signExit -ne 0) { throw "apksigner 失败" }

Write-Host "[7/7] 校验并输出"
$ErrorActionPreference = 'Continue'
& "$bt\apksigner.bat" verify --print-certs $signed | Select-Object -First 3
& "$bt\aapt2.exe" dump badging $signed | Select-String -Pattern "package:|application-label:|launchable-activity|sdkVersion|targetSdkVersion" | ForEach-Object { $_.Line }
$ErrorActionPreference = 'Stop'

Copy-Item $signed $OutFile -Force
$size = [math]::Round((Get-Item $OutFile).Length / 1KB, 0)
Write-Host "`n完成: $OutFile ($size KB)"
