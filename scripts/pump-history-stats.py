import json
import sys

def main():
    pump_history = json.loads(sys.stdin.read())
    bolus_total = 0.0
    rate_total = 0.0
    duration_total = 0.0
    smb_count = 0
    bolus_count = 0
    temp_basal_count = 0
    suspend_count = 0
    resume_count = 0

    for event in pump_history:
        if 'amount' in event:
            bolus_total += event['amount']
            if event.get('isSMB', False):
                smb_count += 1
            bolus_count += 1
        if 'rate' in event:
            rate_total += event['rate']
            temp_basal_count += 1
        if 'duration (min)' in event:
            duration_total += event['duration (min)']
        if event['_type'] == 'PumpSuspend':
            suspend_count += 1
        if event['_type'] == 'PumpResume':
            resume_count += 1

    print(f'bolus_total: {bolus_total}')
    print(f'rate_total: {rate_total}')
    print(f'duration_total: {duration_total}')
    print(f'smb_count: {smb_count}')
    print(f'bolus_count: {bolus_count}')
    print(f'temp_basal_count: {temp_basal_count}')
    print(f'suspend_count: {suspend_count}')
    print(f'resume_count: {resume_count}')

if __name__ == '__main__':
    main()
