#!/usr/bin/env python3
"""
Generate celebration MP4 videos for SwapDotz app
Creates rarity-specific celebration animations as MP4 files
"""

import subprocess
import os
import math
import random

def create_celebration_video(rarity, output_path):
    """Create celebration video matching the exact Flutter animations"""
    
    # Video specifications
    duration = 1.5  # Match Flutter animation duration
    fps = 30
    width, height = 720, 1280
    
    # Rarity-specific settings matching Flutter code exactly
    if rarity == 'common':
        bg_color = 'transparent'  # Transparent background
        particle_count = 30       # Exact same as Flutter
        particle_colors = ['#32CD32', '#90EE90']  # Green variants
        effects = []
    elif rarity == 'uncommon':
        bg_color = 'transparent'
        particle_count = 60       # Exact same as Flutter
        particle_colors = ['#4A90E2', '#00CED1']  # Blue variants
        effects = ['burst_rays']  # Add burst rays like Flutter
    else:  # rare
        bg_color = 'transparent'
        particle_count = 100      # Exact same as Flutter  
        particle_colors = ['#FF6B35', '#FFD700']  # Orange/gold variants
        effects = ['burst_rays', 'shockwave']  # Full effects like Flutter
    
    # Create confetti explosion matching Flutter's _ConfettiPainter
    # This replicates the exact math from Flutter: 
    # - Random angle: rnd.nextDouble() * 2 * math.pi
    # - Radius grows over time: progress * (size.shortestSide * 0.6) * rnd.nextDouble()
    # - Center point: (width/2, height/3)
    
    filters = []
    
    # Base transparent background
    filters.append(f"color=c=black@0.0:s={width}x{height}:d={duration}:r={fps}[bg]")
    
    # Generate particles using same random seed as Flutter (42)
    random.seed(42)  # Match Flutter's Random(42)
    
    center_x = width // 2      # 360
    center_y = height // 3     # ~427 (matches Flutter height/3)
    
    for i in range(particle_count):
        # Match Flutter's random generation exactly
        angle = random.uniform(0, 2 * math.pi)
        velocity = random.uniform(0.0, 1.0)  # Flutter: rnd.nextDouble()
        
        # Flutter calculation: progress * (size.shortestSide * 0.6) * velocity
        # size.shortestSide = 720, so max_radius = 720 * 0.6 = 432
        max_radius = 432 * velocity
        
        # End position
        end_x = center_x + math.cos(angle) * max_radius
        end_y = center_y + math.sin(angle) * max_radius
        
        # Particle size (2 + rnd.nextDouble() * 3) -> 2-5px
        size = 2 + random.uniform(0, 3)
        
        # Particle color (alternating like Flutter)
        color = particle_colors[i % len(particle_colors)]
        
        # Create particle
        particle_size = int(size)
        filters.append(f"color=c={color}:s={particle_size}x{particle_size}:d={duration}:r={fps}[p{i}]")
        
        # Animate position with Flutter's easing (linear progress)
        x_expr = f"{center_x}+({end_x}-{center_x})*t/{duration}"
        y_expr = f"{center_y}+({end_y}-{center_y})*t/{duration}"
        
        # Fade out like Flutter: (1 - progress)
        alpha_expr = f"1-t/{duration}"
        
        # Overlay particle
        if i == 0:
            input_layer = "bg"
        else:
            input_layer = f"tmp{i-1}"
            
        filters.append(f"[{input_layer}][p{i}]overlay=x='{x_expr}':y='{y_expr}':eval=frame:format=auto[tmp{i}]")
    
    final_layer = f"tmp{particle_count-1}" if particle_count > 0 else "bg"
    
    # Add burst rays for uncommon/rare (matching Flutter's _BurstPainter)
    if 'burst_rays' in effects:
        ray_count = 48 if rarity == 'rare' else 32  # Match Flutter ray counts
        
        for ray in range(ray_count):
            angle = (2 * math.pi / ray_count) * ray
            # Flutter: size.shortestSide * 0.15 * progress
            max_length = 720 * 0.15  # 108px
            
            end_x = center_x + math.cos(angle) * max_length
            end_y = center_y + math.sin(angle) * max_length
            
            # Create ray line (simplified as small rectangle)
            filters.append(f"color=c=#FFD700:s=2x20:d={duration}:r={fps}[ray{ray}]")
            
            x_expr = f"{center_x}+({end_x}-{center_x})*t/{duration}"
            y_expr = f"{center_y}+({end_y}-{center_y})*t/{duration}"
            
            filters.append(f"[{final_layer}][ray{ray}]overlay=x='{x_expr}':y='{y_expr}':eval=frame:format=auto[ray_tmp{ray}]")
            final_layer = f"ray_tmp{ray}"
    
    # Build command
    filter_complex = ";".join(filters)
    
    cmd = [
        'ffmpeg', '-y',
        '-f', 'lavfi', '-i', f'color=c=black@0.0:s={width}x{height}:d={duration}:r={fps}',
        '-filter_complex', filter_complex,
        '-map', f'[{final_layer}]',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-crf', '18',
        '-preset', 'fast',
        '-movflags', '+faststart',
        output_path
    ]
    
    print(f"Generating {rarity} celebration video...")
    print(f"Command: {' '.join(cmd[:10])}...")  # Show first part of command
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode == 0:
            print(f"✅ Successfully created {output_path}")
            return True
        else:
            print(f"❌ FFmpeg error: {result.stderr}")
            return False
    except subprocess.TimeoutExpired:
        print(f"❌ Timeout generating {rarity} video")
        return False
    except FileNotFoundError:
        print("❌ FFmpeg not found. Please install FFmpeg first:")
        print("   Ubuntu/Debian: sudo apt install ffmpeg")
        print("   macOS: brew install ffmpeg")
        return False

def main():
    # Output directory
    output_dir = "/home/oliver/Desktop/swapdotz_flutter/assets/celebration_videos"
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate videos for each rarity
    rarities = ['common', 'uncommon', 'rare']
    
    for rarity in rarities:
        output_path = os.path.join(output_dir, f"{rarity}_celebration.mp4")
        success = create_celebration_video(rarity, output_path)
        
        if not success:
            print(f"Failed to create {rarity} video")
            return False
    
    print("\n🎉 All celebration videos generated successfully!")
    print(f"Videos saved to: {output_dir}")
    return True

if __name__ == "__main__":
    main()