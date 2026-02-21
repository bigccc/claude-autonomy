#!/usr/bin/env python3
"""
Autonomy External Loop Driver

External script that drives Claude Code CLI in an infinite loop,
reading tasks from .autonomy/feature_list.json.

Usage:
    python run_autonomy.py [--max-iterations N] [--cooldown SECONDS] [--model MODEL]

This is an alternative to the Stop hook approach (/autocc:run).
Use this when you want to run autonomy from an external terminal process.
"""

import json
import subprocess
import sys
import time
import argparse
import os
from datetime import datetime, timezone


def load_config(path=".autonomy/config.json"):
    if os.path.exists(path):
        try:
            with open(path, "r") as f:
                return json.load(f)
        except (json.JSONDecodeError, ValueError):
            pass
    return {}


def get_task_timeout(config):
    """Get task timeout in seconds from config."""
    minutes = int(config.get("task_timeout_minutes", 30))
    return minutes * 60


def send_notify(event_type, message):
    """Call notify.sh to send webhook notification."""
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "notify.sh")
    if os.path.isfile(script):
        try:
            subprocess.run([script, event_type, message], capture_output=True, timeout=15)
        except Exception:
            pass


def load_feature_list(path=".autonomy/feature_list.json"):
    if not os.path.exists(path):
        print(f"Error: {path} not found. Run /autocc:init first.")
        sys.exit(1)
    with open(path, "r") as f:
        return json.load(f)


def save_feature_list(data, path=".autonomy/feature_list.json"):
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def get_next_task(data):
    """Find the next eligible task using the shared shell script."""
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "get-next-task-json.sh")
    if os.path.isfile(script):
        try:
            result = subprocess.run([script], capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and result.stdout.strip():
                task_json = json.loads(result.stdout.strip())
                task_id = task_json.get("id")
                # Return the matching task from data to keep reference consistency
                return next((f for f in data["features"] if f["id"] == task_id), None)
        except (subprocess.TimeoutExpired, json.JSONDecodeError):
            pass

    # Fallback: inline logic if script unavailable
    done_ids = {f["id"] for f in data["features"] if f["status"] == "done"}

    for f in data["features"]:
        if f["status"] == "in_progress":
            return f

    pending = [
        f for f in data["features"]
        if f["status"] == "pending"
        and (not f.get("dependencies") or all(d in done_ids for d in f["dependencies"]))
    ]
    pending.sort(key=lambda x: x.get("priority", 999))
    return pending[0] if pending else None


def mark_in_progress(data, task_id):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for f in data["features"]:
        if f["id"] == task_id:
            f["status"] = "in_progress"
            f["assigned_at"] = ts
    data["updated_at"] = ts
    save_feature_list(data)


def append_progress(message, path=".autonomy/progress.txt"):
    with open(path, "a") as f:
        f.write(f"\n{message}\n")
    rotate_progress(path)


def rotate_progress(path=".autonomy/progress.txt", config_path=".autonomy/config.json"):
    """Rotate progress.txt, delegating to shared shell script if available."""
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rotate-progress.sh")
    if os.path.isfile(script):
        try:
            subprocess.run([script], capture_output=True, timeout=10)
            return
        except Exception:
            pass

    # Fallback: inline logic
    max_lines = 100
    if os.path.exists(config_path):
        try:
            with open(config_path, "r") as f:
                config = json.load(f)
            max_lines = int(config.get("progress_max_lines", 100))
        except (json.JSONDecodeError, ValueError):
            pass

    if not os.path.exists(path):
        return

    with open(path, "r") as f:
        lines = f.readlines()

    if len(lines) <= max_lines:
        return

    archive_path = path.replace("progress.txt", "progress.archive.txt")
    archive_lines = lines[:-max_lines]
    keep_lines = lines[-max_lines:]

    with open(archive_path, "a") as f:
        f.writelines(archive_lines)

    with open(path, "w") as f:
        f.writelines(keep_lines)


def generate_compact_context():
    """Call compact-context.sh and return the compact JSON string."""
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "compact-context.sh")
    if os.path.isfile(script):
        try:
            subprocess.run([script], capture_output=True, timeout=10)
            compact_path = ".autonomy/context.compact.json"
            if os.path.exists(compact_path):
                with open(compact_path, "r") as f:
                    return f.read().strip()
        except Exception:
            pass
    return ""


