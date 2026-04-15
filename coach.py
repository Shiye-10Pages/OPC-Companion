#!/usr/bin/env python3
"""
OPC 伴侣 - 个人工作节奏教练
用法:
    coach start "任务描述" 25       # 开始 25 分钟专注
    coach status                   # 查看当前状态
    coach done                     # 完成当前任务
    coach cancel                   # 取消当前任务
    coach log                      # 查看历史记录
"""

import json
import os
import sys
import signal
import time
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

DATA_DIR = Path.home() / ".coach"
STATE_FILE = DATA_DIR / "state.json"
HISTORY_FILE = DATA_DIR / "history.jsonl"
PID_FILE = DATA_DIR / "daemon.pid"


def ensure_data_dir():
    DATA_DIR.mkdir(parents=True, exist_ok=True)


# ── macOS 通知 & 对话 ──────────────────────────────────

def notify(title, message, sound="Glass"):
    subprocess.run([
        "osascript", "-e",
        f'display notification "{message}" with title "{title}" sound name "{sound}"'
    ], capture_output=True)


def ask_dialog(title, message):
    script = f'''
set dialogResult to display dialog "{message}" with title "{title}" ¬
    default answer "" ¬
    buttons {{"完成了", "还需要时间", "取消"}} ¬
    default button "还需要时间" ¬
    giving up after 300
set btn to button returned of dialogResult
set txt to text returned of dialogResult
return btn & "|||" & txt
'''
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return None
    parts = result.stdout.strip().split("|||", 1)
    return {
        "button": parts[0],
        "text": parts[1] if len(parts) > 1 else ""
    }


def ask_extend_duration(title):
    script = f'''
set dialogResult to display dialog "还需要多少分钟？" with title "{title}" ¬
    default answer "15" ¬
    buttons {{"确定"}} ¬
    default button "确定"
return text returned of dialogResult
'''
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return 15
    try:
        return int(result.stdout.strip())
    except ValueError:
        return 15


# ── 状态管理 ──────────────────────────────────────────

def load_state():
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return None


def save_state(state):
    ensure_data_dir()
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2))


def clear_state():
    if STATE_FILE.exists():
        STATE_FILE.unlink()


def append_history(record):
    ensure_data_dir()
    with open(HISTORY_FILE, "a") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


# ── 守护进程 ──────────────────────────────────────────

def kill_existing_daemon():
    if not PID_FILE.exists():
        return
    try:
        pid = int(PID_FILE.read_text().strip())
        os.kill(pid, signal.SIGTERM)
        time.sleep(0.5)
    except (ProcessLookupError, ValueError):
        pass
    PID_FILE.unlink(missing_ok=True)


def daemonize():
    pid = os.fork()
    if pid > 0:
        return False  # parent
    os.setsid()
    pid2 = os.fork()
    if pid2 > 0:
        os._exit(0)
    # daemon process
    sys.stdin.close()
    PID_FILE.write_text(str(os.getpid()))
    return True  # child (daemon)


def daemon_loop():
    while True:
        state = load_state()
        if not state:
            break

        now = datetime.now()
        end_time = datetime.fromisoformat(state["end_time"])
        start_time = datetime.fromisoformat(state["start_time"])
        total_seconds = (end_time - start_time).total_seconds()
        elapsed_seconds = (now - start_time).total_seconds()
        remaining_seconds = (end_time - now).total_seconds()
        task = state["task"]
        title = f"OPC 伴侣"

        # 80% 提醒（只触发一次）
        if not state.get("notified_80"):
            threshold_80 = total_seconds * 0.8
            if elapsed_seconds >= threshold_80 and remaining_seconds > 0:
                remaining_min = int(remaining_seconds / 60) + 1
                notify(title, f"「{task}」还剩 {remaining_min} 分钟")
                state["notified_80"] = True
                save_state(state)

        # 到时间了 → 弹对话框
        if remaining_seconds <= 0:
            overtime_min = int(-remaining_seconds / 60)
            if overtime_min == 0:
                msg = f"「{task}」时间到了！\n进展如何？"
            else:
                msg = f"「{task}」已超时 {overtime_min} 分钟。\n进展如何？"

            response = ask_dialog(title, msg)

            if response is None:
                # 对话框被忽略（超时），10 分钟后再问
                time.sleep(600)
                continue

            if response["button"] == "完成了":
                finish_session(state, response["text"] or "已完成")
                break

            elif response["button"] == "还需要时间":
                extra = ask_extend_duration(title)
                new_end = datetime.now() + timedelta(minutes=extra)
                state["end_time"] = new_end.isoformat()
                state["notified_80"] = False
                state["extensions"] = state.get("extensions", 0) + 1
                if response["text"]:
                    state.setdefault("notes", []).append({
                        "time": now.isoformat(),
                        "text": response["text"]
                    })
                save_state(state)
                notify(title, f"好的，再给你 {extra} 分钟")

            elif response["button"] == "取消":
                cancel_session(state)
                break

        time.sleep(30)  # 每 30 秒检查一次

    PID_FILE.unlink(missing_ok=True)


