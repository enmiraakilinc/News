import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('codex_bridge', Path(__file__).with_name('codex_bridge.py'))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class CodexBridgeTests(unittest.TestCase):
    def test_api_login_is_rejected_without_starting_job(self):
        with patch.object(bridge.subprocess, 'run', return_value=Mock(returncode=0, stdout='API key', stderr='')), patch.object(bridge.subprocess, 'Popen') as start:
            with self.assertRaises(RuntimeError):
                bridge.run_codex('task', Path('.'), 'codex.exe')
            start.assert_not_called()

    def test_scoped_chatgpt_execution_uses_stdin_and_filters_keys(self):
        process = Mock(returncode=0)
        process.poll.return_value = 0
        def start(arguments, **kwargs):
            if bridge.os.name == 'nt':
                self.assertEqual(kwargs['creationflags'], bridge.subprocess.CREATE_NO_WINDOW)
            self.assertNotIn('--dangerously-bypass-approvals-and-sandbox', arguments)
            self.assertIn('--approve-for-me', arguments)
            self.assertNotIn('private request', arguments)
            self.assertNotIn('OPENAI_API_KEY', kwargs['env'])
            self.assertNotIn('PC_SECRET', kwargs['env'])
            Path(arguments[arguments.index('--output-last-message') + 1]).write_text('Tamam', encoding='utf-8')
            return process
        with patch.dict(bridge.os.environ, {'OPENAI_API_KEY': 'private', 'PC_SECRET': 'private'}), patch.object(bridge.subprocess, 'run', return_value=Mock(returncode=0, stdout='Logged in using ChatGPT', stderr='')), patch.object(bridge.subprocess, 'Popen', side_effect=start):
            self.assertEqual(bridge.run_codex('private request', Path('.'), 'codex.exe')['text'], 'Tamam')
            self.assertIn(b'private request', process.stdin.write.call_args.args[0])


if __name__ == '__main__':
    unittest.main()
