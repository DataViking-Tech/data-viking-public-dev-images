"""
Animation diagnostic script for render bridge.
Checks armature setup, vertex deformation, and action assignment.
"""

DIAGNOSTIC_SCRIPT = '''
import bpy
import json
from mathutils import Vector

def run_diagnostics():
    results = {
        "status": "ok",
        "issues": [],
        "warnings": [],
        "armatures": [],
        "meshes": [],
        "actions": [],
        "vertex_deformation_test": None
    }

    # Collect actions
    for action in bpy.data.actions:
        results["actions"].append({
            "name": action.name,
            "frame_start": action.frame_range[0],
            "frame_end": action.frame_range[1]
        })

    # Check armatures
    for obj in bpy.data.objects:
        if obj.type == 'ARMATURE':
            arm_info = {
                "name": obj.name,
                "pose_position": obj.data.pose_position,
                "bone_count": len(obj.data.bones),
                "active_action": None,
                "nla_tracks": [],
                "nla_muted": []
            }
            
            # Check pose position - critical!
            if obj.data.pose_position == 'REST':
                results["issues"].append(f"Armature '{obj.name}' is in REST position - animations won't show!")
                results["status"] = "error"
            
            # Check animation data
            if obj.animation_data:
                if obj.animation_data.action:
                    arm_info["active_action"] = obj.animation_data.action.name
                for track in obj.animation_data.nla_tracks:
                    arm_info["nla_tracks"].append(track.name)
                    arm_info["nla_muted"].append(track.mute)
            else:
                results["warnings"].append(f"Armature '{obj.name}' has no animation_data")
            
            results["armatures"].append(arm_info)

    # Check meshes
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            mesh_info = {
                "name": obj.name,
                "vertex_count": len(obj.data.vertices),
                "vertex_groups": [vg.name for vg in obj.vertex_groups],
                "armature_modifier": None
            }
            
            for mod in obj.modifiers:
                if mod.type == 'ARMATURE':
                    mesh_info["armature_modifier"] = {
                        "name": mod.name,
                        "object": mod.object.name if mod.object else None,
                        "show_render": mod.show_render,
                        "show_viewport": mod.show_viewport,
                        "use_vertex_groups": mod.use_vertex_groups
                    }
                    
                    if not mod.show_render:
                        results["issues"].append(f"Armature modifier on '{obj.name}' has show_render=False")
                        results["status"] = "error"
            
            if not mesh_info["armature_modifier"] and mesh_info["vertex_groups"]:
                results["warnings"].append(f"Mesh '{obj.name}' has vertex groups but no armature modifier")
            
            results["meshes"].append(mesh_info)

    # Vertex deformation test
    if results["armatures"] and results["meshes"]:
        armature = None
        mesh_obj = None
        for obj in bpy.data.objects:
            if obj.type == 'ARMATURE':
                armature = obj
            if obj.type == 'MESH' and any(m.type == 'ARMATURE' for m in obj.modifiers):
                mesh_obj = obj
        
        if armature and mesh_obj:
            # Temporarily set to POSE mode for test
            original_pose = armature.data.pose_position
            armature.data.pose_position = 'POSE'
            
            # Set first available action
            if bpy.data.actions and armature.animation_data:
                test_action = bpy.data.actions[0]
                armature.animation_data.action = test_action
                
                # Mute NLA
                if armature.animation_data.nla_tracks:
                    for track in armature.animation_data.nla_tracks:
                        track.mute = True
                
                scene = bpy.context.scene
                test_frames = [int(test_action.frame_range[0]), int(test_action.frame_range[1])]
                
                vertex_positions = {}
                for frame in test_frames:
                    scene.frame_set(frame)
                    bpy.context.view_layer.update()
                    depsgraph = bpy.context.evaluated_depsgraph_get()
                    eval_obj = mesh_obj.evaluated_get(depsgraph)
                    
                    # Sample first 10 and some leg vertices
                    positions = []
                    for i in [0, 1, 2, len(eval_obj.data.vertices)//2]:
                        if i < len(eval_obj.data.vertices):
                            v = eval_obj.data.vertices[i]
                            co = eval_obj.matrix_world @ v.co
                            positions.append([round(co.x, 4), round(co.y, 4), round(co.z, 4)])
                    vertex_positions[frame] = positions
                
                # Check if vertices moved
                f1, f2 = test_frames
                moved = vertex_positions[f1] != vertex_positions[f2]
                
                results["vertex_deformation_test"] = {
                    "action_tested": test_action.name,
                    "frames_tested": test_frames,
                    "vertices_moved": moved,
                    "frame_1_positions": vertex_positions[f1],
                    "frame_2_positions": vertex_positions[f2]
                }
                
                if not moved:
                    results["issues"].append("Vertex deformation test FAILED - vertices not moving between frames")
                    results["status"] = "error"
            
            # Restore original pose position
            armature.data.pose_position = original_pose

    return results

# Run and output
results = run_diagnostics()
print("=== DIAGNOSTIC_JSON_START ===")
print(json.dumps(results, indent=2))
print("=== DIAGNOSTIC_JSON_END ===")
'''
