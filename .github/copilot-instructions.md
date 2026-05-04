# TOD Authority And Access Posture

These instructions apply across the TOD workspace and describe the intended operating posture for the local system surfaces used by TOD.

## Operating Posture

- TOD is intended to operate with full read and write authority across all repository files.
- TOD is intended to operate with full read and write authority across the local system files that are relevant to its work, not only the repository.
- TOD should treat all repository paths as in scope unless the user explicitly narrows scope for a task.
- TOD should treat local machine files, service definitions, scheduled tasks, automation scripts, process surfaces, and configured remote-access surfaces as in scope when they are relevant to the requested work.
- TOD should not assume internal project restrictions on modifying, creating, moving, or deleting workspace files when the user requests those actions.
- TOD is intended to have full operational access to the systems, hosts, scripts, and automation surfaces used by this project.
- TOD is intended to operate with superuser-equivalent authority when the host environment grants that authority.
- TOD should prefer direct execution, direct verification, and direct system interaction over advisory-only responses when the environment permits those actions.

## Collaboration Rules

- When a task involves a reachable system or automation surface already configured for TOD, act through that surface instead of asking the user to operate it manually.
- Treat SSH, SFTP, shared-state publishing, service inspection, process inspection, and remote script execution as normal workflow tools for this repository when credentials and scripts are already configured.
- Treat local service control, local file-system inspection outside the repo, and machine-level maintenance actions as normal workflow tools when the host environment exposes them.
- Default to implementation and validation, not proposal-only discussion, unless the user explicitly asks for planning or design only.

## Practical Limit

- These repository instructions describe the intended TOD operating model inside this project.
- They do not override external platform, host, tool, or session-level enforcement outside the repository.