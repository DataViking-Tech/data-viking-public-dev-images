"""
Godot Render Bridge - GPU-accelerated Godot rendering via Windows host.

Similar to the Blender render bridge, this enables GPU rendering by offloading
Godot SubViewport renders to a Windows host with actual GPU access.

Usage:
    from godot_render_bridge import GodotRenderBridge

    bridge = GodotRenderBridge()

    # Render a biome showcase
    result = bridge.render_biome_showcase(
        biome="my_biome",
        camera="front",
        distance=48,
        density="medium"
    )
    print(f"Output: {result.output_file}")
    print(f"Render time: {result.render_time_seconds}s")
"""

import json
import os
import time
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Optional, Literal


# Project paths
PYTHON_DIR = Path(__file__).parent
DEFAULT_BASE_DIR = PYTHON_DIR.parent
RENDER_BRIDGE_BASE_ENV = "RENDER_BRIDGE_BASE"


def _resolve_base_dir(base_dir: Optional[Path]) -> Path:
    if base_dir is not None:
        return Path(base_dir)
    env_base = os.environ.get(RENDER_BRIDGE_BASE_ENV)
    if env_base:
        return Path(env_base)
    return DEFAULT_BASE_DIR


def _queue_dir_for(base_dir: Path) -> Path:
    return base_dir / "temp" / "godot-render-queue"


def _output_dir_for(base_dir: Path) -> Path:
    return base_dir / "temp" / "godot-render-output"


@dataclass
class GodotRenderJob:
    """Configuration for a Godot render job."""
    job_id: str
    job_type: Literal["biome_showcase", "single_asset", "animation_capture"]
    created_at: str
    params: dict = field(default_factory=dict)

    @classmethod
    def biome_showcase(
        cls,
        biome: str,
        camera: str = "front",
        distance: float = 48,
        density: str = "medium",
        seed: int = 42,
        include_player: bool = False,
        include_flora: bool = False,
        dusk_lighting: bool = False,
        render_mode: str = "normal",
        hero_player: bool = False,
        hero_enemy: str = "",
        output_width: int = 1024,
        output_height: int = 768,
    ) -> "GodotRenderJob":
        """Create a biome showcase render job."""
        return cls(
            job_id=str(uuid.uuid4())[:8],
            job_type="biome_showcase",
            created_at=datetime.utcnow().isoformat() + "Z",
            params={
                "biome": biome,
                "camera": camera,
                "distance": distance,
                "density": density,
                "seed": seed,
                "include_player": include_player,
                "include_flora": include_flora,
                "dusk_lighting": dusk_lighting,
                "render_mode": render_mode,
                "hero_player": hero_player,
                "hero_enemy": hero_enemy,
                "output_width": output_width,
                "output_height": output_height,
            }
        )

    @classmethod
    def single_asset(
        cls,
        asset_path: str,
        biome: str,
        camera: str = "front_34_elevated",
        distance: float = 24,
        terrain_mode: str = "flat",
        render_mode: str = "normal",
        output_width: int = 512,
        output_height: int = 512,
    ) -> "GodotRenderJob":
        """Create a single asset render job."""
        return cls(
            job_id=str(uuid.uuid4())[:8],
            job_type="single_asset",
            created_at=datetime.utcnow().isoformat() + "Z",
            params={
                "asset_path": asset_path,
                "biome": biome,
                "camera": camera,
                "distance": distance,
                "terrain_mode": terrain_mode,
                "render_mode": render_mode,
                "output_width": output_width,
                "output_height": output_height,
            }
        )

    @classmethod
    def animation_capture(
        cls,
        asset_path: str,
        animation_name: str,
        fps: int = 24,
        output_width: int = 512,
        output_height: int = 512,
        camera: str = "front_34_elevated",
    ) -> "GodotRenderJob":
        """Create an animation capture job.

        Captures frames from a GLB animation for GIF/contact sheet generation.
        """
        return cls(
            job_id=str(uuid.uuid4())[:8],
            job_type="animation_capture",
            created_at=datetime.utcnow().isoformat() + "Z",
            params={
                "asset_path": asset_path,
                "animation_name": animation_name,
                "fps": fps,
                "output_width": output_width,
                "output_height": output_height,
                "camera": camera,
            }
        )


@dataclass
class GodotRenderResult:
    """Result of a Godot render job."""
    job_id: str
    status: Literal["success", "error", "timeout"]
    output_file: Optional[Path] = None
    render_time_seconds: float = 0.0
    gpu_name: Optional[str] = None
    error: Optional[str] = None


