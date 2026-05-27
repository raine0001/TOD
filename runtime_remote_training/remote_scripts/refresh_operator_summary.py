import json
from pathlib import Path
from datetime import datetime, timezone
base=Path('/home/testpilot/mim/runtime/shared')
now=datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')
status=json.loads((base/'MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json').read_text())
records=list(status.get('objectives',{}).values())
completed=[r for r in records if 'complete' in str(r.get('status','')).lower() or str(r.get('status','')).startswith('implementation_completed')]
blocked=[r for r in records if 'blocked' in str(r.get('status','')).lower()]
running=[r for r in records if 'running' in str(r.get('status','')).lower()]
summary={
 'packet_type':'mim-tod-morning-operator-summary-v1',
 'generated_at':now,
 'source':'codex_status_repair_after_objective_fix',
 'status':'active_with_narrow_blockers' if blocked else 'active_without_blockers',
 'summary':f'Objective state repaired. {len(completed)} objective(s) have completion evidence, {len(running)} are running, and {len(blocked)} have explicit blockers.',
 'what_changed':['Forum image objective now consumes the Codex implementation result instead of staying queued.','Streaming STT is no longer marked no-executor; the speech turn engine is bound and running.','Calendar/phone/email objective is narrowed to one real remaining binding: email-read summaries.'],
 'blocked_objectives':[{'objective_id':r.get('objective_id'),'reason_code':r.get('reason_code'),'next_recovery_action':r.get('next_recovery_action')} for r in blocked],
 'running_objectives':[{'objective_id':r.get('objective_id'),'reason_code':r.get('reason_code')} for r in running],
 'completed_objectives':[{'objective_id':r.get('objective_id'),'reason_code':r.get('reason_code')} for r in completed],
 'next_action':'Bind the email read summary executor and continue live STT quality validation.'
}
(base/'MIM_TOD_MORNING_OPERATOR_SUMMARY.latest.json').write_text(json.dumps(summary,indent=2,sort_keys=True))
print(summary['summary'])