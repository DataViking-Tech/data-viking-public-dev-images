"""
Render job and result data structures.
"""

import json
import uuid
from dataclasses import dataclass, field, asdict
from typing import Optional, List, Dict, Any
from enum import Enum
from pathlib import Path


class RenderEngine(Enum):
    EEVEE = "BLENDER_EEVEE"  # Note: was BLENDER_EEVEE_NEXT in Blender 4.x
    CYCLES = "CYCLES"
    WORKBENCH = "BLENDER_WORKBENCH"


class OutputFormat(Enum):
    GLB = "glb"
    PNG = "png"
    BLEND = "blend"


class JobStatus(Enum):
    PENDING = "pending"
    RENDERING = "rendering"
    COMPLETE = "complete"
    FAILED = "failed"


@dataclass
class RenderJob:
    """A render job to be processed by the Windows host."""
    
    blend_file: str
    job_id: str = field(default_factory=lambda: str(uuid.uuid4())[:8])
    
    # Render settings
    render_engine: str = "BLENDER_EEVEE"
    output_format: str = "glb"
    
    # Optional custom script to run
    script: Optional[str] = None
    script_args: List[str] = field(default_factory=list)
    
    # Preview generation
    generate_previews: bool = False
    # Default angles for comprehensive 360° coverage with elevated views
    preview_angles: List[str] = field(default_factory=lambda: [
        # Ground level cardinal (4)
        "front", "back", "left", "right",
        # Ground level diagonal (4)
        "front_left", "front_right", "back_left", "back_right",
        # Elevated cardinal - 45° above horizon (4)
        "front_above", "back_above", "left_above", "right_above",
        # Elevated diagonal - 45° above horizon (4)
        "front_left_above", "front_right_above", "back_left_above", "back_right_above",
        # Vertical (2)
        "top", "bottom"
    ])
    preview_resolution: int = 512
    generate_contact_sheet: bool = False  # Contact sheets generated on Linux side with labels
    
    # Animation options
    render_animation: bool = False
    frame_start: Optional[int] = None
    frame_end: Optional[int] = None
    action_name: Optional[str] = None  # Name of action to play (e.g., "Walk", "Idle")
    animation_angles: List[str] = field(default_factory=lambda: ["front34", "side", "top"])
    
    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2)
    
    @classmethod
    def from_json(cls, json_str: str) -> 'RenderJob':
        data = json.loads(json_str)
        return cls(**data)
    
    def save(self, path: Path):
        path.write_text(self.to_json())
    
    @classmethod
    def load(cls, path: Path) -> 'RenderJob':
        return cls.from_json(path.read_text(encoding='utf-8-sig'))


@dataclass
class RenderResult:
    """Result from a completed render job."""
    
    job_id: str
    status: str  # JobStatus value
    
    # Output files (paths relative to render-output/)
    output_files: List[str] = field(default_factory=list)
    preview_files: List[str] = field(default_factory=list)
    
    # Timing
    render_time_seconds: float = 0.0
    
    # Error info (if failed)
    error_message: Optional[str] = None
    error_traceback: Optional[str] = None
    
    # Metadata
    blender_version: Optional[str] = None
    gpu_used: Optional[str] = None
    
    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2)
    
    @classmethod
    def from_json(cls, json_str: str) -> 'RenderResult':
        data = json.loads(json_str)
        return cls(**data)
    
    @property
    def success(self) -> bool:
        return self.status == JobStatus.COMPLETE.value
    
    def save(self, path: Path):
        path.write_text(self.to_json())
    
    @classmethod
    def load(cls, path: Path) -> 'RenderResult':
        return cls.from_json(path.read_text(encoding='utf-8-sig'))
