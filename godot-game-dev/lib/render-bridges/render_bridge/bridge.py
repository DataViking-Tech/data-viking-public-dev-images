"""
RenderBridge - Submit and await render jobs from the Linux container.
"""

import os
import re
import json
import time
import shutil
from pathlib import Path
from typing import Optional, List, Union, Dict, Any

from .job import RenderJob, RenderResult, JobStatus
from .diagnostics import DIAGNOSTIC_SCRIPT


# Paths that work in both container and Windows
# Container sees: <base_dir>/temp/render-queue/
# Windows sees: .\temp\render-queue\ (via bind mount)
DEFAULT_BASE_DIR = Path(__file__).resolve().parents[2]
RENDER_BRIDGE_BASE_ENV = "RENDER_BRIDGE_BASE"


def _resolve_base_dir(base_dir: Optional[Path]) -> Path:
    if base_dir is not None:
        return Path(base_dir)
    env_base = os.environ.get(RENDER_BRIDGE_BASE_ENV)
    if env_base:
        return Path(env_base)
    return DEFAULT_BASE_DIR


def _queue_dir_for(base_dir: Path) -> Path:
    return base_dir / "temp" / "render-queue"


def _output_dir_for(base_dir: Path) -> Path:
    return base_dir / "temp" / "render-output"


QUEUE_DIR = _queue_dir_for(DEFAULT_BASE_DIR)
OUTPUT_DIR = _output_dir_for(DEFAULT_BASE_DIR)


