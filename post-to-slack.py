#!/usr/bin/env python3
"""
Helper script to post package drop notifications to Slack
Usage: python3 post-to-slack.py <channel_id> <vertical> <version> <work_number> <last_merge> <sign_off> <release>
"""

import sys
import json
from datetime import datetime

def format_slack_message(vertical, version, work_number, last_merge, sign_off, release, last_merge_time, sign_off_time, is_monthly=False):
    """Format the Slack message for package drop notification"""

    # Parse dates and calculate day of week
    try:
        # Parse dates in format MM/DD and add year from release date
        release_date = datetime.strptime(release, "%Y-%m-%d")
        year = release_date.year

        last_merge_month, last_merge_day = last_merge.split('/')
        sign_off_month, sign_off_day = sign_off.split('/')

        last_merge_date = datetime(year, int(last_merge_month), int(last_merge_day))
        sign_off_date = datetime(year, int(sign_off_month), int(sign_off_day))

        last_merge_dow = last_merge_date.strftime("%a")
        sign_off_dow = sign_off_date.strftime("%a")
        release_dow = release_date.strftime("%a")

        last_merge_full = f"{last_merge_month}/{last_merge_day}/{year}"
        sign_off_full = f"{sign_off_month}/{sign_off_day}/{year}"
        release_full = f"{release_date.month}/{release_date.day}/{year}"

    except Exception as e:
        print(f"Error parsing dates: {e}", file=sys.stderr)
        sys.exit(1)

    branch_type = "Monthly Patch" if is_monthly else "Patch"
    message = f"""```
Please open the {branch_type} branch {vertical} {version} (post upmerge). Here is the GUS Work {work_number}
Team kindly make sure PR has two level of approvals (before sharing), one of which should be the Manager Approval. Also ensure that PR builds are not failing.
For this patch Aarti Somani will be the RM and Amarendar Musham will be Release Engineer. Please tag us for any assistance.
Schedule:
Last Merge: {last_merge_full}({last_merge_dow} at {last_merge_time})
Q3 Sign Off: {sign_off_full}({sign_off_dow} at {sign_off_time})
Release Deployment: {release_full}
```"""

    return message

def main():
    if len(sys.argv) < 9:
        print("Usage: post-to-slack.py <channel_id> <vertical> <version> <work_number> <last_merge> <sign_off> <release> <last_merge_time> <sign_off_time>")
        sys.exit(1)

    channel_id = sys.argv[1]
    vertical = sys.argv[2]
    version = sys.argv[3]
    work_number = sys.argv[4]
    last_merge = sys.argv[5]
    sign_off = sys.argv[6]
    release = sys.argv[7]
    last_merge_time = sys.argv[8] if len(sys.argv) > 8 else "11:30 AM IST"
    sign_off_time = sys.argv[9] if len(sys.argv) > 9 else "03:00 PM IST"
    is_monthly = sys.argv[10].lower() == "true" if len(sys.argv) > 10 else False

    message = format_slack_message(vertical, version, work_number, last_merge, sign_off, release, last_merge_time, sign_off_time, is_monthly)

    # Output the formatted message as JSON for the bash script to use
    output = {
        "channel_id": channel_id,
        "message": message,
        "vertical": vertical,
        "work_number": work_number,
        "thread_reply": "<@U08TFFLU9HP> FYA"
    }

    print(json.dumps(output))

if __name__ == "__main__":
    main()
