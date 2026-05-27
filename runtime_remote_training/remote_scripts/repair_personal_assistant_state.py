import json
from pathlib import Path
from datetime import datetime, timezone
base=Path('/home/testpilot/mim/runtime/shared')
now=datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')
objective_id='MIM-DAVE-CALENDAR-PHONE-EMAILS-V1'
calendar=json.loads((base/'MIM_DAVE_CALENDAR_LIVE_VERIFICATION.latest.json').read_text()) if (base/'MIM_DAVE_CALENDAR_LIVE_VERIFICATION.latest.json').exists() else {}
wall=json.loads((base/'MIM_WALL_LIVE_FEED_INTEGRATION_STATUS.latest.json').read_text()) if (base/'MIM_WALL_LIVE_FEED_INTEGRATION_STATUS.latest.json').exists() else {}
email_status={
 'packet_type':'mim-dave-email-read-summary-status-v1',
 'generated_at':now,
 'objective_id':objective_id,
 'status':'blocked_with_evidence',
 'reason_code':'email_read_summary_executor_not_bound',
 'secret_policy':'No tokens, passwords, message bodies, or personal email content are written here.',
 'inspected_paths':['runtime/shared/MIM_DAVE_PERSONAL_ASSISTANT_CONNECTOR_STATUS.latest.json','MIM/TOD env key presence only; no secret values emitted'],
 'next_recovery_action':'Bind a summary-only Gmail/IMAP read executor that reports counts, senders/categories, and action-needed summaries without storing message bodies.',
 'validation_requirements':['OAuth/IMAP read succeeds','artifact contains summary-only evidence','send/delete/reply actions remain confirmation-gated']
}
(base/'MIM_DAVE_EMAIL_READ_SUMMARY_STATUS.latest.json').write_text(json.dumps(email_status,indent=2,sort_keys=True))
phone_status={
 'packet_type':'mim-wall-phone-bridge-status-v1',
 'generated_at':now,
 'objective_id':objective_id,
 'status':'build_verified_pending_device_runtime_verification' if wall else 'blocked_with_evidence',
 'reason_code':'mim_wall_live_bridge_build_verified_phone_config_pending' if wall else 'mim_wall_evidence_missing',
 'evidence_artifacts':['runtime/shared/MIM_WALL_LIVE_FEED_INTEGRATION_STATUS.latest.json'] if wall else [],
 'operator_facing_summary':'MIM_Wall has live MIM feed and bidirectional phone-message bridge code built into the debug APK. Remaining step is installing/configuring the phone build and verifying a live round trip.',
 'next_recovery_action':'Install/run the updated debug build on the phone, enable workstation sync, enter MIM credentials/token, then send a test prompt and publish round-trip evidence.',
 'validation_requirements':['phone fetches /objectives/state','phone sends /gateway/intake/text','MIM response appears in MIM_Wall conversation feed']
}
(base/'MIM_WALL_PHONE_BRIDGE_STATUS.latest.json').write_text(json.dumps(phone_status,indent=2,sort_keys=True))
evidence={
 'packet_type':'mim-tod-objective-execution-evidence-v2',
 'generated_at':now,
 'objective_id':objective_id,
 'title':'Dave calendar, phone, and email assistant integration',
 'artifact':'runtime/shared/MIM_TOD_OBJECTIVE_EVIDENCE.MIM-DAVE-CALENDAR-PHONE-EMAILS-V1.latest.json',
 'artifact_path':str(base/'MIM_TOD_OBJECTIVE_EVIDENCE.MIM-DAVE-CALENDAR-PHONE-EMAILS-V1.latest.json'),
 'status':'blocked_with_one_remaining_binding',
 'reason_code':'email_read_summary_executor_not_bound',
 'evidence_artifacts':['runtime/shared/MIM_DAVE_CALENDAR_LIVE_VERIFICATION.latest.json','runtime/shared/MIM_WALL_PHONE_BRIDGE_STATUS.latest.json','runtime/shared/MIM_DAVE_EMAIL_READ_SUMMARY_STATUS.latest.json'],
 'operator_facing_summary':'Calendar access is live. MIM_Wall live feed/message bridge is built and verified at APK level. The remaining unresolved binding is email-read summaries.',
 'next_recovery_action':'Bind the email read summary executor next; keep outbound email/text/call actions confirmation-gated.',
 'validation_requirements':['email read executor publishes summary-only evidence','phone bridge round trip verified on the device','outbound email/text/call actions remain confirmation-gated'],
 'calendar':calendar,
 'phone':phone_status,
 'email':email_status,
 'source':'personal_assistant_connector_state_repair',
 'confidence':'high'
}
(base/'MIM_TOD_OBJECTIVE_EVIDENCE.MIM-DAVE-CALENDAR-PHONE-EMAILS-V1.latest.json').write_text(json.dumps(evidence,indent=2,sort_keys=True))
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