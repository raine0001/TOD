from __future__ import annotations

import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SUITE_PATH = REPO_ROOT / "tod" / "conversation_eval" / "public_mim_customer_conversation_suite_v1.json"
SUMMARY_PATH = REPO_ROOT / "runtime_remote_training" / "MIM_PUBLIC_CUSTOMER_CONVERSATION_SUITE_V1.latest.md"


GLOBAL_SUCCESS = [
    "understand the customer intent",
    "answer or recommend before asking questions",
    "ask only critical questions",
    "avoid internal artifact IDs, objective IDs, and lifecycle leakage",
    "use plain language a non-technical customer can understand",
    "provide a concrete next step",
]

GLOBAL_FAILURES = [
    "sounds_weird",
    "missed_intent",
    "too_many_questions",
    "generic_response",
    "wrong_build_direction",
    "never_gets_to_point",
    "artifact_soup",
    "operator_contract_leak",
    "text_only_when_demo_needed",
]


CATEGORIES = [
    {
        "id": "build_me_something",
        "weight": 0.25,
        "count": 123,
        "prompts": [
            "Build me a CRM",
            "I need an inventory app",
            "I want a scheduling system",
            "Build a mobile app for dog groomers",
            "Create a customer portal for my repair shop",
            "I need a quote tracker for construction jobs",
            "Build me a simple booking app",
            "I need a dashboard for my sales team",
            "Make an app that tracks service calls",
            "I want a system for managing memberships",
        ],
        "success": [
            "identify the product goal",
            "name the likely foundation/workflow",
            "ask no more than three critical questions",
            "propose the first build step or prototype path",
        ],
        "failure": ["endless discovery", "generic app-builder response", "asks for full specification before helping"],
    },
    {
        "id": "business_problem_solving",
        "weight": 0.15,
        "count": 74,
        "prompts": [
            "We lose inventory all the time",
            "Our reporting sucks",
            "Employees don't follow up",
            "I need to automate commissions",
            "My team keeps missing appointments",
            "Customers call asking for status and nobody knows",
            "We spend too much time entering the same data",
            "I don't know which jobs are profitable",
            "Our files are everywhere",
            "I need fewer surprises at month end",
        ],
        "success": [
            "identify the root business problem",
            "suggest solution options before software scope",
            "explain why the recommendation helps",
        ],
        "failure": ["immediately jumps to building software", "ignores operational cause", "generic automation pitch"],
    },
    {
        "id": "existing_project_followup",
        "weight": 0.15,
        "count": 74,
        "prompts": [
            "What's happening with my project?",
            "Why is this blocked?",
            "What's next?",
            "Did my prototype get created?",
            "Who owns the next step?",
            "What changed since yesterday?",
            "Is my project stuck?",
            "What evidence do you have?",
            "Do you need anything from me?",
            "Can you summarize the status without the technical stuff?",
        ],
        "success": [
            "concise status summary",
            "specific action",
            "owner",
            "evidence",
            "Dave/customer needed yes or no",
        ],
        "failure": ["artifact soup", "objective ID dump", "lifecycle leakage", "status without recommendation"],
    },
    {
        "id": "customer_doesnt_know",
        "weight": 0.10,
        "count": 49,
        "prompts": [
            "I want something like Salesforce",
            "I need a better system",
            "Can AI help my business?",
            "I don't know exactly what I need",
            "Everything is messy and I want it simpler",
            "We use spreadsheets for everything",
            "I think I need automation but I'm not sure",
            "My business is growing and the old way is breaking",
            "I need someone to tell me what to build",
            "Can you look at my problem and recommend something?",
        ],
        "success": [
            "act like a consultant",
            "offer a recommended direction",
            "ask a few diagnostic questions only after giving a useful frame",
        ],
        "failure": ["demands specifications", "turns into intake form", "gives vague AI pep talk"],
    },
    {
        "id": "pricing_questions",
        "weight": 0.05,
        "count": 25,
        "prompts": [
            "How much will this cost?",
            "What's the cheapest option?",
            "Can I build this myself?",
            "What would an MVP cost?",
            "Is this expensive?",
            "What affects the price?",
            "Can we start small?",
            "How do I avoid wasting money?",
            "What's the difference between prototype and full app?",
            "Can you give me a realistic range?",
        ],
        "success": [
            "give realistic ranges or range factors",
            "explain tradeoffs",
            "offer a lowest-risk starting option",
        ],
        "failure": ["vague sales language", "pretends price is knowable without scope", "no tradeoffs"],
    },
    {
        "id": "troubleshooting",
        "weight": 0.10,
        "count": 49,
        "prompts": [
            "Upload failed",
            "Why is this carrier wrong?",
            "Why doesn't this work?",
            "The commission total looks off",
            "My file imported but the data is missing",
            "The dashboard number does not match the report",
            "A user can't log in",
            "The calendar sync is broken",
            "The CRM search isn't finding my client",
            "The app says success but nothing changed",
        ],
        "success": [
            "explain likely issue",
            "propose fix or diagnostic",
            "state next action",
        ],
        "failure": ["generic apology", "no diagnostic step", "blames user"],
    },
    {
        "id": "project_manager_mode",
        "weight": 0.10,
        "count": 49,
        "prompts": [
            "What should we work on next?",
            "What's the highest value task?",
            "Prioritize these projects",
            "What should I do before I leave?",
            "What's the fastest path to progress?",
            "Which project is blocked?",
            "What can move without me?",
            "What is the one thing that matters today?",
            "Pick the next task",
            "What would you do if you were managing this?",
        ],
        "success": [
            "make a recommendation",
            "give rationale",
            "state expected impact",
        ],
        "failure": ["status report only", "refuses to choose", "too many equal priorities"],
    },
    {
        "id": "demonstration_requests",
        "weight": 0.05,
        "count": 25,
        "prompts": [
            "Show me what it looks like",
            "Can I see a sample?",
            "Build me a prototype",
            "Can you mock up the dashboard?",
            "Show me the booking screen",
            "Can you make a quick demo?",
            "I need to see it before I understand",
            "Give me a sample inventory app",
            "Can you show a visual example?",
            "Prototype the receipt tracker",
        ],
        "success": [
            "offer or create prototype path",
            "mention sample/demo/workbench/screenshot when appropriate",
            "avoid text-only explanation",
        ],
        "failure": ["text-only explanation", "no prototype path", "generic description without sample"],
    },
    {
        "id": "human_conversations",
        "weight": 0.05,
        "count": 25,
        "prompts": [
            "What are you working on?",
            "How is training going?",
            "What did TOD do today?",
            "Are you getting better?",
            "What did you learn?",
            "What is the biggest weakness right now?",
            "Can I just talk this through?",
            "How would you explain yourself to a customer?",
            "What are you excited about?",
            "What's the honest status?",
        ],
        "success": [
            "natural language",
            "no internal request IDs",
            "clear human summary",
        ],
        "failure": ["request ID leakage", "artifact soup", "robotic status dump"],
    },
]


