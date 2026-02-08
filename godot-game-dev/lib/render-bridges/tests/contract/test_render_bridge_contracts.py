import json
import os
import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from render_bridge.job import RenderJob, RenderResult, JobStatus
import render_bridge.bridge as bridge_module
import godot_render_bridge as godot_bridge

class RenderBridgeContractTests(unittest.TestCase):
    def test_render_job_schema(self):
        job = RenderJob(
            blend_file="/tmp/test.blend",
            job_id="job123",
            render_engine="BLENDER_EEVEE",
            output_format="glb",
            script="/tmp/script.py",
            script_args=["--flag"],
            generate_previews=True,
            preview_angles=["front"],
            preview_resolution=128,
            generate_contact_sheet=True,
            render_animation=True,
            frame_start=1,
            frame_end=2,
            action_name="Walk",
            animation_angles=["front"],
        )

        data = json.loads(job.to_json())
        expected_keys = {
            "blend_file",
            "job_id",
            "render_engine",
            "output_format",
            "script",
            "script_args",
            "generate_previews",
            "preview_angles",
            "preview_resolution",
            "generate_contact_sheet",
            "render_animation",
            "frame_start",
            "frame_end",
            "action_name",
            "animation_angles",
        }
        self.assertTrue(expected_keys.issubset(data.keys()))

        loaded = RenderJob.from_json(job.to_json())
        self.assertEqual(loaded.job_id, "job123")

    def test_render_result_schema(self):
        result = RenderResult(
            job_id="job123",
            status=JobStatus.COMPLETE.value,
            output_files=["/tmp/output.glb"],
            preview_files=["/tmp/preview.png"],
            render_time_seconds=1.25,
            error_message=None,
            error_traceback=None,
            blender_version="4.0",
            gpu_used="TestGPU",
        )

        data = json.loads(result.to_json())
        expected_keys = {
            "job_id",
            "status",
            "output_files",
            "preview_files",
            "render_time_seconds",
            "error_message",
            "error_traceback",
            "blender_version",
            "gpu_used",
        }
        self.assertTrue(expected_keys.issubset(data.keys()))

        loaded = RenderResult.from_json(result.to_json())
        self.assertTrue(loaded.success)

    def test_render_bridge_paths_and_override(self):
        original_env = os.environ.get("RENDER_BRIDGE_BASE")
        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                base = Path(temp_dir)
                os.environ["RENDER_BRIDGE_BASE"] = str(base)

                bridge = bridge_module.RenderBridge()
                self.assertEqual(bridge.queue_dir, base / "temp" / "render-queue")
                self.assertEqual(bridge.output_dir, base / "temp" / "render-output")
        finally:
            if original_env is None:
                os.environ.pop("RENDER_BRIDGE_BASE", None)
            else:
                os.environ["RENDER_BRIDGE_BASE"] = original_env

    def test_godot_bridge_paths_and_override(self):
        original_env = os.environ.get("RENDER_BRIDGE_BASE")
        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                base = Path(temp_dir)
                os.environ["RENDER_BRIDGE_BASE"] = str(base)

                bridge = godot_bridge.GodotRenderBridge(timeout=0.1, poll_interval=0.01)
                self.assertEqual(bridge.queue_dir, base / "temp" / "godot-render-queue")
                self.assertEqual(bridge.output_dir, base / "temp" / "godot-render-output")
        finally:
            if original_env is None:
                os.environ.pop("RENDER_BRIDGE_BASE", None)
            else:
                os.environ["RENDER_BRIDGE_BASE"] = original_env

    def test_godot_bridge_accepts_any_biome_string(self):
        """Verify biome parameter accepts arbitrary strings without validation."""
        job = godot_bridge.GodotRenderJob.biome_showcase(biome="custom_biome_name")
        self.assertEqual(job.params["biome"], "custom_biome_name")
        self.assertEqual(job.job_type, "biome_showcase")

    def test_godot_bridge_accepts_any_render_params(self):
        """Verify camera/density/terrain/render_mode accept arbitrary strings."""
        job = godot_bridge.GodotRenderJob.biome_showcase(
            biome="test",
            camera="custom_angle",
            density="custom_density",
            render_mode="custom_mode",
        )
        self.assertEqual(job.params["camera"], "custom_angle")
        self.assertEqual(job.params["density"], "custom_density")
        self.assertEqual(job.params["render_mode"], "custom_mode")

        job2 = godot_bridge.GodotRenderJob.single_asset(
            asset_path="res://test.glb",
            biome="test",
            terrain_mode="custom_terrain",
            render_mode="custom_render",
        )
        self.assertEqual(job2.params["terrain_mode"], "custom_terrain")
        self.assertEqual(job2.params["render_mode"], "custom_render")

    def test_godot_bridge_cleanup_uses_instance_dirs(self):
        """Verify cleanup_job uses instance queue/output dirs, not module globals."""
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            bridge = godot_bridge.GodotRenderBridge(
                timeout=0.1, poll_interval=0.01, base_dir=base
            )
            # Create a fake job file
            job_file = bridge.queue_dir / "testjob.json"
            job_file.write_text("{}")
            self.assertTrue(job_file.exists())
            bridge.cleanup_job("testjob")
            self.assertFalse(job_file.exists())


if __name__ == "__main__":
    unittest.main()