def build_prompt(task, progress_tail="", compact_context=""):
    if compact_context:
        return f"""You are an autonomous shift worker. Follow the Autonomy Protocol strictly.

## Compact Context (auto-generated)
{compact_context}

## Instructions
1. Read .autonomy/config.json for project settings
2. The compact context above contains your current task details, dependency info, queue summary, and relevant progress
3. If you need more details about other tasks, read .autonomy/feature_list.json
4. If you need full progress history, read .autonomy/progress.txt
5. Execute the current task, following all acceptance_criteria
6. Verify your work (run tests/lint if configured)
7. Update feature_list.json: set status to "done", set completed_at
8. Append completion summary to progress.txt
9. Git commit with format: feat({task['id']}): {task['title']}

If the task fails, increment attempt_count. If attempt_count >= max_attempts, set status to "failed".
If blocked by dependencies, set status to "blocked" and record the blocker.
"""

    # Fallback: legacy prompt
    criteria = "; ".join(task.get("acceptance_criteria", []))
    deps = ", ".join(task.get("dependencies", [])) or "none"

    return f"""You are an autonomous shift worker. Follow the Autonomy Protocol strictly.

## Current Task
Task {task['id']}: {task['title']}
Description: {task['description']}
Acceptance Criteria: {criteria}
Dependencies: {deps}
Attempt: {task.get('attempt_count', 0) + 1}/{task.get('max_attempts', 3)}

## Recent Progress
{progress_tail}

## Instructions
1. Read .autonomy/progress.txt for full context
2. Read .autonomy/feature_list.json for task details
3. Read .autonomy/config.json for project settings
4. Execute the task above, following all acceptance_criteria
5. Verify your work (run tests/lint if configured)
6. Update feature_list.json: set status to "done", set completed_at
7. Append completion summary to progress.txt
8. Git commit with format: feat({task['id']}): {task['title']}

If the task fails, increment attempt_count. If attempt_count >= max_attempts, set status to "failed".
If blocked by dependencies, set status to "blocked" and record the blocker.
"""


def get_progress_tail(path=".autonomy/progress.txt", lines=20):
    if not os.path.exists(path):
        return ""
    with open(path, "r") as f:
        all_lines = f.readlines()
    return "".join(all_lines[-lines:])


def run_claude(prompt, model=None, timeout_seconds=1800):
    """Run Claude Code CLI with the given prompt."""
    cmd = ["claude", "-p", prompt, "--dangerously-skip-permissions"]
    if model:
        cmd.extend(["--model", model])

    timeout_min = timeout_seconds // 60
    print(f"  Running: claude -p '...' --dangerously-skip-permissions (timeout: {timeout_min}m)")
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", f"Timeout: task exceeded {timeout_min} minutes"
    except FileNotFoundError:
        print("Error: 'claude' CLI not found. Make sure Claude Code is installed.")
        sys.exit(1)


def check_git_status():
    """Check for uncommitted changes that may indicate an interrupted session."""
    try:
        result = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True, timeout=10)
        if result.returncode == 0 and result.stdout.strip():
            return "Uncommitted changes detected from possibly interrupted session"
    except Exception:
        pass
    return ""


def propagate_failure(task_id):
    """Block downstream tasks that depend on a failed task."""
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "propagate-failure.sh")
    if os.path.isfile(script):
        try:
            subprocess.run([script, task_id], capture_output=True, timeout=10)
        except Exception:
            pass


def git_rollback():
    """Rollback uncommitted changes on failure."""
    try:
        subprocess.run(["git", "checkout", "."], capture_output=True, timeout=30)
        print("  Git rollback: uncommitted changes reverted.")
    except Exception:
        pass


