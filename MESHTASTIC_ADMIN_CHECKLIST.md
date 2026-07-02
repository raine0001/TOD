# MESHTASTIC ADMIN DEPLOYMENT CHECKLIST
## Pre-Departure & Day-of-Departure

---

## PHASE 1: RADIO SETUP (Do this before crew boards)

### Node PA (Port A) Configuration
- [ ] **Power On**: USB power connected and stable
- [ ] **Firmware**: Verify version 2.7.15.567b8ea (via CLI: `--info`)
- [ ] **Region**: Set to **US**
- [ ] **Modem**: LONG_FAST preset
- [ ] **Primary Channel Name**: SHIP-GROUP
- [ ] **Primary Channel PSK**: Strong secret (do not share outside crew)
- [ ] **Bluetooth Mode**: FIXED_PIN
- [ ] **Bluetooth PIN**: 2277
- [ ] **TX Power**: 30 dBm (or lower if power/heat concern)
- [ ] **Rebroadcast Mode**: ALL
- [ ] **Hop Limit**: 3
- [ ] **Location**: Physical position marked on ship diagram

### Node SB (Starboard B) Configuration
- [ ] **Power On**: USB power connected and stable
- [ ] **Firmware**: Verify version 2.7.15.567b8ea
- [ ] **Region**: Set to **US**
- [ ] **Modem**: LONG_FAST preset
- [ ] **Primary Channel Name**: SHIP-GROUP (match PA)
- [ ] **Primary Channel PSK**: Identical to PA
- [ ] **Bluetooth Mode**: FIXED_PIN
- [ ] **Bluetooth PIN**: 2277 (match PA)
- [ ] **TX Power**: 30 dBm
- [ ] **Rebroadcast Mode**: ALL
- [ ] **Hop Limit**: 3
- [ ] **Location**: Physical position marked on ship diagram

### Node Linkage Verification
- [ ] **Test message from PA**: `python -m meshtastic --port COM6 --sendtext "PREFLIGHT CHECK PA"`
- [ ] **Test message from SB**: `python -m meshtastic --port COM7 --sendtext "PREFLIGHT CHECK SB"`
- [ ] **CLI listen on PA**: Confirm SB's message arrives (0 hops)
- [ ] **CLI listen on SB**: Confirm PA's message arrives (0 hops)
- [ ] **Node List Check**: Both PA and SB see each other in `--nodes` output

---

## PHASE 2: CREW PREPARATION (Before boarding or first morning)

### Group Communication
- [ ] **Announce**: "Meshtastic is live. All phones must connect before operations."
- [ ] **Distribute**: Hand out or email:
  - MESHTASTIC_SHIP_SETUP_GUIDE.md (full guide)
  - MESHTASTIC_QUICK_CARD.md (pocket reference)

### Pre-Board Individual Setup (Each crew member)
- [ ] **App installed** on their phone (Android or iOS)
- [ ] **Location enabled** (system settings)
- [ ] **Bluetooth enabled** (system settings)
- [ ] **Permissions granted** (nearby devices, location, notifications)
- [ ] **Display name set** (FirstName-Initial format, e.g., Sam-R)
- [ ] **Test connection** to nearest node (PA or SB) with PIN 2277

### Crew Connection Spot Check
- [ ] **Count connected**: Ask each person to send a message to SHIP-GROUP
- [ ] **Verify receipt**: All crew confirm they see the test message
- [ ] **Node balance**: Monitor if one node is over-subscribed; if so, ask some users to connect to the other node

---

## PHASE 3: DAY-OF-DEPARTURE FINAL CHECK (Morning of departure)

### Radio Health Check
- [ ] **PA Power**: Verify USB power indicator or LED
- [ ] **SB Power**: Verify USB power indicator or LED
- [ ] **PA Reachability**: `python -m meshtastic --port COM6 --nodes` → SB visible?
- [ ] **SB Reachability**: `python -m meshtastic --port COM7 --nodes` → PA visible?
- [ ] **Message roundtrip**: Send test message PA → SB, confirm arrival within 2 seconds

### Crew Connectivity
- [ ] **Full crew connected**: Spot check 2–3 random crew members for "Connected" status
- [ ] **Channel confirmation**: Ask crew to confirm they see SHIP-GROUP in the app
- [ ] **Test message sent**: One crew member sends group test message
- [ ] **All crew confirm receipt** within 5 seconds