class RenderBridge:
    """Bridge for submitting render jobs to the Windows host."""
    
    def __init__(
        self,
        base_dir: Optional[Path] = None,
        queue_dir: Optional[Path] = None,
        output_dir: Optional[Path] = None,
        timeout: float = 300.0,
        poll_interval: float = 1.0
    ):
        resolved_base = _resolve_base_dir(base_dir)
        self.queue_dir = Path(queue_dir) if queue_dir else _queue_dir_for(resolved_base)
        self.output_dir = Path(output_dir) if output_dir else _output_dir_for(resolved_base)
        self.timeout = timeout
        self.poll_interval = poll_interval
        
        # Ensure directories exist
        self.queue_dir.mkdir(parents=True, exist_ok=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)
    
    def submit_job(self, job: RenderJob) -> str:
        """Submit a render job to the queue.
        
        Returns:
            The job ID for tracking.
        """
        job_file = self.queue_dir / f"{job.job_id}.json"
        job.save(job_file)
        print(f"[RenderBridge] Submitted job {job.job_id}")
        return job.job_id
    
    def is_complete(self, job_id: str) -> bool:
        """Check if a job has completed (success or failure)."""
        result_file = self.output_dir / f"{job_id}.result.json"
        return result_file.exists()
    
    def get_result(self, job_id: str, max_retries: int = 5, retry_delay: float = 0.2) -> Optional[RenderResult]:
        """Get the result of a completed job.

        Handles race condition where file exists but isn't fully written yet.
        """
        result_file = self.output_dir / f"{job_id}.result.json"
        if not result_file.exists():
            return None

        # Retry loop to handle race condition with file writing
        for attempt in range(max_retries):
            try:
                # Check file has content
                if result_file.stat().st_size == 0:
                    if attempt < max_retries - 1:
                        time.sleep(retry_delay)
                        continue
                    return None

                content = result_file.read_text(encoding='utf-8-sig')
                if not content.strip():
                    if attempt < max_retries - 1:
                        time.sleep(retry_delay)
                        continue
                    return None

                return RenderResult.from_json(content)
            except json.JSONDecodeError:
                # File may be partially written
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
                # Final attempt failed - log and return None
                print(f"[RenderBridge] Warning: Could not parse result for {job_id} after {max_retries} attempts")
                return None
            except Exception as e:
                print(f"[RenderBridge] Error reading result for {job_id}: {e}")
                return None

        return None
    
    def wait_for_result(self, job_id: str, timeout: Optional[float] = None) -> RenderResult:
        """Wait for a job to complete and return the result.
        
        Raises:
            TimeoutError: If the job doesn't complete within the timeout.
            RuntimeError: If the job failed.
        """
        timeout = timeout or self.timeout
        start = time.time()
        
        while True:
            if self.is_complete(job_id):
                result = self.get_result(job_id)
                if result and result.status == JobStatus.FAILED.value:
                    raise RuntimeError(f"Render job {job_id} failed: {result.error_message}")
                return result
            
            elapsed = time.time() - start
            if elapsed > timeout:
                raise TimeoutError(f"Render job {job_id} timed out after {timeout}s")
            
            time.sleep(self.poll_interval)
    
    def render_blend(
        self,
        blend_file: str,
        output_format: str = "glb",
        render_engine: str = "BLENDER_EEVEE_NEXT",
        generate_previews: bool = False,
        timeout: Optional[float] = None,
        **kwargs
    ) -> RenderResult:
        """Convenience method to render a .blend file and wait for result.
        
        Args:
            blend_file: Path to the .blend file
            output_format: "glb", "png", or "blend"
            render_engine: "BLENDER_EEVEE", "CYCLES", or "BLENDER_WORKBENCH"
            generate_previews: Whether to generate preview images
            timeout: Max seconds to wait (default: self.timeout)
            **kwargs: Additional RenderJob parameters
            
        Returns:
            RenderResult with output file paths
        """
        job = RenderJob(
            blend_file=blend_file,
            output_format=output_format,
            render_engine=render_engine,
            generate_previews=generate_previews,
            **kwargs
        )
        
        self.submit_job(job)
        return self.wait_for_result(job.job_id, timeout)
    
    def render_with_script(
        self,
        blend_file: str,
        script: str,
        script_args: Optional[List[str]] = None,
        timeout: Optional[float] = None
    ) -> RenderResult:
        """Run a custom Blender Python script on a .blend file.
        
        Args:
            blend_file: Path to the .blend file
            script: Path to the Python script to run
            script_args: Arguments to pass to the script
            timeout: Max seconds to wait
            
        Returns:
            RenderResult with output file paths
        """
        job = RenderJob(
            blend_file=blend_file,
            script=script,
            script_args=script_args or []
        )
        
        self.submit_job(job)
        return self.wait_for_result(job.job_id, timeout)

    def render_animation(
        self,
        blend_file: str,
        action_name: Optional[str] = None,
        frame_start: Optional[int] = None,
        frame_end: Optional[int] = None,
        render_engine: str = "BLENDER_EEVEE",
        resolution: int = 256,
        timeout: Optional[float] = None
    ) -> RenderResult:
        """Render an animation sequence from a .blend file.

        Args:
            blend_file: Path to the .blend file
            action_name: Name of action to play (e.g., "Walk", "Idle"). If None, uses active action.
            frame_start: First frame to render (default: action's start frame)
            frame_end: Last frame to render (default: action's end frame)
            render_engine: "BLENDER_EEVEE", "CYCLES", or "BLENDER_WORKBENCH"
            resolution: Output resolution (square)
            timeout: Max seconds to wait

        Returns:
            RenderResult with frame file paths in output_files
        """
        job = RenderJob(
            blend_file=blend_file,
            render_animation=True,
            action_name=action_name,
            frame_start=frame_start,
            frame_end=frame_end,
            render_engine=render_engine,
            preview_resolution=resolution  # Reuse this field for animation resolution
        )

        self.submit_job(job)
        return self.wait_for_result(job.job_id, timeout or self.timeout)

    def cleanup_job(self, job_id: str):
        """Remove job files after processing."""
        # Remove from queue (should already be gone)
        job_file = self.queue_dir / f"{job_id}.json"
        if job_file.exists():
            job_file.unlink()
        
        # Remove result file
        result_file = self.output_dir / f"{job_id}.result.json"
        if result_file.exists():
            result_file.unlink()
        
        # Remove job output directory
        job_output_dir = self.output_dir / job_id
        if job_output_dir.exists():
            shutil.rmtree(job_output_dir)
    
    def list_pending_jobs(self) -> List[str]:
        """List job IDs currently in the queue."""
        return [f.stem for f in self.queue_dir.glob("*.json")]
    
    def list_completed_jobs(self) -> List[str]:
        """List job IDs that have completed."""
        return [f.stem.replace(".result", "") for f in self.output_dir.glob("*.result.json")]

    def diagnose_blend(
        self,
        blend_file: str,
        timeout: Optional[float] = None
    ) -> Dict[str, Any]:
        """Run animation diagnostics on a .blend file.

        Checks for common issues that prevent animations from rendering:
        - Armature pose_position (must be POSE, not REST)
        - Armature modifier setup
        - Vertex group assignments
        - Vertex deformation test

        Args:
            blend_file: Path to the .blend file
            timeout: Max seconds to wait

        Returns:
            Dict with diagnostic results including:
            - status: "ok" or "error"
            - issues: List of critical problems
            - warnings: List of potential problems
            - armatures: Armature info
            - meshes: Mesh info
            - actions: Available actions
            - vertex_deformation_test: Results of vertex movement test
        """
        # Write diagnostic script to temp file
        script_path = self.queue_dir / "_diagnostic_script.py"
        script_path.write_text(DIAGNOSTIC_SCRIPT)

        try:
            result = self.render_with_script(
                blend_file=blend_file,
                script=str(script_path),
                timeout=timeout
            )

            # Parse the log file to get diagnostic JSON
            log_file = self.output_dir.parent / "render-watcher.log"
            if log_file.exists():
                log_content = log_file.read_text(encoding='utf-8', errors='ignore')

                # Find the diagnostic JSON in the log
                match = re.search(
                    r'=== DIAGNOSTIC_JSON_START ===\s*\n(.*?)\n=== DIAGNOSTIC_JSON_END ===',
                    log_content,
                    re.DOTALL
                )
                if match:
                    return json.loads(match.group(1))

            return {
                "status": "error",
                "issues": ["Could not parse diagnostic output from log"],
                "warnings": [],
                "armatures": [],
                "meshes": [],
                "actions": [],
                "vertex_deformation_test": None
            }

        finally:
            # Cleanup script
            if script_path.exists():
                script_path.unlink()
