import json
from pathlib import Path
from datetime import datetime, timezone
base=Path('/home/testpilot/mim/runtime/shared')
now=datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')
objective_id='AGENTMIM-FORUM-IMAGE-AUTO-QA-REMEDIATION-V1'
impl=json.loads((base/'AGENTMIM_FORUM_IMAGE_AUTO_QA_IMPLEMENTATION_RESULT.latest.json').read_text())
evidence={
  'packet_type':'mim-tod-objective-execution-evidence-v2',
  'generated_at':now,
  'objective_id':objective_id,
  'title':'AgentMIM forum image auto-generation QA and remediation',
  'status':'implementation_completed_with_local_validation',
  'reason_code':'codex_result_ingested_database_apply_blocked',
  'artifact':f'runtime/shared/MIM_TOD_OBJECTIVE_EVIDENCE.{objective_id}.latest.json',
  'artifact_path':str(base/f'MIM_TOD_OBJECTIVE_EVIDENCE.{objective_id}.latest.json'),
  'evidence_artifacts':['runtime/shared/AGENTMIM_FORUM_IMAGE_AUTO_QA_IMPLEMENTATION_RESULT.latest.json'],
  'codex_result_artifact':'runtime/shared/AGENTMIM_FORUM_IMAGE_AUTO_QA_IMPLEMENTATION_RESULT.latest.json',
  'implementation_result':impl,
  'operator_facing_summary':'Forum image QA implementation is complete locally: weak generated editorial/MIM Opinion images now fail relevance and quality gates, and the remediation runner exists. Live apply is blocked only by deployed database access.',
  'next_recovery_action':'Run forum-image-auto-qa-remediate --apply from the deployed AgentMIM environment with database access, then verify remediated post evidence.',
  'source':'codex_result_terminal_state_repair',
  'confidence':'high'
}
(base/f'MIM_TOD_OBJECTIVE_EVIDENCE.{objective_id}.latest.json').write_text(json.dumps(evidence,indent=2,sort_keys=True))
status_path=base/'MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json'
status=json.loads(status_path.read_text())
status.setdefault('objectives',{})[objective_id]={k:evidence.get(k) for k in ['artifact','generated_at','next_recovery_action','objective_id','operator_facing_summary','reason_code','status','title']}
status['latest_action']=status['objectives'][objective_id]
status['generated_at']=now
status_path.write_text(json.dumps(status,indent=2,sort_keys=True))
managed_path=base/'MIM_TOD_MANAGED_OBJECTIVES.latest.json'
managed=json.loads(managed_path.read_text())
for item in managed.get('objectives',[]):
    if str(item.get('objective_id'))==objective_id:
        item['status']='implementation_completed_with_local_validation'
        item['updated_at']=now
        meta=item.get('metadata_json') if isinstance(item.get('metadata_json'),dict) else {}
        meta['latest_execution']={k:evidence.get(k) for k in ['status','generated_at','artifact','reason_code']}
        item['metadata_json']=meta
managed['generated_at']=now
managed_path.write_text(json.dumps(managed,indent=2,sort_keys=True))
dispatch=base/'MIM_READY_TASK_DISPATCHER_STATUS.latest.json'
dispatch.write_text(json.dumps({'packet_type':'mim-ready-task-dispatcher-status-v1','generated_at':now,'status':'processed_codex_result','objective_id':objective_id,'dispatch_status':'implementation_completed_with_local_validation','reason_code':'codex_result_ingested_database_apply_blocked','result_artifact':evidence['artifact']},indent=2,sort_keys=True))
print('terminal forum image objective state repaired')