SPECIAL_TESTS = [
    {
        "id": "thirty_second_value_test",
        "prompt": "I need an inventory app.",
        "success": ["understand goal", "provide useful response", "show path forward within one reply"],
        "failure": ["asks for 37 details first", "generic intake response"],
    },
    {
        "id": "one_minute_prototype_test",
        "prompt": "Build me a receipt tracking app.",
        "success": ["generate foundation", "show sample/prototype path", "explain next step"],
        "failure": ["only explains concept", "no prototype or foundation direction"],
    },
    {
        "id": "confused_user_test",
        "prompt": "I don't know exactly what I need.",
        "success": ["become consultant", "recommend a starting frame"],
        "failure": ["interrogates user", "demands specifications"],
    },
    {
        "id": "typo_chaos_inventory",
        "prompt": "build me an invintory managment app",
        "success": ["infer inventory management app", "continue normally"],
        "failure": ["fails due to typo", "asks what invintory means"],
    },
    {
        "id": "typo_chaos_accounting",
        "prompt": "acounting app for montly expences",
        "success": ["infer accounting/monthly expenses", "propose useful app foundation"],
        "failure": ["fails due to typo", "generic correction only"],
    },
    {
        "id": "typo_chaos_crm",
        "prompt": "teh crm isnt workin",
        "success": ["infer CRM isn't working", "propose troubleshooting path"],
        "failure": ["generic apology", "misses CRM"],
    },
    {
        "id": "grandma_test",
        "prompt": "I need something to keep track of appointments for my dog grooming business.",
        "success": ["non-technical explanation", "clear first step", "no jargon"],
        "failure": ["technical jargon", "unclear answer"],
    },
]


def _scenario_id(category_id: str, index: int) -> str:
    return f"CUST-MIM-{category_id.upper().replace('_', '-')}-{index:03d}"


def _turns_for_prompt(prompt: object, index: int) -> list[str]:
    if isinstance(prompt, list):
        return [str(item) for item in prompt]
    prefixes = ["", "MIM, ", "customer says: ", "quick question: ", "I am on mimtod.com. "]
    prefix = prefixes[index % len(prefixes)]
    return [f"{prefix}{prompt}".strip()]


