# SwapDotz Image Generation Script

This script generates AI images for all 27 marketplace SwapDots using various AI image generation services.

## 🚀 Quick Start

### 1. Install Dependencies
```bash
pip install -r requirements.txt
```

### 2. Create Placeholder Images (for testing)
```bash
python generate_swapdot_images.py --placeholder
```

### 3. Generate with OpenAI DALL-E
```bash
python generate_swapdot_images.py --api-key YOUR_OPENAI_API_KEY --model dalle
```

### 4. Generate with Stability AI
```bash
python generate_swapdot_images.py --api-key YOUR_STABILITY_API_KEY --model stability
```

## 📋 Usage Options

### Generate All Images
```bash
python generate_swapdot_images.py --api-key YOUR_API_KEY --model dalle
```

### Generate Specific Category
```bash
python generate_swapdot_images.py --api-key YOUR_API_KEY --model dalle --category celebrity
python generate_swapdot_images.py --api-key YOUR_API_KEY --model dalle --category branded
python generate_swapdot_images.py --api-key YOUR_API_KEY --model dalle --category regular
```

### Create Placeholder Images
```bash
python generate_swapdot_images.py --placeholder
```

## 🔧 Supported Models

### 1. OpenAI DALL-E 3
- **Quality**: Highest quality, most consistent
- **Cost**: ~$0.04 per image
- **API Key**: Get from [OpenAI Platform](https://platform.openai.com/)

### 2. Stability AI (Stable Diffusion XL)
- **Quality**: High quality, more artistic
- **Cost**: ~$0.02 per image
- **API Key**: Get from [Stability AI](https://platform.stability.ai/)

### 3. Midjourney (Coming Soon)
- **Quality**: Very high quality, artistic
- **Cost**: Varies
- **API Key**: Not yet implemented

## 📁 Output Structure

```
assets/marketplace_images/
├── celebrity/
│   ├── michael_jordan_legacy.png
│   ├── lebron_james_crown.png
│   └── ...
├── branded/
│   ├── mcdonalds_grimace.png
│   ├── pepsi_classic.png
│   └── ...
├── regular/
│   ├── cool_blue_swapdot.png
│   ├── golden_phoenix.png
│   └── ...
└── README.md
```

## 🎨 Image Specifications

- **Format**: PNG with transparent background
- **Size**: 1024x1024 pixels (AI generated)
- **Style**: Circular token design
- **Quality**: High-resolution, professional grade
- **Naming**: Descriptive names with category prefixes

## 💰 Cost Estimation

### OpenAI DALL-E 3
- **27 images**: ~$1.08
- **Per category**: ~$0.36

### Stability AI
- **27 images**: ~$0.54
- **Per category**: ~$0.18

## 🔄 Integration with Flutter App

After generating images, update the marketplace items in `lib/main.dart`:

```dart
// Replace emoji with actual image
Image.asset('assets/marketplace_images/celebrity/michael_jordan_legacy.png')
```

## 🛠️ Troubleshooting

### Common Issues

1. **API Key Error**
   ```
   ❌ OpenAI API key required for DALL-E generation
   ```
   - Get API key from respective platform
   - Ensure key has image generation permissions

2. **Rate Limiting**
   ```
   ❌ Error: Rate limit exceeded
   ```
   - Script includes 2-second delays between requests
   - For high-volume, increase delay in script

3. **PIL Import Error**
   ```
   ⚠️ PIL not available, creating empty file
   ```
   - Install Pillow: `pip install Pillow`

### Tips

- **Test with placeholders first**: Use `--placeholder` to test the script
- **Generate in batches**: Use `--category` to generate one category at a time
- **Check existing files**: Script skips existing images automatically
- **Monitor costs**: Check your API usage dashboard

## 📊 Generation Status

- [x] Script created
- [x] All 27 prompts defined
- [x] Multiple AI model support
- [x] Placeholder generation
- [ ] Actual AI generation (requires API keys)
- [ ] Flutter app integration

## 🎯 Next Steps

1. **Get API keys** from OpenAI or Stability AI
2. **Generate images** using the script
3. **Update Flutter app** to use real images
4. **Test marketplace** with actual SwapDot images 