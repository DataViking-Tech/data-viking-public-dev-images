"""
Render Bridge Integration for Asset Generation.

Provides GPU-accelerated rendering via the Windows host render bridge.
Falls back to local CPU rendering if the bridge is unavailable.

Usage:
    from render_bridge_integration import (
        render_static_preview_gpu,
        render_animation_frames_gpu,
        is_bridge_available
    )

    if is_bridge_available():
        paths = render_static_preview_gpu(blend_path, asset_name)
    else:
        # Fall back to local Cycles/Workbench
        pass
"""

import os
import sys
import shutil
import time
from pathlib import Path
from typing import List, Optional, Tuple

# Add render_bridge to path
PYTHON_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, PYTHON_DIR)

try:
    from render_bridge import RenderBridge
    from render_bridge.job import RenderJob
    BRIDGE_AVAILABLE = True
except ImportError:
    BRIDGE_AVAILABLE = False

# Output directories
DEFAULT_BASE_DIR = Path(__file__).resolve().parents[1]
RENDER_BRIDGE_BASE_ENV = "RENDER_BRIDGE_BASE"


def _resolve_base_dir(base_dir: Optional[Path] = None) -> Path:
    if base_dir is not None:
        return Path(base_dir)
    env_base = os.environ.get(RENDER_BRIDGE_BASE_ENV)
    return Path(env_base) if env_base else DEFAULT_BASE_DIR


def _preview_dir_for(base_dir: Path) -> Path:
    return base_dir / "docs" / "asset-previews"

# Bridge settings
BRIDGE_TIMEOUT_STATIC = 120.0  # 2 minutes for static renders
BRIDGE_TIMEOUT_ANIMATION = 600.0  # 10 minutes for animation renders
BRIDGE_POLL_INTERVAL = 1.0


class BridgeUnavailableError(Exception):
    """Raised when the render bridge is not available or times out."""
    pass


def is_bridge_available(timeout: float = 5.0) -> bool:
    """Check if the render bridge is available by testing connection.

    This doesn't actually render anything - just checks if the bridge
    infrastructure exists and the watcher appears to be running.

    Args:
        timeout: How long to wait for a response.

    Returns:
        True if bridge appears available, False otherwise.
    """
    if not BRIDGE_AVAILABLE:
        return False

    try:
        bridge = RenderBridge(timeout=timeout, poll_interval=0.5)

        # Check if queue and output dirs exist and are writable
        if not bridge.queue_dir.exists() or not bridge.output_dir.exists():
            return False

        # Check if we can write to queue (basic connectivity test)
        test_file = bridge.queue_dir / "_bridge_test.tmp"
        try:
            test_file.write_text("test")
            test_file.unlink()
        except Exception:
            return False

        return True

    except Exception:
        return False


def get_bridge(base_dir: Optional[Path] = None) -> RenderBridge:
    """Get a configured RenderBridge instance."""
    if not BRIDGE_AVAILABLE:
        raise BridgeUnavailableError("render_bridge module not available")
    return RenderBridge(
        base_dir=base_dir,
        timeout=BRIDGE_TIMEOUT_STATIC,
        poll_interval=BRIDGE_POLL_INTERVAL
    )


def render_static_preview_gpu(
    blend_path: str,
    asset_name: str,
    angles: List[str] = None,
    resolution: int = 512,
    timeout: Optional[float] = None,
    base_dir: Optional[Path] = None,
) -> List[str]:
    """Render static preview images using GPU via the render bridge.

    Args:
        blend_path: Path to the .blend file.
        asset_name: Name of the asset (for output file naming).
        angles: List of angles to render (default: front, back, left, right).
        resolution: Output resolution (square).
        timeout: Render timeout in seconds.

    Returns:
        List of paths to rendered preview images.

    Raises:
        BridgeUnavailableError: If bridge is not available or times out.
    """
    if angles is None:
        angles = ["front", "back", "left", "right"]

    bridge = get_bridge(base_dir=base_dir)

    try:
        result = bridge.render_blend(
            blend_file=blend_path,
            output_format="png",
            render_engine="BLENDER_EEVEE",
            generate_previews=True,
            timeout=timeout or BRIDGE_TIMEOUT_STATIC
        )

        if result.status != "complete":
            raise BridgeUnavailableError(f"Render failed: {result.error_message}")

        # Copy preview files to the standard preview directory
        preview_dir = _preview_dir_for(_resolve_base_dir(base_dir))
        os.makedirs(preview_dir, exist_ok=True)
        output_paths = []

        job_dir = bridge.output_dir / result.job_id
        for angle in angles:
            src = job_dir / f"{angle}.png"
            if src.exists():
                dst = os.path.join(preview_dir, f"{asset_name}_{angle}.png")
                shutil.copy2(src, dst)
                output_paths.append(dst)

        # Cleanup job files
        bridge.cleanup_job(result.job_id)

        return output_paths

    except TimeoutError as e:
        raise BridgeUnavailableError(f"Render timed out: {e}")
    except Exception as e:
        raise BridgeUnavailableError(f"Render error: {e}")


