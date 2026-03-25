$ErrorActionPreference = "Stop"

# --- CONFIG ---
$orgAlias   = "collegetrack2-full"
$packageXml = "package.xml"
$retrieveDir = "mdapi-retrieve"
$zipFile = "unpackaged.zip"

Write-Host "`n📦 Retrieving LWC bundle from $orgAlias..." -ForegroundColor Cyan

# Ensure manifest exists
if (!(Test-Path $packageXml)) {
    Write-Host "❌ package.xml not found in project root." -ForegroundColor Red
    exit 1
}

# Create retrieve folder
if (!(Test-Path $retrieveDir)) {
    mkdir $retrieveDir | Out-Null
}

# Start retrieve
sf project retrieve start `
    --target-org $orgAlias `
    --manifest $packageXml `
    --output-dir $retrieveDir `
    --wait 10 `
    --json | Out-Null

Write-Host "✔ Retrieve complete. Unpacking..." -ForegroundColor Green

# Unzip the retrieved metadata
Expand-Archive -Path "$retrieveDir/$zipFile" -DestinationPath "$retrieveDir/unzip" -Force

Write-Host "✔ Unzipped. Copying LWC into force-app..." -ForegroundColor Green

Copy-Item "$retrieveDir/unzip/force-app" "force-app" -Recurse -Force

Write-Host "✔ LWC retrieval complete!" -ForegroundColor Green