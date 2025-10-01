#!/usr/bin/env python3
"""
Generate app icons from SwapDotz logo for Android and iOS
"""

import os
from PIL import Image, ImageDraw
import math

def create_circular_icon(input_path, output_path, size):
    """Create a circular app icon from the input image"""
    try:
        # Open the input image
        img = Image.open(input_path)
        
        # Convert to RGBA if not already
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        
        # Resize to the target size
        img = img.resize((size, size), Image.Resampling.LANCZOS)
        
        # Create a circular mask
        mask = Image.new('L', (size, size), 0)
        draw = ImageDraw.Draw(mask)
        draw.ellipse((0, 0, size, size), fill=255)
        
        # Apply the mask
        output = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        output.paste(img, (0, 0))
        output.putalpha(mask)
        
        # Save the output
        output.save(output_path, 'PNG')
        print(f"Generated {output_path}")
        return True
    except Exception as e:
        print(f"Error generating {output_path}: {e}")
        return False

def main():
    # Input logo file
    input_logo = "swapdotz_possible_logo_no_bg.png"
    
    if not os.path.exists(input_logo):
        print(f"Error: {input_logo} not found!")
        return
    
    # Android icon sizes
    android_sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }
    
    # iOS icon sizes
    ios_sizes = {
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
        'Icon-App-1024x1024@1x.png': 1024,
    }
    
    # Generate Android icons
    print("Generating Android app icons...")
    for folder, size in android_sizes.items():
        output_path = f"android/app/src/main/res/{folder}/ic_launcher.png"
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        create_circular_icon(input_logo, output_path, size)
    
    # Generate iOS icons
    print("Generating iOS app icons...")
    for filename, size in ios_sizes.items():
        output_path = f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{filename}"
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        create_circular_icon(input_logo, output_path, size)
    
    print("App icon generation complete!")

if __name__ == "__main__":
    main() 