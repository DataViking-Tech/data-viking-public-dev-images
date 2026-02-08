# Render Watcher - Windows-side GPU render service
# Monitors temp/render-queue/ for jobs and renders with Blender + GPU
# Supports parallel job processing for better GPU utilization
#
# Usage:
#   .\scripts\windows\render_watcher.ps1
#   .\scripts\windows\render_watcher.ps1 -MaxParallel 4
#   .\scripts\windows\render_watcher.ps1 -BlenderPath "C:\Custom\Blender\blender.exe"
#   .\scripts\windows\render_watcher.ps1 -Once  # Process once and exit

param(
    [string]$BlenderPath = "",
    [switch]$Once = $false,
    [int]$PollInterval = 1,
    [int]$MaxParallel = 8  # Default to 8 concurrent Blender instances
)

$ErrorActionPreference = "Stop"

# Paths - data dirs live under $RepoRoot/temp/ (shared with Linux container bridge)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$TempDir = Join-Path $RepoRoot "temp"
$QueueDir = Join-Path $TempDir "render-queue"
$OutputDir = Join-Path $TempDir "render-output"
$LogFile = Join-Path $TempDir "render-watcher.log"
$LockDir = Join-Path $TempDir "render-locks"

# Track active jobs
$script:ActiveJobs = @{}

# Logging function - writes to both console and log file
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] $Message"
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $logLine -Encoding UTF8
}

# Log Blender output to file
function Write-BlenderLog {
    param([string]$JobId, [string]$Output)
    $separator = "=" * 60
    $logContent = @"

$separator
JOB: $JobId @ $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
$separator
$Output
$separator

"@
    Add-Content -Path $LogFile -Value $logContent -Encoding UTF8
}

# Find Blender if not specified
function Find-Blender {
    if ($BlenderPath -and (Test-Path $BlenderPath)) {
        return $BlenderPath
    }

    # Common install locations
    $locations = @(
        "C:\Program Files\Blender Foundation\Blender 5.0\blender.exe",
        "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe",
        "C:\Program Files\Blender Foundation\Blender 4.4\blender.exe",
        "C:\Program Files\Blender Foundation\Blender 4.3\blender.exe",
        "C:\Program Files\Blender Foundation\Blender 4.2\blender.exe",
        "C:\Program Files\Blender Foundation\Blender 4.1\blender.exe",
        "C:\Program Files\Blender Foundation\Blender 4.0\blender.exe",
        "$env:LOCALAPPDATA\Programs\Blender Foundation\Blender 5.0\blender.exe",
        "$env:LOCALAPPDATA\Programs\Blender Foundation\Blender 4.5\blender.exe",
        "$env:LOCALAPPDATA\Programs\Blender Foundation\Blender 4.4\blender.exe"
    )

    foreach ($loc in $locations) {
        if (Test-Path $loc) {
            return $loc
        }
    }

    # Try PATH
    $inPath = Get-Command blender -ErrorAction SilentlyContinue
    if ($inPath) {
        return $inPath.Source
    }

    throw "Blender not found. Install Blender or specify path with -BlenderPath"
}

