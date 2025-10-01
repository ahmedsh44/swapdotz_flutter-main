#!/usr/bin/env python3
"""
Generate better celebration MP4 videos with more dramatic effects
"""

import subprocess
import os
import math
import random

def create_dramatic_celebration_video(rarity, output_path):
    """Create celebration video with more dramatic and visible effects"""
    
    # Video specifications
    duration = 2.0  # seconds
    fps = 30
    width, height = 720, 1280
    
    # Rarity-specific effects
    if rarity == 'common':
        bg_color = '#1a1a2e'
        primary_color = '#32CD32'  # Green
        secondary_color = '#90EE90'
        particle_count = 50
        particle_size = 12
        speed_multiplier = 1.0
    elif rarity == 'uncommon':
        bg_color = '#1a1a2e'
        primary_color = '#4A90E2'  # Blue
        secondary_color = '#00CED1'
        particle_count = 100
        particle_size = 16
        speed_multiplier = 1.5
    else:  # rare
        bg_color = '#1a1a2e'
        primary_color = '#FF6B35'  # Orange
        secondary_color = '#FFD700'
        particle_count = 150
        particle_size = 20
        speed_multiplier = 2.0
    
    # Generate particles with dramatic movement
    particles = []
    center_x, center_y = width // 2, height // 3
    
    for i in range(particle_count):
        # Random starting position near center
        start_x = center_x + random.randint(-100, 100)
        start_y = center_y + random.randint(-50, 50)
        
        # Explosive outward movement
        angle = random.uniform(0, 2 * math.pi)
        distance = random.uniform(200, 400) * speed_multiplier
        end_x = start_x + math.cos(angle) * distance
        end_y = start_y + math.sin(angle) * distance
        
        # Keep within bounds
        end_x = max(0, min(width, end_x))
        end_y = max(0, min(height, end_y))
        
        color = primary_color if i % 3 != 0 else secondary_color
        size = particle_size + random.randint(-4, 4)
        
        particles.append({
            'start_x': start_x,
            'start_y': start_y,
            'end_x': end_x,
            'end_y': end_y,
            'color': color,
            'size': size
        })
    
    # Create FFmpeg filter with dramatic particle animations
    filters = []
    
    # Base background
    filters.append(f"color=c={bg_color}:s={width}x{height}:d={duration}:r={fps}[bg]")
    
    # Create particles with movement
    for i, particle in enumerate(particles):
        # Create particle
        filters.append(f"color=c={particle['color']}:s={particle['size']}x{particle['size']}:d={duration}:r={fps}[p{i}]")
        
        # Animate position with easing
        x_expr = f"{particle['start_x']}+({particle['end_x']}-{particle['start_x']})*easeout(t/{duration})"
        y_expr = f"{particle['start_y']}+({particle['end_y']}-{particle['start_y']})*easeout(t/{duration})"
        
        # Animate opacity (fade out)
        alpha_expr = f"1-t/{duration}"
        
        if i == 0:
            input_name = "bg"
        else:
            input_name = f"tmp{i-1}"
            
        overlay_filter = f"[{input_name}][p{i}]overlay=x='{x_expr}':y='{y_expr}':alpha='{alpha_expr}':eval=frame[tmp{i}]"
        filters.append(overlay_filter)
    
    # Final output
    final_output = f"tmp{len(particles)-1}" if particles else "bg"
    
    # Build complete filter
    filter_complex = ";".join(filters)
    
    # FFmpeg command with high quality settings
    cmd = [
        'ffmpeg', '-y',
        '-f', 'lavfi',
        '-i', f'color=c={bg_color}:s={width}x{height}:d={duration}:r={fps}',
        '-filter_complex', filter_complex,
        '-map', f'[{final_output}]',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-crf', '15',  # Very high quality
        '-preset', 'slow',  # Better compression
        '-movflags', '+faststart',
        '-r', str(fps),
        output_path
    ]
    
    print(f"Generating DRAMATIC {rarity} celebration video with {particle_count} particles...")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.returncode == 0:
            print(f"✅ Successfully created {output_path}")
            file_size = os.path.getsize(output_path) / 1024  # KB
            print(f"   File size: {file_size:.1f} KB")
            return True
        else:
            print(f"❌ FFmpeg error: {result.stderr}")
            return False
    except subprocess.TimeoutExpired:
        print(f"❌ Timeout generating {rarity} video")
        return False
    except FileNotFoundError:
        print("❌ FFmpeg not found. Please install FFmpeg first.")
        return False

def main():
    output_dir = "/home/oliver/Desktop/swapdotz_flutter/assets/celebration_videos"
    os.makedirs(output_dir, exist_ok=True)
    
    rarities = ['common', 'uncommon', 'rare']
    
    for rarity in rarities:
        output_path = os.path.join(output_dir, f"{rarity}_celebration.mp4")
        success = create_dramatic_celebration_video(rarity, output_path)
        
        if not success:
            print(f"Failed to create {rarity} video")
            return False
    
    print("\n🎉 All DRAMATIC celebration videos generated successfully!")
    print("These videos feature:")
    print("- Large, visible particles (12-20px)")
    print("- Explosive outward movement")
    print("- Rarity-specific colors and particle counts")
    print("- High quality encoding (CRF 15)")
    return True

if __name__ == "__main__":
    main()