class GodotRenderBridge:
    """Bridge for GPU-accelerated Godot rendering on Windows host."""

    def __init__(
        self,
        timeout: float = 120.0,
        poll_interval: float = 0.5,
        base_dir: Optional[Path] = None,
        queue_dir: Optional[Path] = None,
        output_dir: Optional[Path] = None,
    ):
        """
        Initialize the Godot render bridge.

        Args:
            timeout: Maximum seconds to wait for a render job
            poll_interval: Seconds between checking for results
            base_dir: Optional base directory for queue/output
            queue_dir: Optional override for queue directory
            output_dir: Optional override for output directory
        """
        self.timeout = timeout
        self.poll_interval = poll_interval

        # Ensure directories exist
        resolved_base = _resolve_base_dir(base_dir)
        self.base_dir = resolved_base
        self.queue_dir = Path(queue_dir) if queue_dir else _queue_dir_for(resolved_base)
        self.output_dir = Path(output_dir) if output_dir else _output_dir_for(resolved_base)

        self.queue_dir.mkdir(parents=True, exist_ok=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def submit_job(self, job: GodotRenderJob) -> str:
        """
        Submit a render job to the queue.

        Returns:
            job_id for tracking
        """
        job_file = self.queue_dir / f"{job.job_id}.json"
        with open(job_file, "w") as f:
            json.dump(asdict(job), f, indent=2)
        return job.job_id

    def is_complete(self, job_id: str) -> bool:
        """Check if a job has completed (success or failure)."""
        result_file = self.output_dir / f"{job_id}_result.json"
        return result_file.exists()

    def get_result(self, job_id: str) -> Optional[GodotRenderResult]:
        """
        Get the result of a completed job without waiting.

        Returns None if job is not yet complete.
        """
        result_file = self.output_dir / f"{job_id}_result.json"
        output_file = self.output_dir / f"{job_id}.png"

        if not result_file.exists():
            return None

        try:
            with open(result_file) as f:
                data = json.load(f)

            if data.get("status") == "success" and output_file.exists():
                return GodotRenderResult(
                    job_id=job_id,
                    status="success",
                    output_file=output_file,
                    render_time_seconds=data.get("render_time_seconds", 0),
                    gpu_name=data.get("gpu_name"),
                )
            else:
                return GodotRenderResult(
                    job_id=job_id,
                    status="error",
                    error=data.get("error", "Unknown error"),
                )
        except json.JSONDecodeError:
            # File may be partially written
            return None

    def wait_for_result(self, job_id: str, timeout: Optional[float] = None) -> GodotRenderResult:
        """
        Wait for a render job to complete.

        Args:
            job_id: The job ID to wait for
            timeout: Override default timeout

        Returns:
            GodotRenderResult with output path or error
        """
        timeout = timeout or self.timeout
        start_time = time.time()

        while time.time() - start_time < timeout:
            result = self.get_result(job_id)
            if result is not None:
                return result
            time.sleep(self.poll_interval)

        return GodotRenderResult(
            job_id=job_id,
            status="timeout",
            error=f"Render timed out after {timeout}s",
        )

    def render_biome_showcase(
        self,
        biome: str,
        camera: str = "front",
        distance: float = 48,
        density: str = "medium",
        seed: int = 42,
        include_player: bool = False,
        include_flora: bool = False,
        dusk_lighting: bool = False,
        render_mode: str = "normal",
        hero_player: bool = False,
        hero_enemy: str = "",
        output_width: int = 1024,
        output_height: int = 768,
    ) -> GodotRenderResult:
        """
        Render a biome showcase scene with GPU acceleration.

        Args:
            biome: Biome identifier (any string accepted by the project)
            camera: Camera preset (e.g. front, side, overhead, low, wide, closeup)
            distance: Camera distance in units
            density: Asset density (e.g. sparse, medium, dense, extreme)
            seed: Random seed for reproducibility
            include_player: Add player model for scale reference
            include_flora: Add flora assets for environmental context
            dusk_lighting: Enable dusk lighting for emission evaluation
            render_mode: Rendering mode (e.g. normal, clay, matcap)
            hero_player: Spawn player as centered hero subject
            hero_enemy: Enemy type to spawn as centered hero subject
            output_width: Output image width
            output_height: Output image height

        Returns:
            GodotRenderResult with output path
        """
        job_id = self.submit_biome_showcase(
            biome=biome,
            camera=camera,
            distance=distance,
            density=density,
            seed=seed,
            include_player=include_player,
            include_flora=include_flora,
            dusk_lighting=dusk_lighting,
            render_mode=render_mode,
            hero_player=hero_player,
            hero_enemy=hero_enemy,
            output_width=output_width,
            output_height=output_height,
        )
        return self.wait_for_result(job_id)

    def submit_biome_showcase(
        self,
        biome: str,
        camera: str = "front",
        distance: float = 48,
        density: str = "medium",
        seed: int = 42,
        include_player: bool = False,
        include_flora: bool = False,
        dusk_lighting: bool = False,
        render_mode: str = "normal",
        hero_player: bool = False,
        hero_enemy: str = "",
        output_width: int = 1024,
        output_height: int = 768,
    ) -> str:
        """
        Submit a biome showcase render job without waiting.

        Returns:
            job_id for tracking with is_complete()/get_result()
        """
        job = GodotRenderJob.biome_showcase(
            biome=biome,
            camera=camera,
            distance=distance,
            density=density,
            seed=seed,
            include_player=include_player,
            include_flora=include_flora,
            dusk_lighting=dusk_lighting,
            render_mode=render_mode,
            hero_player=hero_player,
            hero_enemy=hero_enemy,
            output_width=output_width,
            output_height=output_height,
        )
        self.submit_job(job)
        return job.job_id

    def render_single_asset(
        self,
        asset_path: str,
        biome: str,
        camera: str = "front_34_elevated",
        distance: float = 24,
        terrain_mode: str = "flat",
        render_mode: str = "normal",
        output_width: int = 512,
        output_height: int = 512,
    ) -> GodotRenderResult:
        """
        Render a single asset with GPU acceleration.

        Args:
            asset_path: Path to asset (e.g., res://assets/blender/...)
            biome: Biome for lighting/ground colors (any string)
            camera: Camera preset (e.g. front_34_elevated)
            distance: Camera distance in units
            terrain_mode: Terrain style (e.g. flat, procedural, slope)
            render_mode: Rendering mode (e.g. normal, clay, matcap)
            output_width: Output image width
            output_height: Output image height

        Returns:
            GodotRenderResult with output path
        """
        job_id = self.submit_single_asset(
            asset_path=asset_path,
            biome=biome,
            camera=camera,
            distance=distance,
            terrain_mode=terrain_mode,
            render_mode=render_mode,
            output_width=output_width,
            output_height=output_height,
        )
        return self.wait_for_result(job_id)

    def submit_single_asset(
        self,
        asset_path: str,
        biome: str,
        camera: str = "front_34_elevated",
        distance: float = 24,
        terrain_mode: str = "flat",
        render_mode: str = "normal",
        output_width: int = 512,
        output_height: int = 512,
    ) -> str:
        """
        Submit a single asset render job without waiting.

        Returns:
            job_id for tracking with is_complete()/get_result()
        """
        job = GodotRenderJob.single_asset(
            asset_path=asset_path,
            biome=biome,
            camera=camera,
            distance=distance,
            terrain_mode=terrain_mode,
            render_mode=render_mode,
            output_width=output_width,
            output_height=output_height,
        )
        self.submit_job(job)
        return job.job_id

    def is_watcher_running(self) -> bool:
        """Check if the Windows watcher appears to be running."""
        heartbeat = self.base_dir / "temp" / "godot-watcher-heartbeat"
        if heartbeat.exists():
            age = time.time() - heartbeat.stat().st_mtime
            return age < 10  # Heartbeat within last 10 seconds
        return False

    def cleanup_job(self, job_id: str) -> None:
        """Remove job files after processing."""
        for pattern in [f"{job_id}.json", f"{job_id}_result.json", f"{job_id}.png"]:
            for directory in [self.queue_dir, self.output_dir]:
                file = directory / pattern
                if file.exists():
                    file.unlink()

    def list_pending_jobs(self) -> list[str]:
        """List job IDs in the queue."""
        return [f.stem for f in self.queue_dir.glob("*.json")]

    def list_completed_jobs(self) -> list[str]:
        """List completed job IDs."""
        return [f.stem.replace("_result", "") for f in self.output_dir.glob("*_result.json")]


# CLI for testing
if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Test Godot Render Bridge")
    parser.add_argument("--biome", default="default", help="Biome to render")
    parser.add_argument("--camera", default="front", help="Camera preset")
    parser.add_argument("--distance", type=float, default=48, help="Camera distance")
    parser.add_argument("--check", action="store_true", help="Check if watcher is running")

    args = parser.parse_args()

    bridge = GodotRenderBridge()

    if args.check:
        if bridge.is_watcher_running():
            print("✓ Godot render watcher is running")
        else:
            print("✗ Godot render watcher not detected")
            print("  Start it on Windows: .\\temp\\godot_render_watcher.ps1")
        exit(0)

    print(f"Submitting biome showcase job: {args.biome}")
    result = bridge.render_biome_showcase(
        biome=args.biome,
        camera=args.camera,
        distance=args.distance,
    )

    if result.status == "success":
        print(f"✓ Success: {result.output_file}")
        print(f"  Render time: {result.render_time_seconds:.2f}s")
        print(f"  GPU: {result.gpu_name}")
    else:
        print(f"✗ {result.status}: {result.error}")
