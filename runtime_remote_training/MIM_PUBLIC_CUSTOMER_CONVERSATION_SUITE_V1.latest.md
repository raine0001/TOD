# MIM Public Customer Conversation Suite V1

- Generated: 2026-06-12T01:01:58Z
- Scenarios: 500
- Goal: catch customer-facing failures before customers silently leave.
- Method: weighted real customer conversation categories, behavior invariants, no static answer keys.

## Weighted Categories
- build_me_something: weight 25%, scenarios 123
- business_problem_solving: weight 15%, scenarios 74
- existing_project_followup: weight 15%, scenarios 74
- customer_doesnt_know: weight 10%, scenarios 49
- pricing_questions: weight 5%, scenarios 25
- troubleshooting: weight 10%, scenarios 49
- project_manager_mode: weight 10%, scenarios 49
- demonstration_requests: weight 5%, scenarios 25
- human_conversations: weight 5%, scenarios 25

## Special mimtod.com Tests
- thirty_second_value_test: I need an inventory app.
- one_minute_prototype_test: Build me a receipt tracking app.
- confused_user_test: I don't know exactly what I need.
- typo_chaos_inventory: build me an invintory managment app
- typo_chaos_accounting: acounting app for montly expences
- typo_chaos_crm: teh crm isnt workin
- grandma_test: I need something to keep track of appointments for my dog grooming business.

## Metrics
- Understanding: intent understood, answered question, typo tolerance.
- Sales: continued conversation, viewed prototype, created project.
- Quality: questions asked, response length, recommendation quality.
- Outcomes: project created, blueprint generated, workbench launched, deployment initiated.