def finish_session(state, note=""):
    end_actual = datetime.now().isoformat()
    start = datetime.fromisoformat(state["start_time"])
    actual_min = int((datetime.now() - start).total_seconds() / 60)

    record = {
        "task": state["task"],
        "planned_minutes": state["planned_minutes"],
        "actual_minutes": actual_min,
        "extensions": state.get("extensions", 0),
        "start_time": state["start_time"],
        "end_time": end_actual,
        "notes": state.get("notes", []),
        "final_note": note,
        "status": "done"
    }
    append_history(record)
    clear_state()
    notify("OPC 伴侣", f"「{state['task']}」完成！用时 {actual_min} 分钟")


def cancel_session(state):
    start = datetime.fromisoformat(state["start_time"])
    actual_min = int((datetime.now() - start).total_seconds() / 60)

    record = {
        "task": state["task"],
        "planned_minutes": state["planned_minutes"],
        "actual_minutes": actual_min,
        "start_time": state["start_time"],
        "end_time": datetime.now().isoformat(),
        "notes": state.get("notes", []),
        "status": "cancelled"
    }
    append_history(record)
    clear_state()


# ── CLI 命令 ──────────────────────────────────────────

def cmd_start(args):
    if len(args) < 2:
        print("用法: coach start \"任务描述\" 分钟数")
        print("例如: coach start \"写口播稿\" 25")
        sys.exit(1)

    task = args[0]
    try:
        duration = int(args[1])
    except ValueError:
        print(f"分钟数必须是数字，你输入的是: {args[1]}")
        sys.exit(1)

    existing = load_state()
    if existing:
        print(f"当前已有进行中的任务: 「{existing['task']}」")
        print("请先 coach done 或 coach cancel")
        sys.exit(1)

    now = datetime.now()
    end = now + timedelta(minutes=duration)

    state = {
        "task": task,
        "planned_minutes": duration,
        "start_time": now.isoformat(),
        "end_time": end.isoformat(),
        "extensions": 0,
        "notes": []
    }

    kill_existing_daemon()
    ensure_data_dir()
    save_state(state)

    print(f"  开始专注: 「{task}」")
    print(f"  计划时长: {duration} 分钟")
    print(f"  结束时间: {end.strftime('%H:%M')}")
    print()
    print("  到时间我会来找你。专心干活吧！")

    is_daemon = daemonize()
    if is_daemon:
        daemon_loop()
        os._exit(0)


def cmd_status(args):
    state = load_state()
    if not state:
        print("  当前没有进行中的任务。")
        print("  用 coach start \"任务\" 分钟数 开始一个。")
        return

    now = datetime.now()
    start = datetime.fromisoformat(state["start_time"])
    end = datetime.fromisoformat(state["end_time"])
    elapsed = int((now - start).total_seconds() / 60)
    remaining = int((end - now).total_seconds() / 60)

    print(f"  任务: 「{state['task']}」")
    print(f"  已用: {elapsed} 分钟")
    if remaining > 0:
        print(f"  剩余: {remaining} 分钟")
    else:
        print(f"  超时: {-remaining} 分钟")
    if state.get("extensions", 0) > 0:
        print(f"  延长: {state['extensions']} 次")


def cmd_done(args):
    state = load_state()
    if not state:
        print("  当前没有进行中的任务。")
        return

    note = " ".join(args) if args else ""
    kill_existing_daemon()
    finish_session(state, note)

    start = datetime.fromisoformat(state["start_time"])
    actual = int((datetime.now() - start).total_seconds() / 60)
    print(f"  「{state['task']}」已完成！用时 {actual} 分钟。")


def cmd_cancel(args):
    state = load_state()
    if not state:
        print("  当前没有进行中的任务。")
        return

    kill_existing_daemon()
    cancel_session(state)
    print(f"  「{state['task']}」已取消。")


def cmd_log(args):
    if not HISTORY_FILE.exists():
        print("  还没有历史记录。")
        return

    lines = HISTORY_FILE.read_text().strip().split("\n")
    recent = lines[-10:]  # 最近 10 条

    for line in recent:
        r = json.loads(line)
        status_icon = "done" if r["status"] == "done" else "cancelled"
        date = datetime.fromisoformat(r["start_time"]).strftime("%m/%d %H:%M")
        ext = f" (+{r.get('extensions', 0)})" if r.get("extensions", 0) > 0 else ""
        print(f"  [{date}] {r['task']}  {r['planned_minutes']}m → {r['actual_minutes']}m{ext}  {status_icon}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    cmd = sys.argv[1]
    args = sys.argv[2:]

    commands = {
        "start": cmd_start,
        "status": cmd_status,
        "s": cmd_status,
        "done": cmd_done,
        "d": cmd_done,
        "cancel": cmd_cancel,
        "log": cmd_log,
        "l": cmd_log,
    }

    if cmd in commands:
        commands[cmd](args)
    else:
        print(f"未知命令: {cmd}")
        print("可用命令: start, status, done, cancel, log")
        sys.exit(1)


if __name__ == "__main__":
    main()
