# AgentMIM Commission Upload Troubleshooting Playbook

Updated: 2026-06-09

## Purpose

Teach MIM and TOD how to troubleshoot AgentMIM commission uploads from evidence, so Dave can have the same kind of conversation with MIM inside AgentMIM that he just had with Codex.

Rule: do not import until parsed detail rows, carrier statement totals, companion files, and mapping confidence reconcile.

## Current May 2026 Dry-Run

Source folder:

- `F:/DRIVE/ahi/may_2026/downloads`

Report artifacts:

- `E:/comm_app/runtime/commission_dry_run/may_2026/commission_dry_run_report.md`
- `E:/comm_app/runtime/commission_dry_run/may_2026/commission_dry_run_report.json`

Current status:

- Files scanned: 35
- Ready file-only mappings: 30
- Duplicate/reference ready: 1
- Mapping failures: 4
- Suspicious totals: 0

No upload/import was performed during this dry-run.

## Known Resolution: CCSB Top-Row Subtotal Loss

File family:

- `CCSB_Statement*.xlsx`
- Carrier: Covered CA Shop / Covered California Small Business

Observed:

- XLSX parsed total was `$31,666.31`.
- PDF cover letter said `$31,744.43`.
- Gap was `$78.12`.

Root cause:

- A top-of-page continuation row combined detail and subtotal content.
- The parser treated group `713667` as a money-like value and missed the real `$78.12` commission.

Resolution:

- `app/mappings/gn_clean_data.py` now uses subtotal-specific money extraction.
- Subtotal parsing prefers dollar/decimal premium and commission values over plain IDs.

Validation:

- `CCSB_Statement05182026rec06.04.26JR.xlsx` parses to `$31,744.43`.
- Regression test: `test_ccsb_gn_clean_data_recovers_subtotal_when_page_top_combines_rows`.

## Known Resolution: Kaiser BID Reward Statements

File family:

- `BID_13695_KPIFPMPM_New_Mbr_Reward_Stmt_*.csv`
- `BID_13695_KPIFPMPM_Renewal_Mbr_Reward_Stmt_*.csv`
- `BID_13695_RewardStatement_ProductionReward_*.csv`

Observed:

- New and renewal member reward files use `Bonus / Reward Amount`, often `$14.00` each.
- Group/production reward file uses a bottom `TOTAL:` row in `Bonus / Reward Total`.
- Renewal reward must not be misclassified as new reward just because `renewal` contains `new`.

Resolution:

- New reward maps `Bonus / Reward Amount` to commission paid.
- Renewal reward maps `Bonus / Reward Amount` to commission paid and is classified separately.
- Group reward creates one reviewable statement-total row from the bottom `TOTAL:` row.
- The group reward total is not fake-allocated across groups.

Validation:

- New reward: `$728.00`.
- Renewal reward: `$1,274.00`.
- Group/production reward: `$1,000.00`.
- Regression tests: `test_get_carrier_name_detects_kaiser_bid_reward_variants`, `test_process_file_reads_kaiser_group_reward_statement_total`.

## Known Resolution: California Choice Carry-Forward Rows

File family:

- `CalChoice_Stmt*.csv`

Observed:

- California Choice places group/policy ID and client name once.
- Rows beneath that entry belong to the same policy/client until the next group/policy appears.
- The statement also prints two subtotal blocks and a final grand total.
- Counting detail rows plus subtotal rows doubled the parsed total.

Resolution:

- AgentMIM now uses a California Choice parser that carries group/client forward.
- It keeps charge detail rows only.
- It ignores `TOTAL COMMISSIONS`, `Total ... Premium`, `TOTAL PAID COMMISSIONS`, and final grand-total rows.

Validation:

- `CalChoice_Stmt05.26.26Rec_05-28-26_JR.csv`: 58 detail rows.
- Parsed total: `$10,334.80`.
- Expected total: `$6,907.23 + $3,427.57`.
- Blank policy/client rows after parsing: 0.
- Regression test: `test_process_file_reads_calchoice_carry_forward_rows_without_totals`.

## Remaining Known Gaps

- GeoBlue PDF needs parser/OCR/manual mapping evidence.
- Schaub DOCX appears scanned/image-only and needs OCR/manual handling.
- CCSB PDF and Mutual of Omaha PDF should be treated as companion/reference files when XLSX/CSV detail companions are authoritative.

## MIM Conversation Behavior

When Dave or a user asks why an upload is wrong, MIM should:

1. Ask for or infer the expected statement total.
2. Use staged review/dry-run before asking for re-upload.
3. Compare parsed total, statement total, companion files, and source row evidence.
4. Identify the likely class: carrier detection, carry-forward rows, subtotal double-counting, OCR/scanned file, companion/reference file, policy-carrier mismatch, or column mapping.
5. Escalate to TOD/Codex only with filename, expected total, parsed total, gap, raw evidence, and proposed bounded repair.