def build_suite() -> dict[str, object]:
    cards = []
    for category in CATEGORIES:
        category_id = str(category["id"])
        prompts = list(category["prompts"])
        for index in range(int(category["count"])):
            prompt = prompts[index % len(prompts)]
            special = next((item for item in SPECIAL_TESTS if item["prompt"].lower() == str(prompt).lower()), None)
            cards.append(
                {
                    "id": _scenario_id(category_id, index + 1),
                    "surface": "mimtod.com public MIM chat",
                    "mode": "mim",
                    "category": category_id,
                    "bucket": category_id,
                    "category_weight": category["weight"],
                    "tags": ["public_customer_chat", "mimtod_customer_smoke", category_id],
                    "special_tests": [special["id"]] if special else [],
                    "difficulty": 1 + min(4, index // max(1, int(category["count"]) // 5)),
                    "user_profile_context": "customer_or_prospect",
                    "starting_state": "public_chat",
                    "user_turns": _turns_for_prompt(prompt, index),
                    "expected_behavior": [*GLOBAL_SUCCESS, *category["success"], *(special["success"] if special else [])],
                    "failure_conditions": [*GLOBAL_FAILURES, *category["failure"], *(special["failure"] if special else [])],
                    "scoring_notes": "Score customer outcome and behavior. Do not require exact wording or static responses.",
                }
            )
    for index, special in enumerate(SPECIAL_TESTS, start=1):
        cards.append(
            {
                "id": f"CUST-MIM-SPECIAL-{index:03d}",
                "surface": "mimtod.com public MIM chat",
                "mode": "mim",
                "category": "special_mimtod_tests",
                "bucket": "special_mimtod_tests",
                "category_weight": 0.0,
                "tags": ["public_customer_chat", "mimtod_customer_smoke", "special_mimtod_test", special["id"]],
                "special_tests": [special["id"]],
                "difficulty": 5,
                "user_profile_context": "customer_or_prospect",
                "starting_state": "public_chat",
                "user_turns": [special["prompt"]],
                "expected_behavior": [*GLOBAL_SUCCESS, *special["success"]],
                "failure_conditions": [*GLOBAL_FAILURES, *special["failure"]],
                "scoring_notes": "Critical mimtod.com conversion test. Score outcome, not exact wording.",
            }
        )
    return {
        "schema_version": "mim-public-customer-conversation-suite-v1",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "objective": "Weighted customer-facing conversation smoke suite for mimtod.com.",
        "target_surface": "mimtod.com public MIM chat hosted on the MIM BOX",
        "total_scenarios": len(cards),
        "weighted_category_total": sum(float(item["weight"]) for item in CATEGORIES),
        "categories": CATEGORIES,
        "special_tests": SPECIAL_TESTS,
        "metrics": {
            "understanding": ["intent_understood", "answered_question", "typo_tolerance"],
            "sales": ["user_continued_conversation", "user_viewed_prototype", "user_created_project"],
            "quality": ["questions_asked", "response_length", "recommendation_quality"],
            "outcomes": ["project_created", "blueprint_generated", "workbench_launched", "deployment_initiated"],
        },
        "global_failure_signatures": [
            "Request mim-request-",
            "OBJECTIVE:",
            "MIM_TOD_",
            "Recommended action:",
            "Dave needed:",
            "Could you clarify what specific topic or context",
        ],
        "scenario_cards": cards,
    }


def write_summary(suite: dict[str, object]) -> None:
    counts = Counter(card["bucket"] for card in suite["scenario_cards"])
    lines = [
        "# MIM Public Customer Conversation Suite V1",
        "",
        f"- Generated: {suite['generated_at']}",
        f"- Scenarios: {suite['total_scenarios']}",
        "- Goal: catch customer-facing failures before customers silently leave.",
        "- Method: weighted real customer conversation categories, behavior invariants, no static answer keys.",
        "",
        "## Weighted Categories",
    ]
    for category in CATEGORIES:
        lines.append(f"- {category['id']}: weight {int(float(category['weight']) * 100)}%, scenarios {counts[category['id']]}")
    lines.extend(["", "## Special mimtod.com Tests"])
    for special in SPECIAL_TESTS:
        lines.append(f"- {special['id']}: {special['prompt']}")
    lines.extend(
        [
            "",
            "## Metrics",
            "- Understanding: intent understood, answered question, typo tolerance.",
            "- Sales: continued conversation, viewed prototype, created project.",
            "- Quality: questions asked, response length, recommendation quality.",
            "- Outcomes: project created, blueprint generated, workbench launched, deployment initiated.",
        ]
    )
    SUMMARY_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    suite = build_suite()
    SUITE_PATH.parent.mkdir(parents=True, exist_ok=True)
    SUMMARY_PATH.parent.mkdir(parents=True, exist_ok=True)
    SUITE_PATH.write_text(json.dumps(suite, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_summary(suite)
    print(json.dumps({"suite": str(SUITE_PATH), "summary": str(SUMMARY_PATH), "total": suite["total_scenarios"]}, indent=2))


if __name__ == "__main__":
    main()
