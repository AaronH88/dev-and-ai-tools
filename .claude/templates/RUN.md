# Agent Entry Point

You are a fresh Claude Code agent working on this project.

## Your Instructions

1. Read `tasks/TASK_LIST.md`
2. Find the line that starts with `→ NEXT:` — this tells you exactly what to do
3. Read the persona file listed for that task
4. Execute the task
5. Update `tasks/TASK_LIST.md` as instructed by the task entry
6. Exit — do not continue to the next task

## Rules

- Do exactly one task entry then stop
- Do not skip ahead
- Do not modify any task entries other than the current one and the `→ NEXT:` cursor
- If the task entry says to read a spec file, read it before doing anything else
- If the task entry says to read a persona file, read it and embody that role fully
- If you are unsure about something, make the simplest reasonable assumption
  and note it in your commit message — do not ask questions
- If you encounter a `[BLOCKED]` entry, stop and report it — do not attempt to fix it