def render_animation_frames_gpu(
    blend_path: str,
    asset_name: str,
    action_name: str,
    resolution: int = 256,
    timeout: Optional[float] = None,
    base_dir: Optional[Path] = None,
) -> Tuple[List[str], int, int]:
    """Render animation frames using GPU via the render bridge.

    Args:
        blend_path: Path to the .blend file.
        asset_name: Name of the asset.
        action_name: Name of the animation action to render.
        resolution: Output resolution (square).
        timeout: Render timeout in seconds.

    Returns:
        Tuple of (frame_paths, start_frame, end_frame).

    Raises:
        BridgeUnavailableError: If bridge is not available or times out.
    """
    bridge = get_bridge(base_dir=base_dir)

    try:
        result = bridge.render_animation(
            blend_file=blend_path,
            action_name=action_name,
            render_engine="BLENDER_EEVEE",
            resolution=resolution,
            timeout=timeout or BRIDGE_TIMEOUT_ANIMATION
        )

        if result.status != "complete":
            raise BridgeUnavailableError(f"Animation render failed: {result.error_message}")

        # Collect frame paths
        job_dir = bridge.output_dir / result.job_id / "frames"
        frame_files = sorted(job_dir.glob("frame_*.png"))

        if not frame_files:
            raise BridgeUnavailableError("No frames rendered")

        # Parse frame numbers to get range
        frame_nums = []
        for f in frame_files:
            try:
                num = int(f.stem.split("_")[1])
                frame_nums.append(num)
            except (ValueError, IndexError):
                pass

        start_frame = min(frame_nums) if frame_nums else 1
        end_frame = max(frame_nums) if frame_nums else 1

        # Return paths (don't copy yet - let caller handle)
        frame_paths = [str(f) for f in frame_files]

        return frame_paths, start_frame, end_frame

    except TimeoutError as e:
        raise BridgeUnavailableError(f"Animation render timed out: {e}")
    except Exception as e:
        raise BridgeUnavailableError(f"Animation render error: {e}")


def diagnose_blend_animation(blend_path: str) -> dict:
    """Run animation diagnostics on a blend file via the render bridge.

    Args:
        blend_path: Path to the .blend file.

    Returns:
        Diagnostic results dict with status, issues, warnings, etc.
    """
    bridge = get_bridge()
    return bridge.diagnose_blend(blend_path, timeout=60.0)


def cleanup_old_jobs(max_age_hours: float = 1.0):
    """Clean up render bridge job outputs older than max_age_hours.

    This is safe for concurrent use - only removes jobs older than
    the specified age.

    Args:
        max_age_hours: Maximum age in hours before cleanup.
    """
    if not BRIDGE_AVAILABLE:
        return

    try:
        bridge = get_bridge()
        output_dir = bridge.output_dir

        cutoff_time = time.time() - (max_age_hours * 3600)

        # Clean up old job directories
        for item in output_dir.iterdir():
            if item.is_dir() and item.name not in (".", ".."):
                try:
                    # Check modification time
                    if item.stat().st_mtime < cutoff_time:
                        shutil.rmtree(item)
                except Exception:
                    pass
            elif item.is_file() and item.suffix == ".json":
                try:
                    if item.stat().st_mtime < cutoff_time:
                        item.unlink()
                except Exception:
                    pass

    except Exception:
        pass  # Silently fail - cleanup is best effort
