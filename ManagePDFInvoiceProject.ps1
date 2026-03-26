<#
╔══════════════════════════════════════════════════════════════════╗
║ UCSF PDF Invoice Project — DevOps Control Center                 ║
║ Menu-driven environment manager for Salesforce + GitHub workflow ║
║ Includes baseline, rollback, cleanup, verification, and README   ║
║ Author: Maurice J. Davis + ChatGPT DevOps Assistant              ║
╚══════════════════════════════════════════════════════════════════╝
#>

# --- SETTINGS ---
$RepoPath = "C:\Users\MauriceJDavis\PDFInvoiceProject"
$OrgAlias = "ucsfsandbox"
$RepoUrl  = "https://github.com/mauricedavis/PDFInvoiceProject"
Set-Location $RepoPath

# --- HELPER FUNCTIONS ---

function Create-Baseline {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagStamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $branchName = "branch_baseline_reset_${tagStamp}"
    $tagName = "baseline_reset_${tagStamp}"

    git checkout -b $branchName
    git add .
    git commit -m "Baseline reset - $timestamp"
    git push origin $branchName
    git tag -a $tagName -m "Baseline reset $timestamp"
    git push origin $tagName

    gh release create $tagName --title "Baseline Reset ($timestamp)" --notes "Protected baseline version snapshot"
    gh api --method PATCH "repos/mauricedavis/PDFInvoiceProject/git/refs/tags/$tagName/protection" --input-data '{"protected":true}' 2>$null
    git checkout main

    Write-Host "✅ Baseline branch '$branchName' and protected tag '$tagName' created successfully.`n"
}

function Restore-FromBaseline {
    $tags = git tag --list "baseline_reset_*"
    if (-not $tags) {
        Write-Host "⚠️ No baseline tags found."
        return
    }
    Write-Host "Available baselines:`n$tags"
    $selectedTag = Read-Host "Enter the tag name to restore"
    if (-not $selectedTag) { Write-Host "❌ No tag selected."; return }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $rollbackBranch = "rollback_from_${selectedTag}_${timestamp}"

    git checkout -b $rollbackBranch $selectedTag
    git push origin $rollbackBranch

    sf project deploy start --target-org $OrgAlias --ignore-conflicts
    sf apex run test --tests ProgramEnrollmentInvoiceController_Tests --target-org $OrgAlias --wait 10

    $rollbackTag = "rollback_${timestamp}_$(git rev-parse --short HEAD)"
    git tag -a $rollbackTag -m "Rollback from $selectedTag on $timestamp"
    git push origin $rollbackTag

    gh release create $rollbackTag --title "Rollback ($timestamp)" --notes "Rollback from $selectedTag"
    gh api --method PATCH "repos/mauricedavis/PDFInvoiceProject/git/refs/tags/$rollbackTag/protection" --input-data '{"protected":true}' 2>$null

    git checkout main
    Write-Host "✅ Rollback branch + tag created and verified.`n"
}

function Cleanup-Trigger {
    $triggerPath = "force-app\main\default\triggers\ProgramEnrollmentInvoiceTrigger.trigger"
    if (Test-Path $triggerPath) {
        Remove-Item $triggerPath -Force
        Write-Host "🧹 Deleted trigger file locally."
        git add .
        git commit -m "Remove ProgramEnrollmentInvoiceTrigger"
        git push origin main
        sf project deploy start --target-org $OrgAlias --ignore-conflicts
        Write-Host "✅ Trigger cleanup deployed to Salesforce."
    } else {
        Write-Host "✅ No trigger file found — already clean."
    }
}

function Verify-RepoState {
    Write-Host "`n🔍 Listing key tags and releases..."
    git tag --list "baseline_*","rollback_*","restored_*"
    gh release list
    Write-Host "`n✅ Verification complete — check for protected baseline tags."
}

function Update-Readme {
    $updateScript = Join-Path $RepoPath "UpdateReadme.ps1"
    if (-Not (Test-Path $updateScript)) {
        Write-Host "❌ Missing UpdateReadme.ps1 script. Please add it first."
        return
    }
    Write-Host "📝 Running README generator..."
    & $updateScript
    Write-Host "✅ README.md updated and pushed to GitHub."
}

# --- MENU ---

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════╗"
    Write-Host "║   UCSF PDF Invoice Project - DevOps Control Center   ║"
    Write-Host "╠══════════════════════════════════════════════════════╣"
    Write-Host "║ 1️⃣  Create Baseline Snapshot                         ║"
    Write-Host "║ 2️⃣  Restore from Baseline                            ║"
    Write-Host "║ 3️⃣  Cleanup Trigger                                  ║"
    Write-Host "║ 4️⃣  Verify Repo State                                ║"
    Write-Host "║ 5️⃣  Update README Documentation                      ║"
    Write-Host "║ 0️⃣  Exit                                             ║"
    Write-Host "╚══════════════════════════════════════════════════════╝"
}

do {
    Show-Menu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" { Create-Baseline }
        "2" { Restore-FromBaseline }
        "3" { Cleanup-Trigger }
        "4" { Verify-RepoState }
        "5" { Update-Readme }
        "0" { Write-Host "👋 Exiting Control Center."; break }
        Default { Write-Host "❌ Invalid option — please try again." }
    }

    if ($choice -ne "0") {
        Write-Host "`nPress Enter to return to menu..."
        Read-Host
    }

} while ($choice -ne "0")