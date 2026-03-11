# TOD Command Reference

Quick command cheatsheet for operating TOD and the TOD Command Console.

## Core Runtime

```powershell
.\scripts\TOD.ps1 -Action init
.\scripts\TOD.ps1 -Action ping-mim
.\scripts\TOD.ps1 -Action compare-manifest
.\scripts\TOD.ps1 -Action sync-mim
```

## Objectives and Tasks

```powershell
.\scripts\TOD.ps1 -Action new-objective -Title "..." -Description "..." -Priority high
.\scripts\TOD.ps1 -Action list-objectives

.\scripts\TOD.ps1 -Action add-task -ObjectiveId <ID> -Title "..." -Type implementation -Scope "..."
.\scripts\TOD.ps1 -Action list-tasks -ObjectiveId <ID>
.\scripts\TOD.ps1 -Action package-task -TaskId <ID>
.\scripts\TOD.ps1 -Action run-task -TaskId <ID>
.\scripts\TOD.ps1 -Action run-task-report -TaskId <ID>
```

## Results and Review

```powershell
.\scripts\TOD.ps1 -Action add-result -TaskId <ID> -Summary "..." -TestResults "pass"
.\scripts\TOD.ps1 -Action review-task -TaskId <ID> -Decision pass -Rationale "..."
.\scripts\TOD.ps1 -Action show-journal -Top 25
```

## Reliability and Routing

```powershell
.\scripts\TOD.ps1 -Action get-reliability
.\scripts\TOD.ps1 -Action show-reliability-dashboard -Top 25
.\scripts\TOD.ps1 -Action show-engine-performance
.\scripts\TOD.ps1 -Action show-routing-decisions
.\scripts\TOD.ps1 -Action show-routing-feedback
.\scripts\TOD.ps1 -Action show-failure-taxonomy
.\scripts\TOD.ps1 -Action get-capabilities
.\scripts\TOD.ps1 -Action get-research -Top 10
.\scripts\TOD.ps1 -Action get-resourcing -ObjectiveId <ID> -Top 10
.\scripts\TOD.ps1 -Action engineer-run -Top 10
.\scripts\TOD.ps1 -Action engineer-run -TaskId <ID> -ApplyPlan
.\scripts\TOD.ps1 -Action engineer-scorecard -Top 25
.\scripts\TOD.ps1 -Action sandbox-list -Top 25
.\scripts\TOD.ps1 -Action sandbox-plan -SandboxPath "notes/demo.txt" -Content "planned content"
.\scripts\TOD.ps1 -Action sandbox-apply-plan -SandboxPlanPath "tod/sandbox/artifacts/PLAN-XXXXXXXXXX.json"
.\scripts\TOD.ps1 -Action sandbox-write -SandboxPath "notes/demo.txt" -Content "hello sandbox"
.\scripts\TOD.ps1 -Action get-state-bus
.\scripts\TOD.ps1 -Action get-version
```

## TOD Command Console (UI)

```powershell
.\scripts\Start-TOD-UI.ps1 -Port 8844
```

Notes:
- If the requested port is busy, TOD auto-falls forward to the next available port.
- Open the printed URL in browser.

Optional command alias module:

```powershell
Import-Module TODTools -DisableNameChecking -Force
Start-TOD-UI -Port 8844
```

## Debug Logging

```powershell
Get-Content .\tod\out\mim-http.log -Tail 20
```

`mim-http.log` is populated when `mim_debug.enabled` is `true` in `tod/config/tod-config.json`.