def main():
    parser = argparse.ArgumentParser(description="Autonomy External Loop Driver")
    parser.add_argument("--max-iterations", type=int, default=0, help="Max iterations (0=unlimited)")
    parser.add_argument("--cooldown", type=int, default=5, help="Seconds between iterations")
    parser.add_argument("--model", type=str, default=None, help="Model to use (e.g. opus, sonnet)")
    args = parser.parse_args()

    print("=" * 50)
    print("Autonomy External Loop Driver")
    print("=" * 50)

    config = load_config()
    timeout_seconds = get_task_timeout(config)

    iteration = 0
    while True:
        iteration += 1

        if args.max_iterations > 0 and iteration > args.max_iterations:
            print(f"\nMax iterations ({args.max_iterations}) reached. Stopping.")
            break

        data = load_feature_list()
        task = get_next_task(data)

        if not task:
            remaining = [f for f in data["features"] if f["status"] in ("pending", "blocked")]
            if remaining:
                print(f"\nNo eligible tasks (remaining are blocked). Stopping.")
            else:
                print(f"\nAll tasks completed!")
                send_notify("all_done", "所有任务已完成！")
            break

        task_id = task["id"]
        task_title = task["title"]
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        print(f"\n--- Iteration {iteration} | {ts} ---")
        print(f"  Task: {task_id} - {task_title}")

        # Mark in_progress if not already
        if task["status"] != "in_progress":
            mark_in_progress(data, task_id)
        else:
            # Resuming an interrupted task — check for uncommitted changes
            git_warning = check_git_status()
            if git_warning:
                print(f"  ⚠️  {git_warning}")

        # Build prompt and run
        compact_context = generate_compact_context()
        if compact_context:
            prompt = build_prompt(task, compact_context=compact_context)
        else:
            progress_tail = get_progress_tail()
            prompt = build_prompt(task, progress_tail=progress_tail)

        append_progress(f"=== External Loop Iteration {iteration} | {ts} ===\nTask: {task_id} - {task_title}\nStatus: STARTED")

        returncode, stdout, stderr = run_claude(prompt, model=args.model, timeout_seconds=timeout_seconds)

        # Check result
        data = load_feature_list()  # Reload, Claude may have modified it
        current_task = next((f for f in data["features"] if f["id"] == task_id), None)

        if current_task and current_task["status"] == "done":
            print(f"  Result: COMPLETED")
            send_notify("task_done", f"任务 {task_id} ({task_title}) 已完成")
        elif current_task and current_task["status"] == "failed":
            print(f"  Result: FAILED (attempt {current_task.get('attempt_count', '?')}/{current_task.get('max_attempts', '?')})")
            propagate_failure(task_id)
            send_notify("task_failed", f"任务 {task_id} ({task_title}) 失败")
        elif returncode == -1:
            # Timeout
            print(f"  Result: TIMEOUT")
            if current_task:
                current_task["attempt_count"] = current_task.get("attempt_count", 0) + 1
                max_attempts = current_task.get("max_attempts", 3)
                if current_task["attempt_count"] >= max_attempts:
                    current_task["status"] = "failed"
                    print(f"  Max attempts reached. Marking as failed.")
                    save_feature_list(data)
                    propagate_failure(task_id)
                    send_notify("task_failed", f"任务 {task_id} ({task_title}) 超时后失败")
                else:
                    current_task["status"] = "pending"
                    save_feature_list(data)
                    send_notify("task_timeout", f"任务 {task_id} ({task_title}) 超时，将重试")
            git_rollback()
            append_progress(f"Task: {task_id}\nStatus: TIMEOUT\nDetails: {stderr}\n===")
        elif returncode != 0:
            print(f"  Result: ERROR (exit code {returncode})")
            if stderr:
                print(f"  Stderr: {stderr[:200]}")
            # Increment attempt count
            if current_task:
                current_task["attempt_count"] = current_task.get("attempt_count", 0) + 1
                max_attempts = current_task.get("max_attempts", 3)
                if current_task["attempt_count"] >= max_attempts:
                    current_task["status"] = "failed"
                    print(f"  Max attempts reached. Marking as failed.")
                    save_feature_list(data)
                    propagate_failure(task_id)
                    send_notify("task_failed", f"任务 {task_id} ({task_title}) 错误后失败")
                else:
                    current_task["status"] = "pending"
                    save_feature_list(data)
            git_rollback()
            append_progress(f"Task: {task_id}\nStatus: ERROR\nDetails: Exit code {returncode}\n===")
        else:
            print(f"  Result: Claude exited normally, task status: {current_task['status'] if current_task else 'unknown'}")

        # Cooldown
        if args.cooldown > 0:
            print(f"  Cooling down {args.cooldown}s...")
            time.sleep(args.cooldown)

    print("\n" + "=" * 50)
    print("Autonomy loop finished.")

    # Final summary
    summary_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "summary.sh")
    if os.path.isfile(summary_script):
        subprocess.run([summary_script], timeout=10)
    else:
        data = load_feature_list()
        done = len([f for f in data["features"] if f["status"] == "done"])
        total = len(data["features"])
        print(f"Completed: {done}/{total} tasks")
    print("=" * 50)


if __name__ == "__main__":
    main()
