"""Source-package closure controls; no simulated character or game acceptance."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('physical_authority_runner', ROOT / 'scripts/check_physical_build.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class PhysicalBuildPackageTests(unittest.TestCase):
    def test_actual_minimal_model_manifest_requires_its_geometry_dependency(self):
        actual = runner.source_inputs()
        self.assertIn('opening/site_geometry.gd', actual)
        omitted = tuple(name for name in runner.FILES if name != 'opening/site_geometry.gd')
        with self.assertRaisesRegex(ValueError, r'Missing copied dependency: opening/site_geometry.gd \(from model.gd\)'):
            runner.source_inputs(files=omitted)

    def test_dependency_source_alias_is_refused_before_any_engine(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            for name, data in runner.source_inputs().items():
                target = project / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            geometry = project / 'opening/site_geometry.gd'
            geometry.unlink()
            geometry.symlink_to(runner.PROJECT / 'opening/site_geometry.gd')
            with self.assertRaisesRegex(ValueError, 'Missing regular source input: opening/site_geometry.gd'):
                runner.source_inputs(project=project)


if __name__ == '__main__':
    unittest.main()
