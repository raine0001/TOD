from pathlib import Path
p=Path('/home/testpilot/mim/scripts/mim_ready_task_dispatcher.py')
s=p.read_text()
s=s.replace('result = load_json(SHARED / "AGENTMIM_FORUM_IMAGE_AUTO_QA_IMPLEMENTATION_RESULT.latest.json", {})\n        if result:', 'result_path = SHARED / "AGENTMIM_FORUM_IMAGE_AUTO_QA_IMPLEMENTATION_RESULT.latest.json"\n        result = load_json(result_path, {})\n        if not result:\n            alt_result_path = Path("/home/testpilot/mim/runtime/shared/AGENTMIM_FORUM_IMAGE_AUTO_QA_IMPLEMENTATION_RESULT.latest.json")\n            result = load_json(alt_result_path, {})\n        if result:')
p.write_text(s)
print('patched alt explicit forum result path')