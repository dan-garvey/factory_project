import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location("factory_pm", Path(__file__).resolve().parents[1] / "scripts/pm.py")
pm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pm)


class PMTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="factory pm ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.directory = self.root / "runtime"
        self.directory.mkdir()
        self.thread = "01a13bb6-ca3f-71d2-ace8-305484081ed5"
        pm.write_json(self.directory / "pm-config.json", {"thread": self.thread, "codex": "/fake/codex", "root": str(self.root)})
        self.manager = pm.Manager(self.root, self.directory)
        self.manager.snapshot = lambda: {"refs": ["refs/heads/main abc123"], "free_disk_bytes": 123}
        self.queue = mock.Mock(return_value=subprocess.CompletedProcess([], 0, "Queued fixture receipt", ""))

    def test_explicit_thread_and_pending_requests_coalesce(self):
        first = self.manager.poll(queue=self.queue)
        second = self.manager.poll(queue=self.queue)
        self.assertEqual(self.queue.call_count, 1)
        self.assertTrue(second["coalesced"])
        self.assertEqual(first["queued"]["id"], second["pending"]["id"])
        self.assertIn(self.thread, self.queue.call_args.args[0])
        state = pm.read_json(self.manager.state_path)
        self.assertNotIn("last_completed", state)

    def test_dry_run_does_not_write_or_queue(self):
        result = self.manager.poll(dry_run=True, queue=self.queue)
        self.assertTrue(result["dry_run"])
        self.assertFalse(self.manager.state_path.exists())
        self.queue.assert_not_called()

    def test_prelaunch_failure_is_not_review_completion_and_can_retry(self):
        self.queue.side_effect = FileNotFoundError("missing executable")
        with self.assertRaises(FileNotFoundError):
            self.manager.poll(queue=self.queue)
        state = pm.read_json(self.manager.state_path)
        self.assertIsNone(state["pending"])
        self.assertNotIn("last_completed", state)
        self.queue.side_effect = None
        self.manager.poll(queue=self.queue)
        self.assertEqual(self.queue.call_count, 2)

    def test_nonzero_after_admission_is_not_automatically_duplicated(self):
        self.queue.side_effect = subprocess.CalledProcessError(1, ["codex"], output="Queued before failure")
        with self.assertRaises(subprocess.CalledProcessError):
            self.manager.poll(queue=self.queue)
        result = self.manager.poll(queue=self.queue)
        self.assertTrue(result["coalesced"])
        self.assertEqual(result["pending"]["status"], "delivery_unknown")
        self.assertEqual(self.queue.call_count, 1)

    def test_unknown_delivery_is_not_automatically_duplicated(self):
        self.queue.side_effect = subprocess.TimeoutExpired(["codex"], 30)
        with self.assertRaises(subprocess.TimeoutExpired):
            self.manager.poll(queue=self.queue)
        result = self.manager.poll(queue=self.queue)
        self.assertTrue(result["coalesced"])
        self.assertEqual(result["pending"]["status"], "delivery_unknown")
        self.assertEqual(self.queue.call_count, 1)

    def test_acknowledgement_requires_exact_request_and_keeps_requested_refs(self):
        request = self.manager.poll(queue=self.queue)["queued"]
        self.manager.snapshot = lambda: {"refs": ["refs/heads/main NOT_REVIEWED"], "free_disk_bytes": 123}
        with self.assertRaises(ValueError):
            self.manager.acknowledge("wrong-id", "must not clear")
        result = self.manager.acknowledge(request["id"], "Bead records exact reviewed SHAs")
        self.assertEqual(result["refs"], ["refs/heads/main abc123"])
        self.assertIsNone(pm.read_json(self.manager.state_path)["pending"])

    def test_cancelling_a_stale_request_does_not_claim_review_completion(self):
        request = self.manager.poll(queue=self.queue)["queued"]
        with self.assertRaises(ValueError):
            self.manager.cancel("wrong-id", "not the request")
        self.manager.cancel(request["id"], "inspected thread; request not delivered")
        state = pm.read_json(self.manager.state_path)
        self.assertIsNone(state["pending"])
        self.assertNotIn("last_completed", state)
        self.assertEqual(state["last_cancelled"]["reason"], "inspected thread; request not delivered")

    def test_install_refuses_foreign_unit_before_changing_config(self):
        units = self.root / "units"
        units.mkdir()
        (units / "factory-pm.timer").write_text("unrelated timer")
        codex = self.root / "codex"
        codex.touch()
        directory = self.root / "new runtime"
        with self.assertRaises(ValueError):
            pm.install(self.root, directory, self.thread, codex, units)
        self.assertEqual((units / "factory-pm.timer").read_text(), "unrelated timer")
        self.assertFalse((directory / "pm-config.json").exists())

    def test_install_is_repeatable_and_uses_directive_specific_paths(self):
        codex = self.root / "codex"
        codex.touch()
        units = self.root / "units"
        directory = self.root / "new runtime"
        pm.install(self.root, directory, self.thread, codex, units)
        pm.install(self.root, directory, self.thread, codex, units)
        service = (units / "factory-pm.service").read_text()
        self.assertIn(f'WorkingDirectory={self.root}', service)
        self.assertIn("Persistent=true", (units / "factory-pm.timer").read_text())
        self.assertEqual(pm.read_json(directory / "pm-config.json")["thread"], self.thread)

    def test_install_refuses_dangling_unit_symlinks_without_writing_target(self):
        codex = self.root / "codex"
        codex.touch()
        units = self.root / "units"
        units.mkdir()
        foreign = self.root / "foreign.service"
        (units / "factory-pm.service").symlink_to(foreign)
        directory = self.root / "new runtime"
        with self.assertRaises(ValueError):
            pm.install(self.root, directory, self.thread, codex, units)
        self.assertFalse(foreign.exists())
        self.assertTrue((units / "factory-pm.service").is_symlink())
        self.assertFalse((directory / "pm-config.json").exists())

    def test_unit_quoting_distinguishes_exec_expansion_from_working_directory(self):
        self.assertEqual(pm.quote_unit("/project/${HOME}", command=True), '"/project/$${HOME}"')
        self.assertEqual(pm.quote_unit("/project/${HOME}"), '"/project/${HOME}"')

    def test_install_keeps_stable_launcher_symlink(self):
        target = self.root / "versioned-codex"
        target.touch()
        launcher = self.root / "stable-codex"
        launcher.symlink_to(target)
        directory = self.root / "new runtime"
        pm.install(self.root, directory, self.thread, launcher, self.root / "units")
        self.assertEqual(pm.read_json(directory / "pm-config.json")["codex"], str(launcher))

    def test_generated_units_pass_the_actual_systemd_parser(self):
        # verify parses units only: no daemon-reload/start or real queue call.
        root = self.root / "special ${HOME} % path"
        root.mkdir()
        codex = root / "codex"
        codex.touch()
        units = root / "units"
        pm.install(root, root / "runtime", self.thread, codex, units)
        result = subprocess.run(["systemd-analyze", "verify", str(units / "factory-pm.service"),
                                 str(units / "factory-pm.timer")], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
