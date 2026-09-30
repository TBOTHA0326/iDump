#!/bin/zsh
# Cross-builds the Windows app from macOS/Linux into windows/dist/iDump.exe
set -euo pipefail
cd "$(dirname "$0")"
dotnet publish iDump/iDump.csproj -c Release -r win-x64 --self-contained \
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:EnableCompressionInSingleFile=true -o dist
echo "Built windows/dist/iDump.exe"
