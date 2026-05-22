param(
    [string]$EnvFile = ".env",
    [int]$Seconds = 120,
    [int]$IntervalSeconds = 5,
    [int]$Tail = 8
)

$ErrorActionPreference = "Stop"
$deadline = (Get-Date).AddSeconds([Math]::Max(1, $Seconds))
$lastGeneratedAt = ""

while ((Get-Date) -lt $deadline) {
    $command = @"
if [ -f /home/testpilot/mim/runtime/shared/MIM_VOICE_TRANSCRIPT_LOG.latest.jsonl ]; then
  tail -n $Tail /home/testpilot/mim/runtime/shared/MIM_VOICE_TRANSCRIPT_LOG.latest.jsonl
else
  echo ''
fi
"@
    $raw = & "$PSScriptRoot\Connect-Mim.ps1" -EnvFile $EnvFile -Command $command
    $lines = @($raw | Where-Object { $_ -and $_ -notmatch '^Connected to ' })
    foreach ($line in $lines) {
        try {
            $entry = $line | ConvertFrom-Json
            $generatedAt = [string]$entry.generated_at
            if ($generatedAt -eq $lastGeneratedAt) {
                continue
            }
            $lastGeneratedAt = $generatedAt
            Write-Host ""
            Write-Host "[$generatedAt] $($entry.status)"
            Write-Host "  transcript: '$($entry.transcript)'"
            Write-Host "  general:    '$($entry.general_transcript)'"
            Write-Host "  wake:       '$($entry.wake_transcript)'"
            Write-Host "  vad:        speech=$($entry.vad.speech_detected) segments=$(@($entry.vad.segments).Count)"
            Write-Host "  rms/max:    $($entry.audio_level.rms)/$($entry.audio_level.max)"
            Write-Host "  response:   $($entry.lab_conversation_response) intent=$($entry.lab_conversation_intent)"
        }
        catch {
            Write-Host $line
        }
    }
    Start-Sleep -Seconds ([Math]::Max(1, $IntervalSeconds))
}
