$repoRoot = Split-Path -Parent $PSScriptRoot
$enginePath = Join-Path $repoRoot 'scripts/engines/LocalExecutionEngine.ps1'
$engineText = [System.IO.File]::ReadAllText($enginePath)

Describe 'TOD local engineering provider prompt authority' {
    It 'does not append a duplicate source anchor to authoritative provider messages' {
        $branch = [regex]::Match(
            $engineText,
            '(?s)if \(\$outboundMessages\.Count -gt 0\) \{(?<body>.*?)\}\s*else \{'
        )

        $branch.Success | Should Be $true
        $branch.Groups['body'].Value | Should Not Match 'sourceAnchorPrompt'
        $branch.Groups['body'].Value | Should Match "provider_request_prompt_messages_authoritative"
    }

    It 'uses a bounded output budget for patch JSON generation' {
        $body = [regex]::Match(
            $engineText,
            '(?s)\$body = \[ordered\]@\{(?<body>.*?)response_format = @\{type = ''json_object''\}'
        )

        $body.Success | Should Be $true
        $body.Groups['body'].Value | Should Match 'max_tokens\s*=\s*1024'
        $body.Groups['body'].Value | Should Not Match 'max_tokens\s*=\s*6000'
    }

    It 'retains the literal source anchor in the default candidate prompt' {
        $engineText | Should Match '(?s)\$candidatePrompt = @".*?Source anchor:.*?\$sourceAnchorTextForPrompt'
        $engineText | Should Match "default_candidate_prompt_plus_literal_source_anchor"
    }
}
