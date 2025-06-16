#!/usr/bin/env bash

# This requires taskwarrior and timewarrior installed on the system.
if timew get dom.active 2>/dev/null | grep -q 1; then
    task_name=$(timew | grep Tracking | cut -d'"' -f2)
    duration=$(timew | grep Total | awk '{print $2}')
    # Extract minutes part from H:MM:SS or MM:SS
    minutes=$(echo "$duration" | awk -F: '{ if (NF == 3) print $2; else
    print $1 }')

    if [ "$minutes" -ge 25 ]; then
        task "$task_name" stop >/dev/null 2>&1
        echo " $task_name - auto-stopped "
    else
        echo "🕒 $task_name — $duration"
    fi
fi
