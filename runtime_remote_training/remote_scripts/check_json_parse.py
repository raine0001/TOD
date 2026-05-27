import json
from pathlib import Path
p=Path('/home/testpilot/mim/runtime/shared/AGENTMIM_FORUM_IMAGE_AUTO_QA_IMPLEMENTATION_RESULT.latest.json')
print(p.exists(), p.stat().st_size if p.exists() else None)
data=json.loads(p.read_text())
print(list(data.keys()), data.get('status'))