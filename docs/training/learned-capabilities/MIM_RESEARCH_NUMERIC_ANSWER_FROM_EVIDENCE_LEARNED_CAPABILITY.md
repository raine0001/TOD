# Learned Capability: MIM Research Numeric Answer From Evidence V1

Capability Name: Evidence-derived numeric research answers without hardcoded response text.

Trigger: A user asks MIM for a numeric, cost, specification, output, dimension, count, date, or capacity answer inside a research project.

Reality: The SolAir project library contained an observed BOM artifact with row-level cost data. The user asked how much it costs to build one SolAir. A useful answer required reading the observed BOM rows, parsing quantity and cost fields, calculating a one-unit estimate, linking the source workbook, and preserving uncertainty about whether the cost column was unit cost or row-extended cost.

Observation: MIM answered with a generic manufacturing-discovery response. It named BOM lanes and source context, but did not answer the cost question. The generic manufacturing route caught the word "build" before a cost-specific evidence path could calculate from the BOM artifact.

Root Cause: MIM had evidence access and routing capability, but lacked a specific numeric-answer rung that:

1. detects a numeric/cost intent,
2. selects the narrowest source artifact,
3. extracts relevant source fields,
4. calculates from those fields,
5. labels estimate boundaries,
6. validates against generic fallback leakage.

Blocker Class: capability_blocker plus evidence_routing_gap plus validation_gap.

Decomposition Ladder:

1. Preserve the observed bad answer as failure evidence.
2. Identify the user's actual object of inquiry: one-unit build cost.
3. Locate the relevant source artifact: `SOLAIR_PARTS_BOM_OBSERVATION.latest.json`.
4. Inspect artifact shape and row fields: `row_number`, `part_no`, `quantity`, `description`, `supplier`, `supplier_part_no`, `cost`, `assembly_path`.
5. Parse cost values without hardcoding numbers.
6. Parse numeric quantities without treating special values such as `SP` as one-unit quantities.
7. Exclude packaged subtotal rows that would double count the main BOM.
8. Calculate both extended quantity-by-cost sum and unextended row-cost sum.
9. Identify the largest observed contributors from calculated row values.
10. Compose an answer that separates source fact, calculation, estimate, uncertainty, and excluded production costs.
11. Route cost questions before generic manufacturing-discovery fallback.
12. Add a regression test proving the cost question no longer returns the generic fallback.
13. Validate locally, validate on MIM box, restart service, and probe the live HTTP chat route.

Smallest Successful Rung: A direct SolAir cost question with Observatory context returns calculated BOM totals, links the BOM source workbook, and does not include the generic "build-readiness package" fallback.

Implementation Summary: Added a cost-specific evidence lane in `core/public_research_context.py` that loads SolAir BOM artifacts, parses money and quantity values, calculates extended and unextended cost views, formats the largest observed contributors, cites the source workbook link, and states excluded production-cost boundaries. Added coverage in `tests/test_public_research_context.py` for the failed prompt.

Validation:

- Local syntax check for `core/public_research_context.py` and `tests/test_public_research_context.py`: passed.
- Local `test_public_research_context.py`: passed.
- Remote MIM-box syntax check: passed.
- Remote MIM-box `test_public_research_context.py`: passed.
- `mim-mobile-web.service` restart: active.
- Live HTTP probe to `/public/chat/message`: returned the corrected evidence-derived answer.

General Rule Learned: A numeric answer is not a paragraph to remember. It is a small evidence pipeline: intent -> source selection -> field extraction -> calculation -> boundary labeling -> source citation -> validation.

Prevention Rule: MIM must not answer specific numeric research questions from generic fallback text. Before publishing a numeric answer, MIM must name the source evidence, show whether the value is source-observed or calculated, expose assumptions, and reject fallback completion if no relevant evidence was inspected.

Reuse Trigger: Reuse this capability when MIM is asked for cost, build cost, unit price, power, wattage, certification number, dimensions, component counts, date, meeting length, participant count, or any other factual numeric claim that could be pulled from a project artifact or DB record.

Dependent Capabilities: research document assimilation, source artifact loading, BOM row extraction, money parsing, quantity parsing, source-link rendering, evidence-lane routing, regression test authoring, HTTP route probing, direct-answer compression.

Capability Confidence: 8/10 for the SolAir cost prompt and similar BOM-derived numeric answers. Lower for unseen artifact schemas until MIM/TOD prove schema inspection and calculation planning independently.

Independent Pass Rate: Not yet measured. Codex performed the emergency product repair. MIM/TOD must now rerun this as training and prove they can diagnose and design the same style of evidence-derived answer without Codex authoring the code first.

Date Frozen: 2026-07-06.

Separate Debt: Generalize this beyond SolAir-specific routing so new research projects can register numeric evidence extractors or artifact schemas without growing a hardcoded route page.

Generalized Principle: Specific evidence questions should activate source inspection and calculation behavior, not generic conversation fallbacks. Deterministic calculations are allowed; hardcoded factual answers are not.