### Documentation
- [ ] **Backup**: Export both node configs (keep PC copy for emergency reset)
- [ ] **Channel QR**: Do NOT share outside crew
- [ ] **PIN reminder**: Confirm crew knows PIN is 2277

---

## PHASE 4: FIRST-DAY OPERATIONS (Once underway)

### Morning Brief
- [ ] **Crew standing**: "Meshtastic is primary comms. Internet unavailable."
- [ ] **Emergency protocol**: Define fallback if radios fail (e.g., handheld walkie-talkies)
- [ ] **Message discipline**: No spam, keep to short operational messages

### Continuous Monitoring (at least once per watch)
- [ ] **Node status**: Both PA and SB still online and linked?
- [ ] **Message latency**: Typical message delivery < 2 seconds?
- [ ] **Crew count**: All expected crew shown as connected?
- [ ] **Problem reports**: Any crew unable to connect? (troubleshoot per quick card)

### Daily Checklist (Evening)
- [ ] **Radio uptime**: Both nodes still powered and linked
- [ ] **Crew satisfaction**: Any complaints or connection issues?
- [ ] **Message volume**: Normal traffic or unusual activity?
- [ ] **Battery health**: Any signs of over-discharge (rare with USB power)

---

## TROUBLESHOOTING TREE

### Problem: One node offline or not responding

**Action:**
1. Check USB power on that node
2. Restart the radio (disconnect USB, wait 10 sec, reconnect)
3. Re-verify via CLI: `python -m meshtastic --port COMx --info`
4. If still failing, restore from backup config or re-import settings

### Problem: Crew cannot connect despite following guide

**Action:**
1. Confirm Bluetooth is ON and Location is ON on their phone
2. Toggle Bluetooth off → wait 3 sec → on
3. Force-close Meshtastic app (Settings → Apps → Meshtastic → Force Stop)
4. Reopen app and retry with PIN 2277
5. If still failing, have them connect to the **other node** (PA ↔ SB)
6. If both fail, ask if another crew member's phone is occupying the BLE slot

### Problem: Messages not arriving between nodes

**Action:**
1. Verify both nodes are on SHIP-GROUP primary channel (CLI)
2. Verify channel PSK is identical on both nodes
3. Verify modem preset is LONG_FAST on both (CLI)
4. Send test message via CLI from PA, monitor SB listener for receipt
5. If received at SB, issue is app-side; restart app on crew phones

### Problem: Intermittent connectivity (connected then disconnected)

**Action:**
1. Android: Check battery optimization (set to "No restrictions" for Meshtastic)
2. Move user to the **other node** if current node is congested
3. Enable Bluetooth troubleshooting via Settings → Developer Options (if available)
4. Consider Wi-Fi AP mode on one node if BLE saturation is chronic

---

## FALLBACK: Wi-Fi AP Mode (If BLE Saturated)

If more than 2–3 phones need simultaneous connection to one node:

1. **Admin action**: Enable Wi-Fi on that node
   ```
   python -m meshtastic --port COMx --set network.wifiEnabled true
   python -m meshtastic --port COMx --set network.wifiSsid "SHIP-PA-OPEN"
   python -m meshtastic --port COMx --set network.wifiPsk "password123"
   ```
2. **Crew action**: Forget Bluetooth, connect via Wi-Fi SSID instead
3. **Tradeoff**: Wi-Fi uses more power, but supports unlimited simultaneous users

---

## CONTACTS & ESCALATION

| Issue | First Contact | Escalation |
|---|---|---|
| User connection help | You (Admin) | Refer to quick card |
| Node offline | You (Admin) | Restart radio, restore config |
| Channel corruption | You (Admin) | Export backup, reset both nodes |
| No fix works | Meshtastic Discord or GitHub Issues | Emergency fallback comms |

---

## END-OF-VOYAGE CHECKLIST

- [ ] **Disconnect radios** from USB power gracefully
- [ ] **Backup final state** (export node configs)
- [ ] **Document lessons learned** (any issues, workarounds)
- [ ] **Reset PIN** to 123456 before next crew takes over (or keep 2277)

---

**Prepared by:** Admin  
**Date:** [Departure Date]  
**Nodes:** PA, SB  
**Channel:** SHIP-GROUP  
**PIN:** 2277  
**Status:** READY FOR DEPLOYMENT

