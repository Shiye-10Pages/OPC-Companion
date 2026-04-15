import json
import sys
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch, MagicMock
import tempfile
import os

sys.path.insert(0, str(Path(__file__).parent))
import coach


class TestStateManagement(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.orig_data_dir = coach.DATA_DIR
        coach.DATA_DIR = Path(self.tmp.name)
        coach.STATE_FILE = coach.DATA_DIR / "state.json"
        coach.HISTORY_FILE = coach.DATA_DIR / "history.jsonl"
        coach.PID_FILE = coach.DATA_DIR / "daemon.pid"

    def tearDown(self):
        coach.DATA_DIR = self.orig_data_dir
        coach.STATE_FILE = self.orig_data_dir / "state.json"
        coach.HISTORY_FILE = self.orig_data_dir / "history.jsonl"
        coach.PID_FILE = self.orig_data_dir / "daemon.pid"
        self.tmp.cleanup()

    def test_load_state_returns_none_when_no_file(self):
        self.assertIsNone(coach.load_state())

    def test_save_and_load_state(self):
        state = {"task": "写测试", "planned_minutes": 25}
        coach.save_state(state)
        loaded = coach.load_state()
        self.assertEqual(loaded["task"], "写测试")
        self.assertEqual(loaded["planned_minutes"], 25)

    def test_clear_state(self):
        coach.save_state({"task": "test"})
        coach.clear_state()
        self.assertIsNone(coach.load_state())

    def test_append_history(self):
        record1 = {"task": "任务1", "status": "done"}
        record2 = {"task": "任务2", "status": "cancelled"}
        coach.append_history(record1)
        coach.append_history(record2)
        lines = coach.HISTORY_FILE.read_text().strip().split("\n")
        self.assertEqual(len(lines), 2)
        self.assertEqual(json.loads(lines[0])["task"], "任务1")
        self.assertEqual(json.loads(lines[1])["task"], "任务2")


class TestCmdStart(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        coach.DATA_DIR = Path(self.tmp.name)
        coach.STATE_FILE = coach.DATA_DIR / "state.json"
        coach.HISTORY_FILE = coach.DATA_DIR / "history.jsonl"
        coach.PID_FILE = coach.DATA_DIR / "daemon.pid"

    def tearDown(self):
        self.tmp.cleanup()

    @patch("coach.daemonize", return_value=False)
    @patch("coach.kill_existing_daemon")
    def test_start_creates_state(self, mock_kill, mock_daemon):
        coach.cmd_start(["写口播稿", "25"])
        state = coach.load_state()
        self.assertIsNotNone(state)
        self.assertEqual(state["task"], "写口播稿")
        self.assertEqual(state["planned_minutes"], 25)

    def test_start_missing_args_exits(self):
        with self.assertRaises(SystemExit):
            coach.cmd_start([])

    def test_start_invalid_duration_exits(self):
        with self.assertRaises(SystemExit):
            coach.cmd_start(["任务", "abc"])

    @patch("coach.daemonize", return_value=False)
    @patch("coach.kill_existing_daemon")
    def test_start_blocks_when_task_active(self, mock_kill, mock_daemon):
        coach.cmd_start(["任务一", "10"])
        with self.assertRaises(SystemExit):
            coach.cmd_start(["任务二", "10"])


class TestCmdDone(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        coach.DATA_DIR = Path(self.tmp.name)
        coach.STATE_FILE = coach.DATA_DIR / "state.json"
        coach.HISTORY_FILE = coach.DATA_DIR / "history.jsonl"
        coach.PID_FILE = coach.DATA_DIR / "daemon.pid"

    def tearDown(self):
        self.tmp.cleanup()

    @patch("coach.notify")
    @patch("coach.kill_existing_daemon")
    def test_done_clears_state_and_writes_history(self, mock_kill, mock_notify):
        now = datetime.now()
        state = {
            "task": "完成任务",
            "planned_minutes": 25,
            "start_time": (now - timedelta(minutes=20)).isoformat(),
            "end_time": (now + timedelta(minutes=5)).isoformat(),
            "extensions": 0,
            "notes": []
        }
        coach.save_state(state)
        coach.cmd_done([])
        self.assertIsNone(coach.load_state())
        lines = coach.HISTORY_FILE.read_text().strip().split("\n")
        record = json.loads(lines[0])
        self.assertEqual(record["task"], "完成任务")
        self.assertEqual(record["status"], "done")

    def test_done_no_active_task(self, ):
        import io
        with patch("sys.stdout", new_callable=io.StringIO) as mock_out:
            coach.cmd_done([])
            self.assertIn("没有", mock_out.getvalue())


class TestCmdCancel(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        coach.DATA_DIR = Path(self.tmp.name)
        coach.STATE_FILE = coach.DATA_DIR / "state.json"
        coach.HISTORY_FILE = coach.DATA_DIR / "history.jsonl"
        coach.PID_FILE = coach.DATA_DIR / "daemon.pid"

    def tearDown(self):
        self.tmp.cleanup()

    @patch("coach.kill_existing_daemon")
    def test_cancel_writes_cancelled_status(self, mock_kill):
        now = datetime.now()
        state = {
            "task": "取消任务",
            "planned_minutes": 15,
            "start_time": (now - timedelta(minutes=5)).isoformat(),
            "end_time": (now + timedelta(minutes=10)).isoformat(),
            "extensions": 0,
            "notes": []
        }
        coach.save_state(state)
        coach.cmd_cancel([])
        self.assertIsNone(coach.load_state())
        record = json.loads(coach.HISTORY_FILE.read_text().strip())
        self.assertEqual(record["status"], "cancelled")


class TestCmdStatus(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        coach.DATA_DIR = Path(self.tmp.name)
        coach.STATE_FILE = coach.DATA_DIR / "state.json"
        coach.HISTORY_FILE = coach.DATA_DIR / "history.jsonl"
        coach.PID_FILE = coach.DATA_DIR / "daemon.pid"

    def tearDown(self):
        self.tmp.cleanup()

    def test_status_no_task(self):
        import io
        with patch("sys.stdout", new_callable=io.StringIO) as mock_out:
            coach.cmd_status([])
            self.assertIn("没有", mock_out.getvalue())

    def test_status_shows_task(self):
        import io
        now = datetime.now()
        state = {
            "task": "状态测试",
            "planned_minutes": 30,
            "start_time": (now - timedelta(minutes=10)).isoformat(),
            "end_time": (now + timedelta(minutes=20)).isoformat(),
            "extensions": 0,
            "notes": []
        }
        coach.save_state(state)
        with patch("sys.stdout", new_callable=io.StringIO) as mock_out:
            coach.cmd_status([])
            output = mock_out.getvalue()
            self.assertIn("状态测试", output)


if __name__ == "__main__":
    unittest.main()
