# GitHub Branch Protection For TOD

Use these settings to ensure TOD reliability and routing tests are enforced before merge.

## Target Branch

- Branch name pattern: `main`

## Required Protections

- Require a pull request before merging: enabled
- Require approvals: enabled (recommended minimum: 1)
- Dismiss stale pull request approvals when new commits are pushed: enabled
- Require status checks to pass before merging: enabled
- Require branches to be up to date before merging: enabled

## Required Status Check

After the workflow has run at least once in GitHub, add this required check:

- `TOD Tests / test`

Notes:
- Workflow file: `.github/workflows/tod-tests.yml`
- The CI entrypoint used by the job is `scripts/Invoke-TODTests.CI.ps1`.
- The JSON summary artifact uploaded by the workflow is `tod-tests-summary`.

## Optional Hardening

- Require conversation resolution before merging: enabled
- Require linear history: enabled
- Restrict who can push to matching branches: enabled for administrators/team leads only
- Include administrators: enabled
