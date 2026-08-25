# TOD Managed Host Connectivity V1

TOD owns the safe connection answer for TODBOX and MIMBOX. The authority is `tod/config/managed-host-connections.json`; passwords and private keys are never stored there.

Operator questions:

- `TOD, how do we connect to the TODBOX?`
- `TOD, how do we connect to the MIMBOX?`

TOD's answer must name the SSH alias, current authority-managed service address, account, last key-access proof, and evidence timestamp. The normal commands are `ssh todbox` and `ssh mimbox`.

`scripts/Sync-TODManagedSshConnectivity.ps1` performs the client proof. It verifies the selected public-key fingerprint, compares the server's presented ED25519 identity to the pinned authority fingerprint before changing configuration, generates the SSH aliases, and proves noninteractive key login. It refuses to rewrite the managed configuration when server identity is unexpected.

`scripts/Register-TODManagedSshConnectivityTask.ps1` registers the proof at workstation logon and every 15 minutes. TODBOX independently runs `todbox-startup-connectivity-verify.timer` at boot and every 15 minutes, covering SSH service readiness and its live system inventory.

The same registry owns address consumers. The verifier synchronizes `MIM_SSH_HOST` in the local deployment environment from the verified MIMBOX record, so Posh-SSH workflows that cannot use OpenSSH aliases still follow TOD's authority rather than an independently maintained address.

Failure meanings are distinct:

- `client_identity_mismatch_or_missing`: the expected client public key is missing or is not the authority key.
- `server_host_identity_mismatch_or_unreachable`: the server is unreachable or its cryptographic host identity changed; do not erase `known_hosts` or blindly accept it.
- key login rejected after both identities match: inspect the remote account's `authorized_keys`, ownership, permissions, and effective `sshd` policy.

The August 25 incident had two independent causes: direct TODBOX checks selected the passphrase-protected default key without a running SSH agent, while the dedicated key already worked; MIMBOX's hand-written alias named obsolete user `testpilot`, while live authority uses `tod`, and `/home/tod/.ssh/authorized_keys` did not exist. Both hosts now authorize the dedicated administrative key.

Training status: `scaffolded_pass`. This is a Codex-assisted repair after TOD's first diagnosis. Promotion requires TOD to independently diagnose and resolve a fresh analogous identity-selection or authorization failure.
