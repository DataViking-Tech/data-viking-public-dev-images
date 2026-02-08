# Render Bridge

Cross-platform rendering bridge between Linux dev container and Windows host with GPU access.

## Why?

- AMD GPUs don't have WSL2/Docker GPU passthrough on Windows
- Blender's Eevee renderer requires GPU/OpenGL
- This bridge lets container code submit render jobs to Windows Blender with full GPU access

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Linux Container                                                  │
│                                                                  │
│   Python Script ──► RenderBridge ──► temp/render-queue/*.json   │
│                                                                  │
│   (polls)         ◄── RenderResult ◄── temp/render-output/      │
└─────────────────────────────────────────────────────────────────┘
                              │ bind mount
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Windows Host                                                     │
│                                                                  │
│   render_watcher.ps1 ──► Blender (GPU) ──► .glb/.png outputs    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Start the Windows watcher (run in PowerShell on Windows)

```powershell
cd frontline-forge
.\temp\render_watcher.ps1
```

The watcher will:
- Auto-detect your Blender installation
- Monitor `temp/render-queue/` for job files
- Render with GPU acceleration
- Write results to `temp/render-output/`

### 2. Submit jobs from the container

```python
from render_bridge import RenderBridge

bridge = RenderBridge()

# Render a .blend file to GLB with Eevee
result = bridge.render_blend(
    blend_file="/workspaces/frontline-forge/project/assets/blender/item_wood.blend",
    output_format="glb",
    render_engine="BLENDER_EEVEE_NEXT"
)

print(f"Output: {result.output_files}")
print(f"Render time: {result.render_time_seconds}s")
print(f"GPU used: {result.gpu_used}")
```

### 3. Generate previews

```python
result = bridge.render_blend(
    blend_file="/workspaces/frontline-forge/project/assets/blender/player.blend",
    generate_previews=True,
    preview_resolution=512
)

# Outputs: front.png, back.png, left.png, right.png
print(f"Previews: {result.preview_files}")
```

### 4. Run custom scripts

```python
result = bridge.render_with_script(
    blend_file="/workspaces/frontline-forge/project/assets/blender/item_wood.blend",
    script="/workspaces/frontline-forge/python/generate_utils.py",
    script_args=["--preview-only"]
)
```

## API Reference

### RenderBridge

| Method | Description |
|--------|-------------|
| `render_blend(blend_file, output_format, ...)` | Render a .blend file and wait for result |
| `render_with_script(blend_file, script, ...)` | Run a custom Blender script |
| `submit_job(job)` | Submit a job without waiting |
| `wait_for_result(job_id)` | Wait for a submitted job |
| `is_complete(job_id)` | Check if job finished |
| `cleanup_job(job_id)` | Remove job files after processing |

### RenderJob options

| Field | Default | Description |
|-------|---------|-------------|
| `blend_file` | required | Path to .blend file |
| `output_format` | `"glb"` | `"glb"`, `"png"`, or `"blend"` |
| `render_engine` | `"BLENDER_EEVEE_NEXT"` | Eevee, Cycles, or Workbench |
| `generate_previews` | `False` | Render 4-angle preview images |
| `preview_resolution` | `512` | Preview image size |
| `script` | `None` | Custom Python script path |
| `script_args` | `[]` | Arguments for custom script |

## Troubleshooting

**Watcher not finding Blender:**
```powershell
.\temp\render_watcher.ps1 -BlenderPath "C:\Path\To\blender.exe"
```

**Jobs timing out:**
```python
bridge = RenderBridge(timeout=600)  # 10 minutes
```

**Check pending jobs:**
```python
print(bridge.list_pending_jobs())
print(bridge.list_completed_jobs())
```
