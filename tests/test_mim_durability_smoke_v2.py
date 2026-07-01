import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "run_mim_durability_smoke_v2.py"


def load_smoke_module():
    spec = importlib.util.spec_from_file_location("run_mim_durability_smoke_v2", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_status_report_scaffold_fails_normal_durability_prompt():
    module = load_smoke_module()
    reply = (
        "The important training question is whether the work is producing useful behavior, "
        "not whether the scoreboard looks busy.\n\n"
        "Current evidence: mode-selection is 100%.\n"
        "Recommended action: rerun the smoke.\n"
        "Owner: MIM owns the reply behavior.\n"
        "Expected evidence: MIM_DURABILITY_SMOKE_V2.latest.json.\n"
        "Time / aging rule: rerun within 24h.\n"
        "Dave needed: no."
    )

    result = module.evaluate("explanation_mode", "How is training going MIM?", reply)

    assert result["checks"]["no_status_report_leakage"] is False
    assert result["passed"] is False


def test_plain_explanation_reply_does_not_trigger_status_leakage_guard():
    module = load_smoke_module()
    reply = (
        "Training is moving in the right direction, but the useful test is whether it "
        "changes what MIM and TOD do next. The strongest progress is that MIM is now "
        "better at choosing the right kind of answer, while TOD still needs more real "
        "independent fixes. The next step should be one behavior-changing TOD task that "
        "is inspected, patched, validated, and recorded without help."
    )

    result = module.evaluate("explanation_mode", "How is training going MIM?", reply)

    assert result["checks"]["no_status_report_leakage"] is True


def test_recommendation_shaped_reply_fails_explanation_mode_identity():
    module = load_smoke_module()
    reply = (
        "I recommend working on MIM conversation mode selection next. It has the "
        "highest value because TOD is starting to prove real implementation movement, "
        "while MIM still needs to answer normal questions without slipping into "
        "internal status language. The next useful action is to rerun the durability "
        "suite and use the failures to tune the handler."
    )

    result = module.evaluate("explanation_mode", "What are you working on MIM?", reply)

    assert result["checks"]["mode_identity"] is False
    assert result["passed"] is False


def test_plain_explanation_reply_passes_explanation_mode_identity():
    module = load_smoke_module()
    reply = (
        "I am working on making MIM choose the right kind of answer before it talks. "
        "In plain language: if you ask what is happening, I should explain; if you ask "
        "what to do next, I should recommend; if someone wants software built, I should "
        "ask only the critical discovery questions and then show a path forward. The "
        "next step is to keep testing normal office questions against that behavior."
    )

    result = module.evaluate("explanation_mode", "What are you working on MIM?", reply)

    assert result["checks"]["mode_identity"] is True
    assert result["passed"] is True


def test_needs_attention_explanation_passes_explanation_mode_identity():
    module = load_smoke_module()
    reply = (
        "Three things need attention, Dave. The first is that the page can show an "
        "old assessment even when the current evidence has moved. The second is that "
        "operator-impact replies still need live scoring. The third is that TOD's "
        "independent-resolution count should only move when behavior actually changes. "
        "The useful next step is to refresh the scorecard and inspect the failed line."
    )

    result = module.evaluate("explanation_mode", "Explain why the training page says needs attention.", reply)

    assert result["checks"]["mode_identity"] is True
    assert result["passed"] is True
