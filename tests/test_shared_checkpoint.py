"""Publisher-boundary refusal controls; Core/Store own the checkpoint schema."""
import copy
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
with mock.patch.object(sys, 'path', [str(ROOT / 'scripts'), *sys.path]):
    spec = importlib.util.spec_from_file_location('shared_checkpoint_launcher', ROOT / 'scripts/run_shared_opening.py')
    launcher = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(launcher)


class SharedCheckpointTests(unittest.TestCase):
    def fixture(self, root):
        # Opaque publisher-control bytes, not a pretend saved game or Model.
        slot = root / 'published-control'
        slot.write_bytes(b'publisher boundary control')
        report = {'persistence': {'accepted': True, 'save': {'accepted': True, 'reason': 'saved'},
                  'save_file': str(slot), 'saved_sha256': launcher.sha(slot), 'input_preserved': True}}
        return slot, report

    def test_report_success_cannot_mask_missing_or_changed_file(self):
        for mutation in ('missing', 'changed', 'pending'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                slot, report = self.fixture(Path(directory))
                launcher.verify_host_checkpoint(report, slot)
                if mutation == 'missing': slot.unlink()
                elif mutation == 'changed': slot.write_bytes(b'changed')
                else: Path(str(slot) + '.pending').write_bytes(b'owned collision sentinel')
                with self.assertRaisesRegex(ValueError, 'absent, pending, oversized or differs'):
                    launcher.verify_host_checkpoint(report, slot)

    def test_refused_numeric_or_misrouted_publication_never_becomes_success(self):
        for mutation in ('refused', 'numeric_overall', 'numeric_save', 'wrong_target', 'changed_input'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                slot, report = self.fixture(Path(directory))
                launcher.verify_host_checkpoint(report, slot)
                value = copy.deepcopy(report)
                persisted = value['persistence']
                if mutation == 'refused': persisted['save']['accepted'] = False
                elif mutation == 'numeric_overall': persisted['accepted'] = 1
                elif mutation == 'numeric_save': persisted['save']['accepted'] = 1
                elif mutation == 'wrong_target': persisted['save_file'] = str(slot.parent / 'another-target')
                else: persisted['input_preserved'] = False
                with self.assertRaisesRegex(ValueError, 'Host did not publish the requested checkpoint'):
                    launcher.verify_host_checkpoint(value, slot)

    def test_resume_requires_actual_immutable_captured_input(self):
        for mutation in ('bytes', 'reported_hash', 'path', 'refused'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                slot, report = self.fixture(root)
                incoming = root / 'incoming-control'
                incoming.write_bytes(b'owned immutable input control')
                captured = {'incoming': str(incoming), 'source_sha256': launcher.sha(incoming)}
                report['persistence'].update(resume={'accepted': True}, resume_input=str(incoming),
                                             input_sha256=captured['source_sha256'])
                launcher.verify_host_checkpoint(report, slot, captured)
                if mutation == 'bytes': incoming.write_bytes(b'changed input')
                elif mutation == 'reported_hash': report['persistence']['input_sha256'] = '0' * 64
                elif mutation == 'path': report['persistence']['resume_input'] = str(root / 'different-input')
                else: report['persistence']['resume']['accepted'] = False
                with self.assertRaisesRegex(ValueError, 'Host did not preserve the actual captured resume input'):
                    launcher.verify_host_checkpoint(report, slot, captured)


if __name__ == '__main__':
    unittest.main()
