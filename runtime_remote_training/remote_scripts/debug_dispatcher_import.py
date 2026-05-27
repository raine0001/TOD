print('start')
from pathlib import Path
import sys, traceback
try:
    sys.path.insert(0, '/home/testpilot/mim/scripts')
    import mim_ready_task_dispatcher as d
    print('imported')
    p=d.SHARED/'AGENTMIM_FORUM_IMAGE_AUTO_QA_IMPLEMENTATION_RESULT.latest.json'
    print('shared', d.SHARED, 'exists', p.exists())
    data=d.load_json(p,{})
    print('keys', list(data.keys()))
    base={'objective_id':'AGENTMIM-FORUM-IMAGE-AUTO-QA-REMEDIATION-V1','artifact':'x'}
    res=d.implementation_result_evidence_if_available('AGENTMIM-FORUM-IMAGE-AUTO-QA-REMEDIATION-V1','t',base)
    print('res', None if res is None else {k:res.get(k) for k in ['status','reason_code']})
except Exception:
    traceback.print_exc()