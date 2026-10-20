import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('pc_agent', Path(__file__).with_name('pc_agent.py'))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


class AgentTests(unittest.TestCase):
    def test_paths_stay_inside_registered_project(self):
        with tempfile.TemporaryDirectory(prefix='telegram_agent_test_') as directory:
            root = Path(directory)
            self.assertEqual(agent.inside(root, 'logs/test.log'), root / 'logs/test.log')
            with self.assertRaises(ValueError):
                agent.inside(root, '../outside.log')
            with self.assertRaises(ValueError):
                agent.inside(root, str(root.resolve()))

    def test_python_is_disabled_by_default_and_bridge_secret_not_in_child_environment(self):
        with tempfile.TemporaryDirectory(prefix='telegram_agent_test_') as directory:
            job = {'kind': 'python', 'payload': {'code': 'print("hello")'}}
            with patch.object(agent, 'run_process') as run:
                self.assertIn('kapalı', agent.execute(job, Path(directory))['text'])
                run.assert_not_called()
            with patch.dict(agent.os.environ, {'PC_SECRET': 'private-bridge-secret'}):
                result = agent.run_process([agent.sys.executable, '-I', '-c', 'import os; print(os.environ.get("PC_SECRET", "absent"))'], Path(directory))
                self.assertIn('absent', result)
                self.assertNotIn('private-bridge-secret', result)

    def test_pending_result_retries_delivery_without_executing_twice(self):
        with tempfile.TemporaryDirectory(prefix='telegram_agent_test_') as directory:
            root = Path(directory)
            journal = {}
            class Bridge:
                secret = 'private-key'
                count = 0
                def post(self, path, data):
                    self.count += 1
                    if self.count == 1:
                        raise RuntimeError('connection lost')
                    return {'accepted': True}
            bridge = Bridge()
            job = {'id': 'pc1', 'lease': 'l1', 'kind': 'python', 'payload': {'code': 'print(1)'}}
            with patch.object(agent, 'execute', return_value={'text': 'result'}) as execute:
                with self.assertRaises(RuntimeError):
                    agent.handle_job(bridge, 'p1', root, job, journal, root/'journal.json', True, {})
                agent.handle_job(bridge, 'p1', root, job, journal, root/'journal.json', True, {})
                self.assertEqual(execute.call_count, 1)
            self.assertEqual(journal['p1:pc1'], {'state': 'done'})
            self.assertNotIn('result', (root/'journal.json').read_text())

    def test_uncertain_started_job_is_not_rerun(self):
        with tempfile.TemporaryDirectory(prefix='telegram_agent_test_') as directory:
            root = Path(directory)
            class Bridge:
                secret = 'secret'
                def post(self, path, data):
                    self.data = data
                    return {'accepted': True}
            bridge = Bridge()
            journal = {'p1:pc1': {'state': 'started'}}
            job = {'id': 'pc1', 'lease': 'l2', 'kind': 'gitpull', 'payload': {}}
            with patch.object(agent, 'execute') as execute:
                agent.handle_job(bridge, 'p1', root, job, journal, root/'journal.json', False, {})
                execute.assert_not_called()
            self.assertIn('belirsiz', bridge.data['text'])

    def test_python_watch_checks_syntax_without_running_file(self):
        with tempfile.TemporaryDirectory(prefix='telegram_agent_test_') as directory:
            root = Path(directory)
            source = root/'example.py'
            source.write_text('raise RuntimeError("must not execute")', encoding='utf-8')
            watcher = {}
            agent.execute({'kind': 'watch', 'payload': {'path': 'example.py'}}, root, watch=watcher)
            self.assertIn('çalışma zamanı testi yapılmadı', agent.watch_error(root, watcher))
            self.assertIsNone(agent.watch_error(root, watcher))


if __name__ == '__main__':
    unittest.main()