# Convert container path to Windows path
function Convert-ContainerPath {
    param([string]$Path)

    # /workspaces/frontline-forge/... -> .\...
    if ($Path.StartsWith("/workspaces/frontline-forge/")) {
        $relative = $Path.Substring("/workspaces/frontline-forge/".Length)
        return Join-Path $RepoRoot $relative.Replace("/", "\")
    }

    # Already a Windows path
    if ($Path -match "^[A-Za-z]:") {
        return $Path
    }

    # Relative path
    return Join-Path $RepoRoot $Path.Replace("/", "\")
}

# Try to acquire a lock on a job file (returns $true if successful)
function Acquire-JobLock {
    param([string]$JobId)

    $lockFile = Join-Path $LockDir "$JobId.lock"

    try {
        # Try to create lock file exclusively
        $null = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        return $true
    }
    catch {
        return $false
    }
}

# Release a job lock
function Release-JobLock {
    param([string]$JobId)

    $lockFile = Join-Path $LockDir "$JobId.lock"
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

# Write result JSON
function Write-RenderResult {
    param(
        [string]$JobId,
        [string]$Status,
        [string[]]$OutputFiles,
        [string]$ErrorMessage = "",
        [string[]]$PreviewFiles = @(),
        [double]$RenderTime = 0,
        [string]$BlenderVer = "",
        [string]$Gpu = ""
    )

    $result = @{
        job_id = $JobId
        status = $Status
        output_files = $OutputFiles
        preview_files = $PreviewFiles
        render_time_seconds = $RenderTime
        error_message = $ErrorMessage
        blender_version = $BlenderVer
        gpu_used = $Gpu
    }

    $resultFile = Join-Path $OutputDir "$JobId.result.json"
    $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultFile -Encoding utf8
}

# Process a single render job (runs in background)
$ProcessJobScript = {
    param(
        [string]$JobFilePath,
        [string]$Blender,
        [string]$OutputDir,
        [string]$LogFile,
        [string]$BlenderVersion,
        [string]$GpuName,
        [string]$RepoRoot
    )

    # Helper: Convert container path
    function Convert-ContainerPath {
        param([string]$Path)
        if ($Path.StartsWith("/workspaces/frontline-forge/")) {
            $relative = $Path.Substring("/workspaces/frontline-forge/".Length)
            return Join-Path $RepoRoot $relative.Replace("/", "\")
        }
        if ($Path -match "^[A-Za-z]:") { return $Path }
        return Join-Path $RepoRoot $Path.Replace("/", "\")
    }

    # Helper: Write result
    function Write-RenderResult {
        param($JobId, $Status, $OutputFiles, $ErrorMessage = "", $PreviewFiles = @(), $RenderTime = 0)
        $result = @{
            job_id = $JobId; status = $Status; output_files = $OutputFiles
            preview_files = $PreviewFiles; render_time_seconds = $RenderTime
            error_message = $ErrorMessage; blender_version = $BlenderVersion; gpu_used = $GpuName
        }
        $resultFile = Join-Path $OutputDir "$JobId.result.json"
        $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultFile -Encoding utf8
    }

    $job = Get-Content $JobFilePath | ConvertFrom-Json
    $jobId = $job.job_id
    $startTime = Get-Date

    # Create job output directory
    $jobOutputDir = Join-Path $OutputDir $jobId
    New-Item -ItemType Directory -Path $jobOutputDir -Force | Out-Null

    # Convert paths
    $blendFile = Convert-ContainerPath $job.blend_file

    if (-not (Test-Path $blendFile)) {
        Write-RenderResult $jobId "failed" @() "Blend file not found: $blendFile"
        Remove-Item $JobFilePath -Force
        return @{ JobId = $jobId; Status = "failed"; Error = "Blend file not found" }
    }

    try {
        $outputFiles = @()
        $previewFiles = @()

        # Handle custom script
        if ($job.script) {
            $scriptPath = Convert-ContainerPath $job.script
            $args = @("--background", $blendFile, "--python", $scriptPath)
            if ($job.script_args) { $args += "--"; $args += $job.script_args }

            $blenderOutput = & $Blender @args 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                throw "Script failed: $blenderOutput"
            }
        }
        else {
            # Standard export based on format
            switch ($job.output_format) {
                "glb" {
                    $outputPath = Join-Path $jobOutputDir "$jobId.glb"
                    $exportScript = @"
import bpy
bpy.context.scene.render.engine = '$($job.render_engine)'
bpy.ops.export_scene.gltf(filepath=r'$outputPath', export_format='GLB')
"@
                    $tempScript = Join-Path $env:TEMP "render_export_$jobId.py"
                    $exportScript | Out-File -FilePath $tempScript -Encoding utf8
                    $blenderOutput = & $Blender --background $blendFile --python $tempScript 2>&1 | Out-String
                    Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
                    if (-not (Test-Path $outputPath)) { throw "No output: $blenderOutput" }
                    $outputFiles += "$jobId/$jobId.glb"
                }
                "png" {
                    $outputPath = Join-Path $jobOutputDir "$jobId.png"
                    $renderScript = @"
import bpy
from mathutils import Vector
scene = bpy.context.scene
scene.render.engine = '$($job.render_engine)'
scene.render.filepath = r'$outputPath'
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
scene.render.resolution_x = 512
scene.render.resolution_y = 512
if not scene.camera:
    cam_data = bpy.data.cameras.new('RenderCam')
    cam_data.type = 'ORTHO'
    cam_obj = bpy.data.objects.new('RenderCam', cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    # Calculate bounds from actual vertices (not bound_box which can be stale)
    min_co = [float('inf')] * 3
    max_co = [float('-inf')] * 3
    for obj in scene.objects:
        if obj.type != 'MESH': continue
        for v in obj.data.vertices:
            world = obj.matrix_world @ v.co
            for i in range(3):
                min_co[i] = min(min_co[i], world[i])
                max_co[i] = max(max_co[i], world[i])
    if min_co[0] != float('inf'):
        center = Vector([(min_co[i] + max_co[i]) / 2 for i in range(3)])
        size = [max_co[i] - min_co[i] for i in range(3)]
        max_dim = max(size)
        distance = max_dim * 2
        cam_dir = (0.707, -0.707, 0.5)
        # Per-angle projected framing with percentile-based extents
        all_verts = []
        for obj in scene.objects:
            if obj.type != 'MESH': continue
            for v in obj.data.vertices:
                all_verts.append(obj.matrix_world @ v.co)
        cam_look = -Vector(cam_dir).normalized()
        up = Vector((0, 0, 1))
        right = cam_look.cross(up).normalized()
        up = right.cross(cam_look).normalized()
        r_vals = []
        u_vals = []
        for v in all_verts:
            rel = v - center
            r_vals.append(rel.dot(right))
            u_vals.append(rel.dot(up))
        n = len(r_vals) if r_vals else 1
        r_vals.sort()
        u_vals.sort()
        lo = max(0, int(n * 0.025))
        hi = min(n - 1, int(n * 0.975))
        r_lo, r_hi = r_vals[lo], r_vals[hi]
        u_lo, u_hi = u_vals[lo], u_vals[hi]
        vc = center + right * (r_lo + r_hi) / 2 + up * (u_lo + u_hi) / 2
        cam_data.ortho_scale = max(r_hi - r_lo, u_hi - u_lo) * 1.3
        cam_obj.rotation_mode = 'QUATERNION'
        cam_obj.location = vc + Vector([cam_dir[0] * distance, cam_dir[1] * distance, cam_dir[2] * distance])
        direction = vc - cam_obj.location
        cam_obj.rotation_quaternion = direction.to_track_quat('-Z', 'Y')
bpy.ops.render.render(write_still=True)
"@
                    $tempScript = Join-Path $env:TEMP "render_export_$jobId.py"
                    $renderScript | Out-File -FilePath $tempScript -Encoding utf8
                    $blenderOutput = & $Blender --background $blendFile --python $tempScript 2>&1 | Out-String
                    Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
                    if (-not (Test-Path $outputPath)) { throw "No output: $blenderOutput" }
                    $outputFiles += "$jobId/$jobId.png"
                }
            }
        }

        # Render animation if requested (renders from multiple angles)
        if ($job.render_animation) {
            $actionName = if ($job.action_name) { "'$($job.action_name)'" } else { "None" }
            $frameStartParam = if ($job.frame_start) { $job.frame_start } else { "None" }
            $frameEndParam = if ($job.frame_end) { $job.frame_end } else { "None" }

            # Get animation angles (default to front34, side, top)
            $animAngles = if ($job.animation_angles) { $job.animation_angles } else { @("front34", "side", "top") }
            $animAnglesJson = $animAngles | ConvertTo-Json -Compress

            $animScript = @"
import bpy
from mathutils import Vector
import os
scene = bpy.context.scene
scene.render.engine = '$($job.render_engine)'
scene.render.resolution_x = $($job.preview_resolution)
scene.render.resolution_y = $($job.preview_resolution)
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'

# Ensure proper Eevee settings for material rendering (with fallback for API changes)
try:
    if scene.render.engine == 'BLENDER_EEVEE' and hasattr(scene, 'eevee'):
        scene.eevee.use_gtao = True
        scene.eevee.gtao_distance = 1.0
        if hasattr(scene.eevee, 'use_soft_shadows'):
            scene.eevee.use_soft_shadows = True
except Exception as e:
    print(f'Eevee settings warning: {e}')

# Enable compositor bloom so emission materials (crystals, glowing eyes) render with glow halos
# In Blender 4.x, bloom moved from Eevee settings to compositor Glare node
try:
    scene.use_nodes = True
    tree = scene.node_tree
    for link in list(tree.links):
        tree.links.remove(link)
    render_layers = tree.nodes.get('Render Layers')
    composite = tree.nodes.get('Composite')
    if render_layers and composite:
        glare = tree.nodes.new(type='CompositorNodeGlare')
        glare.glare_type = 'BLOOM'
        glare.quality = 'HIGH'
        glare.threshold = 0.8
        glare.size = 6
        glare.mix = 0.0
        tree.links.new(render_layers.outputs['Image'], glare.inputs['Image'])
        tree.links.new(glare.outputs['Image'], composite.inputs['Image'])
        if 'Alpha' in render_layers.outputs and 'Alpha' in composite.inputs:
            tree.links.new(render_layers.outputs['Alpha'], composite.inputs['Alpha'])
        print('Compositor bloom enabled via Glare node')
    else:
        print('Compositor bloom skipped: missing Render Layers or Composite node')
except Exception as e:
    print(f'Compositor bloom warning: {e}')

# Set up world lighting if not present (needed for proper material colors)
try:
    if not scene.world:
        scene.world = bpy.data.worlds.new('RenderWorld')
    if scene.world:
        scene.world.use_nodes = True
        nodes = scene.world.node_tree.nodes
        links = scene.world.node_tree.links
        nodes.clear()
        bg = nodes.new('ShaderNodeBackground')
        bg.inputs['Color'].default_value = (0.15, 0.15, 0.17, 1.0)
        bg.inputs['Strength'].default_value = 1.0
        output = nodes.new('ShaderNodeOutputWorld')
        links.new(bg.outputs['Background'], output.inputs['Surface'])
except Exception as e:
    print(f'World setup warning: {e}')

# Add fill lights for better material visibility
def add_area_light(name, location, energy, size=5.0):
    try:
        light_data = bpy.data.lights.new(name, 'AREA')
        light_data.energy = energy
        light_data.size = size
        light_data.color = (1.0, 1.0, 1.0)
        light_obj = bpy.data.objects.new(name, light_data)
        scene.collection.objects.link(light_obj)
        light_obj.location = location
        direction = Vector((0, 0, 0)) - light_obj.location
        light_obj.rotation_mode = 'QUATERNION'
        light_obj.rotation_quaternion = direction.to_track_quat('-Z', 'Y')
        return light_obj
    except Exception as e:
        print(f'Light setup warning for {name}: {e}')
        return None

# Calculate model bounds for light scaling (meshes already loaded at this point)
min_co = [float('inf')] * 3
max_co = [float('-inf')] * 3
for obj in scene.objects:
    if obj.type != 'MESH': continue
    for v in obj.data.vertices:
        world = obj.matrix_world @ v.co
        for i in range(3):
            min_co[i] = min(min_co[i], world[i])
            max_co[i] = max(max_co[i], world[i])

if min_co[0] != float('inf'):
    center = Vector([(min_co[i] + max_co[i]) / 2 for i in range(3)])
    size = [max_co[i] - min_co[i] for i in range(3)]
    max_dim = max(size)
else:
    center = Vector((0, 0, 0))
    max_dim = 2.0

light_scale = max(max_dim / 10.0, 1.0)
energy_scale = light_scale * light_scale  # Inverse-square law compensation
add_area_light('KeyLight', (5 * light_scale, -5 * light_scale, 8 * light_scale), 200 * energy_scale, 8.0 * light_scale)
add_area_light('FillLight', (-5 * light_scale, -3 * light_scale, 4 * light_scale), 80 * energy_scale, 6.0 * light_scale)
add_area_light('RimLight', (0, 6 * light_scale, 4 * light_scale), 100 * energy_scale, 4.0 * light_scale)

base_frames_dir = r'$jobOutputDir'
action_name = $actionName
armature = None
for obj in bpy.data.objects:
    if obj.type == 'ARMATURE':
        armature = obj
        break

# Set up animation
if armature:
    armature.data.pose_position = 'POSE'
    if not armature.animation_data:
        armature.animation_data_create()
    if armature.animation_data.nla_tracks:
        for track in armature.animation_data.nla_tracks:
            track.mute = True
    if action_name and action_name in bpy.data.actions:
        armature.animation_data.action = bpy.data.actions[action_name]
    action = armature.animation_data.action
    if action:
        frame_start = $frameStartParam if $frameStartParam is not None else int(action.frame_range[0])
        frame_end = $frameEndParam if $frameEndParam is not None else int(action.frame_range[1])
    else:
        frame_start = $frameStartParam if $frameStartParam is not None else 1
        frame_end = $frameEndParam if $frameEndParam is not None else 24
else:
    frame_start = $frameStartParam if $frameStartParam is not None else 1
    frame_end = $frameEndParam if $frameEndParam is not None else 24

# Create camera (center and max_dim already computed above for light scaling)
cam_data = bpy.data.cameras.new('AnimCam')
cam_data.type = 'ORTHO'
cam_data.ortho_scale = max_dim * 1.5
cam_obj = bpy.data.objects.new('AnimCam', cam_data)
scene.collection.objects.link(cam_obj)
scene.camera = cam_obj
distance = max_dim * 2

# Angle definitions (direction vectors from center)
sqrt2 = 0.707
sqrt3 = 0.577
anim_angles = {
    'front34': (-sqrt2, sqrt2, 0.3),  # 45 deg front-left, slight elevation
    'side': (1, 0, 0),                 # Pure side (from right)
    'top': (0, 0.1, 1),                # Top-down with slight tilt for depth
    'front': (0, 1, 0),
    'back': (0, -1, 0),
}

# Pre-collect world-space vertices for per-angle projected framing
all_verts = []
for obj in scene.objects:
    if obj.type != 'MESH': continue
    for v in obj.data.vertices:
        all_verts.append(obj.matrix_world @ v.co)

def get_view_frame(cam_dir, verts, bbox_center, padding=1.5):
    """Compute per-angle ortho_scale and view center from projected 2D bounds.
    Uses percentile-based extents so thin extremities don't dominate framing."""
    cam_look = -Vector(cam_dir).normalized()
    up = Vector((0, 0, 1))
    if abs(cam_look.dot(up)) > 0.99:
        up = Vector((0, 1, 0))
    right = cam_look.cross(up).normalized()
    up = right.cross(cam_look).normalized()
    if not verts:
        return bbox_center, 2.0
    r_vals = []
    u_vals = []
    for v in verts:
        rel = v - bbox_center
        r_vals.append(rel.dot(right))
        u_vals.append(rel.dot(up))
    n = len(r_vals)
    r_vals.sort()
    u_vals.sort()
    lo = max(0, int(n * 0.025))
    hi = min(n - 1, int(n * 0.975))
    r_lo, r_hi = r_vals[lo], r_vals[hi]
    u_lo, u_hi = u_vals[lo], u_vals[hi]
    vc = bbox_center + right * (r_lo + r_hi) / 2 + up * (u_lo + u_hi) / 2
    ortho = max(r_hi - r_lo, u_hi - u_lo) * padding
    return vc, max(ortho, 0.1)

# Render frames for each requested angle
requested_angles = $animAnglesJson
scene.frame_start = frame_start
scene.frame_end = frame_end
cam_obj.rotation_mode = 'QUATERNION'

for angle_name in requested_angles:
    if angle_name not in anim_angles:
        print(f'Unknown angle: {angle_name}, skipping')
        continue

    # Create angle-specific frames directory
    angle_frames_dir = os.path.join(base_frames_dir, f'frames_{angle_name}')
    os.makedirs(angle_frames_dir, exist_ok=True)

    # Per-angle framing: project vertices onto camera plane
    dir_vec = anim_angles[angle_name]
    view_center, angle_ortho = get_view_frame(dir_vec, all_verts, center)
    cam_data.ortho_scale = angle_ortho
    cam_obj.location = view_center + Vector([dir_vec[0] * distance, dir_vec[1] * distance, dir_vec[2] * distance])
    direction = view_center - cam_obj.location
    cam_obj.rotation_quaternion = direction.to_track_quat('-Z', 'Y')

    print(f'Rendering {angle_name}: frames {frame_start}-{frame_end}')

    # Render all frames for this angle
    for frame in range(frame_start, frame_end + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(angle_frames_dir, f'frame_{frame:04d}.png')
        bpy.ops.render.render(write_still=True)

    print(f'  Completed {angle_name}: {frame_end - frame_start + 1} frames')
"@
            $tempScript = Join-Path $env:TEMP "render_anim_$jobId.py"
            $animScript | Out-File -FilePath $tempScript -Encoding utf8
            $blenderOutput = & $Blender --background $blendFile --python $tempScript 2>&1 | Out-String
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue

            # Collect frame files from all angle directories
            $totalFrames = 0
            foreach ($angle in $animAngles) {
                $angleFramesDir = Join-Path $jobOutputDir "frames_$angle"
                if (Test-Path $angleFramesDir) {
                    $frameFiles = Get-ChildItem -Path $angleFramesDir -Filter "frame_*.png" -ErrorAction SilentlyContinue
                    foreach ($frame in $frameFiles) {
                        $outputFiles += "$jobId/frames_$angle/$($frame.Name)"
                    }
                    $totalFrames += $frameFiles.Count
                }
            }
            if ($totalFrames -eq 0) { throw "No frames rendered" }
        }

        # Generate previews if requested
        if ($job.generate_previews) {
            $previewScript = @"
import bpy
from mathutils import Vector
import os
scene = bpy.context.scene
scene.render.engine = '$($job.render_engine)'
scene.render.resolution_x = $($job.preview_resolution)
scene.render.resolution_y = $($job.preview_resolution)
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'

# Ensure proper Eevee settings for material rendering (with fallback for API changes)
try:
    if scene.render.engine == 'BLENDER_EEVEE' and hasattr(scene, 'eevee'):
        scene.eevee.use_gtao = True
        scene.eevee.gtao_distance = 1.0
        if hasattr(scene.eevee, 'use_soft_shadows'):
            scene.eevee.use_soft_shadows = True
except Exception as e:
    print(f'Eevee settings warning: {e}')

# Enable compositor bloom so emission materials (crystals, glowing eyes) render with glow halos
# In Blender 4.x, bloom moved from Eevee settings to compositor Glare node
try:
    scene.use_nodes = True
    tree = scene.node_tree
    for link in list(tree.links):
        tree.links.remove(link)
    render_layers = tree.nodes.get('Render Layers')
    composite = tree.nodes.get('Composite')
    if render_layers and composite:
        glare = tree.nodes.new(type='CompositorNodeGlare')
        glare.glare_type = 'BLOOM'
        glare.quality = 'HIGH'
        glare.threshold = 0.8
        glare.size = 6
        glare.mix = 0.0
        tree.links.new(render_layers.outputs['Image'], glare.inputs['Image'])
        tree.links.new(glare.outputs['Image'], composite.inputs['Image'])
        if 'Alpha' in render_layers.outputs and 'Alpha' in composite.inputs:
            tree.links.new(render_layers.outputs['Alpha'], composite.inputs['Alpha'])
        print('Compositor bloom enabled via Glare node')
    else:
        print('Compositor bloom skipped: missing Render Layers or Composite node')
except Exception as e:
    print(f'Compositor bloom warning: {e}')

# Set up world lighting if not present (needed for proper material colors)
try:
    if not scene.world:
        scene.world = bpy.data.worlds.new('RenderWorld')
    if scene.world:
        scene.world.use_nodes = True
        nodes = scene.world.node_tree.nodes
        links = scene.world.node_tree.links
        # Clear existing nodes
        nodes.clear()
        # Add background node with neutral gray
        bg = nodes.new('ShaderNodeBackground')
        bg.inputs['Color'].default_value = (0.15, 0.15, 0.17, 1.0)
        bg.inputs['Strength'].default_value = 1.0
        output = nodes.new('ShaderNodeOutputWorld')
        links.new(bg.outputs['Background'], output.inputs['Surface'])
except Exception as e:
    print(f'World setup warning: {e}')

# Add fill lights for better material visibility
def add_area_light(name, location, energy, size=5.0):
    try:
        light_data = bpy.data.lights.new(name, 'AREA')
        light_data.energy = energy
        light_data.size = size
        light_data.color = (1.0, 1.0, 1.0)
        light_obj = bpy.data.objects.new(name, light_data)
        scene.collection.objects.link(light_obj)
        light_obj.location = location
        # Point at origin
        direction = Vector((0, 0, 0)) - light_obj.location
        light_obj.rotation_mode = 'QUATERNION'
        light_obj.rotation_quaternion = direction.to_track_quat('-Z', 'Y')
        return light_obj
    except Exception as e:
        print(f'Light setup warning for {name}: {e}')
        return None

cam_data = bpy.data.cameras.new('PreviewCam')
cam_data.type = 'ORTHO'
cam_obj = bpy.data.objects.new('PreviewCam', cam_data)
scene.collection.objects.link(cam_obj)
scene.camera = cam_obj
# Force depsgraph evaluation so bone-parented objects have correct matrix_world
bpy.context.view_layer.update()
# Calculate bounds from actual vertices (not bound_box which can be stale)
min_co = [float('inf')] * 3
max_co = [float('-inf')] * 3
for obj in scene.objects:
    if obj.type != 'MESH': continue
    for v in obj.data.vertices:
        world = obj.matrix_world @ v.co
        for i in range(3):
            min_co[i] = min(min_co[i], world[i])
            max_co[i] = max(max_co[i], world[i])
if min_co[0] != float('inf'):
    center = Vector([(min_co[i] + max_co[i]) / 2 for i in range(3)])
    size = [max_co[i] - min_co[i] for i in range(3)]
    max_dim = max(size)
    cam_data.ortho_scale = max_dim * 1.2
    distance = max_dim * 2
    # Scale lights relative to model size (normalized to ~10-unit models)
    light_scale = max(max_dim / 10.0, 1.0)
    energy_scale = light_scale * light_scale  # Inverse-square law compensation
    add_area_light('KeyLight', (5 * light_scale, -5 * light_scale, 8 * light_scale), 200 * energy_scale, 8.0 * light_scale)
    add_area_light('FillLight', (-5 * light_scale, -3 * light_scale, 4 * light_scale), 80 * energy_scale, 6.0 * light_scale)
    add_area_light('RimLight', (0, 6 * light_scale, 4 * light_scale), 100 * energy_scale, 4.0 * light_scale)
    sqrt2 = 0.707  # 1/sqrt(2) for 45-degree diagonals
    sqrt3 = 0.577  # 1/sqrt(3) for 3D diagonals
    elev = 0.707   # Elevation factor for "above" angles (45 degrees up)
    elev_h = 0.707 # Horizontal factor when elevated
    # Full angle dictionary - direction vectors (x, y, z offset from center)
    all_angles = {
        # Ground level cardinal
        'front': (0, 1, 0),
        'back': (0, -1, 0),
        'left': (-1, 0, 0),
        'right': (1, 0, 0),
        # Ground level diagonal
        'front_left': (-sqrt2, sqrt2, 0),
        'front_right': (sqrt2, sqrt2, 0),
        'back_left': (-sqrt2, -sqrt2, 0),
        'back_right': (sqrt2, -sqrt2, 0),
        # Elevated cardinal (45° above horizon)
        'front_above': (0, elev_h, elev),
        'back_above': (0, -elev_h, elev),
        'left_above': (-elev_h, 0, elev),
        'right_above': (elev_h, 0, elev),
        # Elevated diagonal (45° above horizon)
        'front_left_above': (-sqrt3, sqrt3, sqrt3),
        'front_right_above': (sqrt3, sqrt3, sqrt3),
        'back_left_above': (-sqrt3, -sqrt3, sqrt3),
        'back_right_above': (sqrt3, -sqrt3, sqrt3),
        # Vertical
        'top': (0, 0, 1),
        'bottom': (0, 0, -1),
        # Animation-specific angles (for GIF previews)
        'front34': (-sqrt2, sqrt2, 0.3),  # 45° from front-left, slight elevation
        'side': (1, 0, 0),  # Pure side profile (same as 'right')
    }
    # Use quaternion rotation to avoid gimbal lock on elevated/diagonal angles
    cam_obj.rotation_mode = 'QUATERNION'

    # Pre-collect world-space vertices for per-angle projected framing
    all_verts = []
    for obj in scene.objects:
        if obj.type != 'MESH': continue
        for v in obj.data.vertices:
            all_verts.append(obj.matrix_world @ v.co)

    def get_view_frame(cam_dir, verts, bbox_center, padding=1.3):
        """Compute per-angle ortho_scale and view center from projected 2D bounds.
        Uses percentile-based extents so thin extremities (spire tips) don't
        dominate framing for models with extreme aspect ratios."""
        cam_look = -Vector(cam_dir).normalized()
        up = Vector((0, 0, 1))
        if abs(cam_look.dot(up)) > 0.99:
            up = Vector((0, 1, 0))
        right = cam_look.cross(up).normalized()
        up = right.cross(cam_look).normalized()
        if not verts:
            return bbox_center, 2.0
        r_vals = []
        u_vals = []
        for v in verts:
            rel = v - bbox_center
            r_vals.append(rel.dot(right))
            u_vals.append(rel.dot(up))
        n = len(r_vals)
        r_vals.sort()
        u_vals.sort()
        # Use 2.5th-97.5th percentile to trim thin extremities
        lo = max(0, int(n * 0.025))
        hi = min(n - 1, int(n * 0.975))
        r_lo, r_hi = r_vals[lo], r_vals[hi]
        u_lo, u_hi = u_vals[lo], u_vals[hi]
        vc = bbox_center + right * (r_lo + r_hi) / 2 + up * (u_lo + u_hi) / 2
        ortho = max(r_hi - r_lo, u_hi - u_lo) * padding
        return vc, max(ortho, 0.1)

    requested_angles = $($job.preview_angles | ConvertTo-Json -Compress)
    rendered_images = []
    for name in requested_angles:
        if name not in all_angles:
            continue
        dir = all_angles[name]
        # Per-angle framing: project vertices onto camera plane
        view_center, angle_ortho = get_view_frame(dir, all_verts, center)
        cam_data.ortho_scale = angle_ortho
        # Position camera from the projected view center
        cam_obj.location = view_center + Vector([dir[0] * distance, dir[1] * distance, dir[2] * distance])
        direction = view_center - cam_obj.location
        cam_obj.rotation_quaternion = direction.to_track_quat('-Z', 'Y')
        out = os.path.join(r'$jobOutputDir', f'{name}.png')
        scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        rendered_images.append((name, out))

# Generate contact sheet if requested and we have multiple images
generate_sheet = $(if ($job.generate_contact_sheet) { 'True' } else { 'False' })
if generate_sheet and len(rendered_images) > 1:
    import math

    # Determine grid size (aim for roughly square)
    n = len(rendered_images)
    cols = math.ceil(math.sqrt(n))
    rows = math.ceil(n / cols)

    res = $($job.preview_resolution)

    # Create a new image in Blender for the contact sheet
    sheet_name = 'ContactSheet'
    if sheet_name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[sheet_name])

    sheet = bpy.data.images.new(sheet_name, width=cols * res, height=rows * res, alpha=True)
    sheet_pixels = [0.0] * (cols * res * rows * res * 4)  # RGBA

    for i, (name, path) in enumerate(rendered_images):
        try:
            # Load source image
            if name in bpy.data.images:
                bpy.data.images.remove(bpy.data.images[name])
            src_img = bpy.data.images.load(path)
            src_pixels = list(src_img.pixels[:])

            # Calculate position in grid (flip Y since Blender images are bottom-up)
            grid_x = i % cols
            grid_y = rows - 1 - (i // cols)  # Flip Y

            # Copy pixels to contact sheet
            for py in range(res):
                for px in range(res):
                    src_idx = (py * res + px) * 4
                    dst_x = grid_x * res + px
                    dst_y = grid_y * res + py
                    dst_idx = (dst_y * cols * res + dst_x) * 4
                    for c in range(4):
                        sheet_pixels[dst_idx + c] = src_pixels[src_idx + c]

            bpy.data.images.remove(src_img)
        except Exception as e:
            print(f'Failed to add {name} to contact sheet: {e}')

    # Set pixels and save
    sheet.pixels = sheet_pixels
    sheet_path = os.path.join(r'$jobOutputDir', 'contact_sheet.png')
    sheet.filepath_raw = sheet_path
    sheet.file_format = 'PNG'
    sheet.save()
    print(f'Contact sheet saved: {sheet_path}')
"@
            $tempScript = Join-Path $env:TEMP "render_preview_$jobId.py"
            $previewScript | Out-File -FilePath $tempScript -Encoding utf8
            $blenderOutput = & $Blender --background $blendFile --python $tempScript 2>&1 | Out-String
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue

            # Collect all rendered preview files (18 angles)
            $possibleAngles = @(
                "front", "back", "left", "right",
                "front_left", "front_right", "back_left", "back_right",
                "front_above", "back_above", "left_above", "right_above",
                "front_left_above", "front_right_above", "back_left_above", "back_right_above",
                "top", "bottom"
            )
            foreach ($angle in $possibleAngles) {
                $previewPath = Join-Path $jobOutputDir "$angle.png"
                if (Test-Path $previewPath) { $previewFiles += "$jobId/$angle.png" }
            }
            # Also include contact sheet if generated
            $sheetPath = Join-Path $jobOutputDir "contact_sheet.png"
            if (Test-Path $sheetPath) { $previewFiles += "$jobId/contact_sheet.png" }
        }

        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        Write-RenderResult $jobId "complete" $outputFiles "" $previewFiles $elapsed
        return @{ JobId = $jobId; Status = "complete"; Time = $elapsed }
    }
    catch {
        $errorMsg = $_.ToString()
        Write-RenderResult $jobId "failed" @() $errorMsg
        return @{ JobId = $jobId; Status = "failed"; Error = $errorMsg }
    }
    finally {
        Remove-Item $JobFilePath -Force -ErrorAction SilentlyContinue
    }
}

# Main
Write-Host "=== Render Watcher (Parallel) ===" -ForegroundColor Yellow
Write-Host "Queue: $QueueDir"
Write-Host "Output: $OutputDir"
Write-Host "Max Parallel: $MaxParallel"

# Ensure directories exist
New-Item -ItemType Directory -Path $QueueDir -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
New-Item -ItemType Directory -Path $LockDir -Force | Out-Null

# Find and verify Blender
$Blender = Find-Blender
Write-Host "Blender: $Blender" -ForegroundColor Green

# Get Blender version
$versionOutput = & $Blender --version 2>&1 | Select-Object -First 1
$BlenderVersion = $versionOutput -replace "Blender ", ""
Write-Host "Version: $BlenderVersion"

# Get GPU info
$GpuName = (Get-WmiObject Win32_VideoController | Select-Object -First 1).Name
Write-Host "GPU: $GpuName"

Write-Host "`nWatching for render jobs (parallel mode)..." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop`n"

# Main loop
do {
    # Clean up completed jobs
    $completedJobs = @()
    foreach ($jobId in $script:ActiveJobs.Keys) {
        $psJob = $script:ActiveJobs[$jobId]
        if ($psJob.State -eq 'Completed') {
            $result = Receive-Job $psJob
            Remove-Job $psJob
            Release-JobLock $jobId
            $completedJobs += $jobId

            if ($result.Status -eq "complete") {
                Write-Host "[$jobId] Complete in $([math]::Round($result.Time, 1))s" -ForegroundColor Green
            } else {
                Write-Host "[$jobId] Failed: $($result.Error)" -ForegroundColor Red
            }
        }
        elseif ($psJob.State -eq 'Failed') {
            $errorInfo = $psJob.ChildJobs[0].JobStateInfo.Reason.Message
            Remove-Job $psJob
            Release-JobLock $jobId
            $completedJobs += $jobId
            Write-Host "[$jobId] Job failed: $errorInfo" -ForegroundColor Red
        }
    }
    foreach ($jobId in $completedJobs) {
        $script:ActiveJobs.Remove($jobId)
    }

    # Check for new jobs if we have capacity
    $activeCount = $script:ActiveJobs.Count
    if ($activeCount -lt $MaxParallel) {
        $jobs = Get-ChildItem -Path $QueueDir -Filter "*.json" -ErrorAction SilentlyContinue |
                Sort-Object CreationTime |
                Select-Object -First ($MaxParallel - $activeCount)

        foreach ($jobFile in $jobs) {
            $jobId = [System.IO.Path]::GetFileNameWithoutExtension($jobFile.Name)

            # Skip if already processing
            if ($script:ActiveJobs.ContainsKey($jobId)) { continue }

            # Try to acquire lock
            if (-not (Acquire-JobLock $jobId)) { continue }

            Write-Host "[$jobId] Starting..." -ForegroundColor Cyan

            # Start background job
            $psJob = Start-Job -ScriptBlock $ProcessJobScript -ArgumentList @(
                $jobFile.FullName,
                $Blender,
                $OutputDir,
                $LogFile,
                $BlenderVersion,
                $GpuName,
                $RepoRoot
            )

            $script:ActiveJobs[$jobId] = $psJob
        }
    }

    # Show status
    if ($script:ActiveJobs.Count -gt 0) {
        $runningIds = $script:ActiveJobs.Keys -join ", "
        Write-Host "`rActive: $($script:ActiveJobs.Count)/$MaxParallel [$runningIds]" -NoNewline
    }

    if (-not $Once -or $script:ActiveJobs.Count -gt 0) {
        Start-Sleep -Milliseconds ($PollInterval * 1000)
    }
} while (-not $Once -or $script:ActiveJobs.Count -gt 0)

# Wait for remaining jobs
while ($script:ActiveJobs.Count -gt 0) {
    Start-Sleep -Seconds 1
    foreach ($jobId in @($script:ActiveJobs.Keys)) {
        $psJob = $script:ActiveJobs[$jobId]
        if ($psJob.State -ne 'Running') {
            $result = Receive-Job $psJob -ErrorAction SilentlyContinue
            Remove-Job $psJob
            Release-JobLock $jobId
            $script:ActiveJobs.Remove($jobId)
        }
    }
}

if ($Once) {
    Write-Host "`nAll jobs complete." -ForegroundColor Green
}
