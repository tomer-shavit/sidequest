---
name: dnd
description: "Do Not Disturb mode — temporarily pause quests. Use this when the user says 'stop showing me stuff', 'too many quests', 'quest fatigue', 'these are annoying', 'I'm getting too many notifications', 'not now', 'leave me alone', 'stop interrupting', 'I need a break', 'pause quests for a bit', 'quiet mode', 'mute notifications', or expresses frustration about quest frequency."
---

# /sidequest:dnd

Temporarily pause quests with Do Not Disturb mode.

## Steps

1. Parse the duration from the user input. Support these formats:
   - "30m", "1h", "2h", "4h", "8h" → minutes or hours
   - "until tomorrow" → calculate until 9 AM tomorrow
   - "until 5pm" → calculate until 5 PM today
   - If no duration specified, default to 2 hours

2. Calculate the `dnd_until` timestamp as a Unix timestamp (seconds since epoch):
   - Current time + duration in seconds
   - For "until tomorrow": current time until 9 AM tomorrow
   - For "until 5pm": current time until 5 PM today (or tomorrow if past 5 PM)

3. Read the current config:

```bash
cat ~/.sidequest/config.json
```

4. Update the config using Python:

```bash
python3 -c "
import json, os, time, tempfile
config_path = os.path.expanduser('~/.sidequest/config.json')
with open(config_path) as f:
    config = json.load(f)
config['dnd_until'] = <DND_UNTIL_TIMESTAMP>
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(config_path))
with os.fdopen(fd, 'w') as f:
    json.dump(config, f, indent=2)
os.rename(tmp, config_path)
"
```

5. Convert the `dnd_until` timestamp to a human-readable time (e.g., "10:30 PM today" or "April 13 at 9:00 AM").

6. Display confirmation:

```
Do Not Disturb Active
=====================
Quests paused for {duration}
Resumes at: {human_readable_time}

Run /sidequest:dnd cancel to resume immediately.
```

## Cancel Early

If the user says "cancel", "resume", or "turn it off":

1. Read the config
2. Remove the `dnd_until` field entirely:

```bash
python3 -c "
import json, os, tempfile
config_path = os.path.expanduser('~/.sidequest/config.json')
with open(config_path) as f:
    config = json.load(f)
config.pop('dnd_until', None)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(config_path))
with os.fdopen(fd, 'w') as f:
    json.dump(config, f, indent=2)
os.rename(tmp, config_path)
"
```

3. Display: "Do Not Disturb cancelled. Quests will resume normally."

## Error Handling

- If `~/.sidequest/config.json` doesn't exist, tell the user: "SideQuest not configured. Run /sidequest:login first."
- If the duration can't be parsed, ask the user to clarify (e.g., "Please specify a duration like '1h', '30m', 'until tomorrow', or 'until 5pm'").
- If JSON parsing fails, tell the user: "Config file is corrupted. Run /sidequest:login to reset."

## Implementation Note

The stop-hook already checks `dnd_until` automatically. Once you set it, quests stop appearing immediately. The hook exits silently if current time < dnd_until.
