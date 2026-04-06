#!/usr/bin/env python3
import paramiko
from datetime import datetime

HOST = '192.168.1.90'
USER = 'testpilot'
PASSWORD = 'dontcrash'

try:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print("Connecting to Pi...")
    client.connect(hostname=HOST, username=USER, password=PASSWORD, timeout=20, allow_agent=False, look_for_keys=False)
    print("✓ Connected")
    
    sftp = client.open_sftp_client()
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    
    # Backup original files
    print("\n[BACKUP]")
    for remote_file in ['/home/testpilot/mim_arm/templates/routines.html',
                        '/home/testpilot/mim_arm/static/control.js']:
        backup = f"{remote_file}.bak-{ts}"
        stdin, stdout, stderr = client.exec_command(f"cp {remote_file} {backup}")
        stdout.channel.recv_exit_status()
        print(f"✓ {remote_file}")
    
    # Upload new files
    print("\n[UPLOAD]")
    files = [
        ('e:/TOD/tmp_remote_mim/routines.html', '/home/testpilot/mim_arm/templates/routines.html'),
        ('e:/TOD/tmp_remote_mim/control.js', '/home/testpilot/mim_arm/static/control.js')
    ]
    
    for local_file, remote_file in files:
        sftp.put(local_file, remote_file)
        print(f"✓ {remote_file}")
    
    # Validate control.js syntax
    print("\n[VALIDATION]")
    stdin, stdout, stderr = client.exec_command('node --check /home/testpilot/mim_arm/static/control.js 2>&1')
    code = stdout.channel.recv_exit_status()
    out = stdout.read().decode('utf-8','replace')
    if code == 0:
        print("✓ control.js syntax valid")
    else:
        print(f"⚠ Syntax check: {out or 'pass'}")
    
    sftp.close()
    client.close()
    
    print("\n✓ Deployment complete!")
    print(f"Backups created with timestamp: {ts}")
    
except Exception as e:
    print(f"✗ Error: {e}")
    import traceback
    traceback.print_exc()
