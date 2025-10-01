# Marketplace Images Folder

This folder contains AI-generated images for SwapDotz marketplace items.

## Folder Structure

```
assets/marketplace_images/
├── celebrity/           # Celebrity/Ownership SwapDots
├── branded/            # Branded SwapDots  
├── regular/            # Regular Marketplace SwapDots
└── image_prompts.md    # AI generation prompts
```

## Image Requirements

- **Format**: PNG with transparent background
- **Size**: 512x512 pixels minimum
- **Style**: Circular token design
- **Quality**: High-resolution, professional grade

## Naming Convention

- `celebrity_michael_jordan_legacy.png`
- `branded_mcdonalds_grimace.png`
- `regular_ocean_wave.png`

## Usage in App

Images will be loaded dynamically in the marketplace using:
```dart
Image.asset('assets/marketplace_images/celebrity_michael_jordan_legacy.png')
```

## Generation Status

- [ ] Celebrity/Ownership images (12 items)
- [ ] Branded images (7 items)  
- [ ] Regular marketplace images (8 items)

Total: 27 unique SwapDot designs needed 