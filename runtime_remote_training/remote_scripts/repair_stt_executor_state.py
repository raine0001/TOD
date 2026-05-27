import json
from pathlib import Path
from datetime import datetime, timezone
base=Path('/home/testpilot/mim/runtime/shared')
now=datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')
objective_id='MIM-STREAMING-STT-MIGRATION-V1'
speech=json.loads((base/'MIM_SPEECH_TURN_ENGINE_STATUS.latest.json').read_text()) if (base/'MIM_SPEECH_TURN_ENGINE_STATUS.latest.json').exists() else {}
transcript=json.loads((base/'MIM_VOICE_TRANSCRIPT_LOG_STATUS.latest.json').read_text()) if (base/'MIM_VOICE_TRANSCRIPT_LOG_STATUS.latest.json').exists() else {}
patch=json.loads((base/'MIM_VOICE_ROUTE_STT_PATCH.latest.json').read_text()) if (base/'MIM_VOICE_ROUTE_STT_PATCH.latest.json').exists() else {}
last=transcript.get('last_entry') if isinstance(transcript.get('last_entry'),dict) else {}
empty=bool(last) and not str(last.get('transcript') or last.get('normalized_transcript') or '').strip()
evidence={
 'packet_type':'mim-tod-objective-execution-evidence-v2',
 'generated_at':now,
 'objective_id':objective_id,
 'title':'Streaming STT Migration',
 'artifact':f'runtime/shared/MIM_TOD_OBJECTIVE_EVIDENCE.{objective_id}.latest.json',
 'artifact_path':str(base/f'MIM_TOD_OBJECTIVE_EVIDENCE.{objective_id}.latest.json'),
 'status':'blocked_with_evidence' if empty else 'running_with_executor_bound',
 'reason_code':'speech_detected_but_stt_empty' if empty else 'speech_turn_engine_bound',
 'evidence_artifacts':['runtime/shared/MIM_SPEECH_TURN_ENGINE_STATUS.latest.json','runtime/shared/MIM_VOICE_TRANSCRIPT_LOG_STATUS.latest.json','runtime/shared/MIM_VOICE_ROUTE_STT_PATCH.latest.json'],
 'operator_facing_summary':'MIM has a full-time speech turn engine bound and listening, but the latest captured speech produced an empty transcript.' if empty else 'MIM has a full-time speech turn engine bound and listening; STT/router evidence is being refreshed.',
 'next_recovery_action':'Tune STT/VAD against fresh spoken samples and prefer the clean low-noise device that produces non-empty transcripts.' if empty else 'Continue validating live spoken turns through the UI-chat-equivalent route.',
 'validation_requirements':['speech turn creates non-empty transcript','transcript routes to UI-chat-equivalent response path','empty/noise fragments are logged without interrupting Dave'],
 'speech_status':speech,
 'transcript_status':transcript,
 'patch_status':patch,
 'source':'stt_executor_binding_repair',
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
        item['status']=evidence['status']
        item['updated_at']=now
        meta=item.get('metadata_json') if isinstance(item.get('metadata_json'),dict) else {}
        meta['latest_execution']={k:evidence.get(k) for k in ['status','generated_at','artifact','reason_code']}
        item['metadata_json']=meta
managed['generated_at']=now
managed_path.write_text(json.dumps(managed,indent=2,sort_keys=True))
print(evidence['status'], evidence['reason_code'])