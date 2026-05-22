param(
    [string]$EnvFile = ".env",
    [int]$Seconds = 120,
    [int]$IntervalSeconds = 5
)

$ErrorActionPreference = "Stop"
$deadline = (Get-Date).AddSeconds([Math]::Max(1, $Seconds))
$lastGeneratedAt = ""

while ((Get-Date) -lt $deadline) {
    $command = @'
if [ -f /home/testpilot/mim/runtime/shared/MIM_WAKE_DIAGNOSTIC.latest.json ]; then
  cat /home/testpilot/mim/runtime/shared/MIM_WAKE_DIAGNOSTIC.latest.json
else
  echo '{"status":"missing","diagnosis":{"reason_code":"artifact_missing","summary":"No diagnostic artifact has been produced yet."}}'
fi
'@
    $raw = & "$PSScriptRoot\Connect-Mim.ps1" -EnvFile $EnvFile -Command $command
    $jsonText = ($raw | Where-Object { $_ -notmatch '^Connected to ' }) -join "`n"
    try {
        $payload = $jsonText | ConvertFrom-Json
        $generatedAt = [string]$payload.generated_at
        if ($generatedAt -ne $lastGeneratedAt) {
            $lastGeneratedAt = $generatedAt
            $diag = $payload.diagnosis
            $observed = $diag.observed
            Write-Host ""
            Write-Host "[$generatedAt] $($diag.reason_code)"
            Write-Host "  $($diag.summary)"
            if ($observed) {
                Write-Host "  transcript: '$($observed.transcript)'"
                Write-Host "  wake: $($observed.wake_phrase_detected)  self_output: $($observed.self_output_detected)  voice: $($observed.voice_wav_output_accepted)"
                Write-Host "  rms/max: $($observed.rms)/$($observed.max)"
            }
            Write-Host "  next: $($diag.next_action)"
        }
    } catch {
        Write-Host "Could not parse diagnostic payload:"
        Write-Host $jsonText
    }
    Start-Sleep -Seconds ([Math]::Max(1, $IntervalSeconds))
}
