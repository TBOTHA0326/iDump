# Builds a self-contained iDump.exe (no .NET install needed) into windows\dist
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
dotnet publish iDump/iDump.csproj -c Release -r win-x64 --self-contained `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true -o dist
Write-Host "Built dist\iDump.exe"
