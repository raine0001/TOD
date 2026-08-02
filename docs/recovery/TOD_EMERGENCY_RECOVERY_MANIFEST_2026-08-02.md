# TOD Emergency Recovery Manifest — 2026-08-02

## Recovery objective

Rebuild the TOD workstation after loss of the current Windows installation or hardware while preserving source, configuration intent, operational state, models, databases, credentials, and evidence with explicit trust boundaries.

## Git recovery snapshot

- Repository: `raine0001/TOD`
- Emergency branch: `codex/emergency-recovery-snapshot-20260802`
- Base before snapshot: `99833c67c8867ddfa79db1a33102bdd95a178b21`
- The emergency branch contains tracked source/configuration changes plus reviewed new source, tests, deployment scripts, training documents, and this manifest.
- Runtime evidence, downloaded archives, database files, model weights, invalid-state backups, `.env` files, private keys, cookies, and credentials are intentionally excluded from Git.
- Pre-commit checks: PowerShell parser pass for 32 candidate files; Python compile pass for seven candidate files; `git diff --check` pass; targeted secret-pattern scan zero hits.

## Workstation baseline

- Computer: `TOD-3322`
- OS: Windows 11 Pro, version `10.0.26200`, build `26200`
- Memory: 63.8 GB
- TOD repository: `E:\TOD`
- Local model inventory: 41 files, approximately 52.55 GB under `E:\TOD\models`
- Local MySQL service: `MIMsql`, automatic start, data directory `C:\ProgramData\MySQL\MySQL Server 8.0\Data`
- TOD/MIM scheduled-task inventory at capture: 22 matching tasks.
- Storage at capture:
  - `C:` 1,861.9 GB total
  - `D:` 1,863.0 GB total
  - `E:` 931.5 GB total
  - `F:` 1,907.7 GB total

## Verified secondary recovery copy

- Destination: separate external USB NVMe volume `F:` under `F:\TOD-Recovery\2026-08-02`.
- Git bundle: `TOD-repository-all-refs.bundle`.
- Git bundle bytes: 109,705,779.
- Git bundle SHA-256: `A97FDBDCE4E1CD0CD29758C8945A54D30F8220D74379C072E2DEAC6B24D7B0B1`.
- `git bundle verify`: pass; emergency branch included.
- Model copy: 41 files and 56,429,215,604 source bytes.
- Model verification: every source/destination file pair compared by SHA-256; zero mismatches.
- Encryption boundary: this session could not prove BitLocker status on `F:` without elevation. Only non-secret Git/model assets were copied. Databases, credentials, `.env` values, keys, and runtime state were not copied to the encryption-unverified volume.

## What Git recovers

1. TOD source, tests, scripts, checked-in configuration, training documents, and product-code mirrors intentionally tracked by the repository.
2. Commit history and the exact emergency branch snapshot.
3. This restore order and the inventory needed to identify missing non-Git assets.

Git does not recover live databases, secrets, model weights, runtime queues/state, Windows services/tasks, browser profiles, SSH material, or hosted-system data.

## Required encrypted off-box backup set

The following assets must be copied to an encrypted destination on independent storage or a trusted encrypted cloud backup. They must never be committed to Git.

1. MySQL logical dumps for every required local database, created with a consistent transactional/export procedure and accompanied by SHA-256 hashes and restore tests.
2. `E:\TOD\models` model weights and model manifest, or verified upstream download coordinates plus hashes where redistribution is unnecessary.
3. Required TOD runtime/state selections from `E:\TOD\tod\data`, `E:\TOD\tod\state`, `E:\TOD\runtime`, and `E:\TOD\runtime_remote_training`; exclude disposable caches and preserve evidence manifests.
4. Credentials and `.env` values exported to a password manager or encrypted secrets archive. Record variable names and owners separately; never store secret values in this repository.
5. SSH keys, certificates, Cloudflare/hosting credentials, GitHub access, and recovery codes in an encrypted credential vault with a tested access path.
6. Windows scheduled-task XML exports, service inventory, startup configuration, firewall configuration, installed-application inventory, device/driver inventory, and BitLocker recovery information.
7. MIMBox application/database backups and hosted ProjectManager preservation artifacts with independently verified hashes.

## Restore order

1. Install a supported Windows release and all firmware/chipset/GPU/storage/network updates.
2. Enable Microsoft Defender, firewall, BitLocker, tamper protection, cloud protection, script scanning, and network inspection before restoring executable content.
3. Install Git and clone the TOD repository. Check out the emergency recovery branch or the later reviewed merge commit.
4. Verify the checked-out commit and repository integrity with `git fsck --full`.
5. Install required application runtimes from trusted publishers.
6. Restore credentials from the encrypted vault without placing them in Git or logs.
7. Restore and verify model files by SHA-256.
8. Restore MySQL from logical dumps into an isolated instance, validate table/row inventories and application reads, then enable normal services.
9. Restore only required runtime/state artifacts after schema and ownership checks.
10. Re-register TOD/MIM scheduled tasks from reviewed scripts, not from unknown binaries.
11. Start services in dependency order and run health, authentication-boundary, queue, worker, database, and public-route probes.
12. Run Defender full/offline scanning before declaring the recovered workstation trusted.

## Current recovery gaps

- The source snapshot is on GitHub, and model weights plus a complete Git bundle have a verified second physical copy on `F:`. That external volume is not proven encrypted or off-site.
- Encrypted off-box copies of local databases, required runtime state, and credentials have not yet been proven in this manifest.
- The ProjectManager hosted-source archive transfer and isolated restore validation are still in progress.
- An elevated Defender Offline scan has not been run because it requires a reboot and would interrupt active preservation work.
- A full bare-metal image is not present in Git and should not be placed there.

## Completion gate

Full recovery readiness is complete only when:

- the emergency Git branch is pushed and can be freshly fetched;
- the repository commit passes integrity checks;
- every non-Git asset has an encrypted off-box copy, SHA-256 manifest, and isolated restore proof;
- credentials are recoverable through a separate trusted vault;
- scheduled tasks/services can be rebuilt from reviewed artifacts;
- a clean-machine rehearsal restores TOD/MIM health without relying on the original workstation.
