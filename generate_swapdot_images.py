#!/usr/bin/env python3
"""
SwapDotz Marketplace Image Generator (Local GPU Version)
Generates AI images for all marketplace SwapDots using Stable Diffusion locally with CUDA support.
No API keys or placeholders required.
"""

import os
import time
from pathlib import Path
from typing import Dict, List
import argparse
from diffusers import StableDiffusionPipeline
import torch

class SwapDotImageGenerator:
    def __init__(self, model_path: str = "runwayml/stable-diffusion-v1-5"):
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.pipe = StableDiffusionPipeline.from_pretrained(model_path, torch_dtype=torch.float16 if self.device == "cuda" else torch.float32)
        self.pipe = self.pipe.to(self.device)

        self.output_dir = Path("assets/marketplace_images")
        self.output_dir.mkdir(parents=True, exist_ok=True)

        (self.output_dir / "inspired_by_legends").mkdir(exist_ok=True)
        (self.output_dir / "fantasy_brands").mkdir(exist_ok=True)
        (self.output_dir / "regular").mkdir(exist_ok=True)

        self.marketplace_items = self._load_marketplace_items()

    def _load_marketplace_items(self) -> Dict[str, List[Dict]]:
        items = {
            "inspired_by_legends": [
                {"name": "skywalker_legacy", "display_name": "Skywalker Legacy", "prompt": "A circular token with basketball leather texture, gold trim, heroic profile silhouette, glowing blue aura, floating in space, premium 3D render"},
                {"name": "royal_emblem", "display_name": "Royal Emblem", "prompt": "A regal circular token with crown motif, purple and gold gradient, court texture, radiant light, collectible style"},
                {"name": "mamba_strike", "display_name": "Mamba Strike", "prompt": "A dark circular token with snakeskin texture, glowing number 24, shimmering gold lines, mysterious energy"},
                {"name": "splash_signature", "display_name": "Splash Signature", "prompt": "A vibrant token with blue-yellow gradient, splash water lighting effect, net texture, dynamic and energetic style"},
                {"name": "shadow_reaper", "display_name": "Shadow Reaper", "prompt": "A sleek black token with red gradient edges, number 35 in metallic lettering, spectral reaper figure, intimidating glow"},
                {"name": "olympian_fury", "display_name": "Olympian Fury", "prompt": "A powerful green-and-white token with Greek column textures, number 34, godlike glow, mythological aesthetic"},
                {"name": "euro_magic", "display_name": "Euro Magic", "prompt": "A blue and silver token with sparkling starfield background, number 77, magical floating dust, elegant collectible style"},
                {"name": "card_master", "display_name": "Card Master", "prompt": "A whimsical token with gold/brown gradient, joker face motif, suit symbols, playful yet premium design"},
                {"name": "urban_process", "display_name": "Urban Process", "prompt": "A gritty token with steel texture, blue/red gradient, city skyline etched into edge, powerful energy"},
                {"name": "zero_hour", "display_name": "Zero Hour", "prompt": "A dramatic token with black-red gradient, clock face design, glowing zero numeral, intense lighting"},
                {"name": "retro_flash", "display_name": "Retro Flash", "prompt": "A disco-inspired token with mirrored ball texture, purple-gold tones, number 32, glam vintage style"},
                {"name": "green_floor_general", "display_name": "Green Floor General", "prompt": "A classic token with parquet texture, green-white colors, number 33, old-school basketball heritage"}
            ],
            "fantasy_brands": [
                {"name": "fuzzy_purple_friend", "display_name": "Fuzzy Purple Friend", "prompt": "A fun circular token with fuzzy purple fur texture, smiling blob mascot, cartoonish glow, joyful collectible"},
                {"name": "fizzy_duo_classic", "display_name": "Fizzy Duo Classic", "prompt": "A refreshing blue-red gradient token, fizzy bubble texture, circular logo pattern, clean and crisp"},
                {"name": "high_jump_dream", "display_name": "High Jump Dream", "prompt": "A sporty circular token with red-black leather texture, high-flying athlete silhouette, elite energy"},
                {"name": "vintage_soda_glow", "display_name": "Vintage Soda Glow", "prompt": "A retro token with red-white gradient, glass bottle outline, nostalgic texture, classic appeal"},
                {"name": "urban_runner", "display_name": "Urban Runner", "prompt": "A street-style token with black-white gradient, triple-stripe pattern, bold athletic vibes"},
                {"name": "artisan_reserve", "display_name": "Artisan Reserve", "prompt": "A premium token with roasted bean texture, green-gold gradient, elegant crest, luxury product feel"},
                {"name": "spicy_triangle", "display_name": "Spicy Triangle", "prompt": "A bold token with orange-red gradient, triangle pattern, melted cheese texture, intense snack vibe"}
            ],
            "regular": [
                {"name": "cool_blue_swapdot", "display_name": "Cool Blue SwapDot", "prompt": "A beautiful token with blue gradient, wave patterns, crystal-like texture, peaceful aesthetic"},
                {"name": "golden_phoenix", "display_name": "Golden Phoenix", "prompt": "A mythical token with phoenix feather textures, golden flames, glowing edges, legendary rebirth theme"},
                {"name": "neon_cyber", "display_name": "Neon Cyber", "prompt": "A futuristic token with neon lines, glitch textures, digital grid, cyberpunk glow"},
                {"name": "vintage_basketball", "display_name": "Vintage Basketball", "prompt": "A nostalgic token with aged leather look, classic hoops design, warm tones, old-school style"},
                {"name": "ocean_wave", "display_name": "Ocean Wave", "prompt": "A calming token with ocean gradient, foam wave textures, soothing energy"},
                {"name": "forest_guardian", "display_name": "Forest Guardian", "prompt": "A nature-inspired token with bark textures, leaf patterns, earthy tones, enchanted look"},
                {"name": "sunset_glow", "display_name": "Sunset Glow", "prompt": "A romantic token with orange-pink gradient, sunset haze, soft edges, warm ambiance"},
                {"name": "galaxy_explorer", "display_name": "Galaxy Explorer", "prompt": "A cosmic token with nebula swirls, starfields, deep colors, space traveler design"}
            ]
        }
        return items

    def generate_image(self, prompt: str, output_path: Path) -> bool:
        try:
            image = self.pipe(prompt).images[0]
            image.save(output_path)
            print(f"✅ Generated: {output_path}")
            return True
        except Exception as e:
            print(f"❌ Error generating {output_path}: {e}")
            return False

    def generate_all_images(self, category: str = None) -> None:
        total = 0
        success = 0

        for cat, items in self.marketplace_items.items():
            if category and cat != category:
                continue

            print(f"\n🎨 Generating {cat} tokens...")

            for item in items:
                total += 1
                filename = self.output_dir / cat / f"{item['name']}.png"

                if filename.exists():
                    print(f"⏭️  Skipping existing: {filename}")
                    continue

                if self.generate_image(item['prompt'], filename):
                    success += 1

                time.sleep(1)

        print(f"\n📊 Generation complete: {success}/{total} successful")


def main():
    parser = argparse.ArgumentParser(description="Generate SwapDot marketplace images locally")
    parser.add_argument("--model-path", default="runwayml/stable-diffusion-v1-5", help="Local or HF model path")
    parser.add_argument("--category", choices=["inspired_by_legends", "fantasy_brands", "regular"], help="Optional category to generate")
    args = parser.parse_args()

    generator = SwapDotImageGenerator(model_path=args.model_path)
    generator.generate_all_images(category=args.category)


if __name__ == "__main__":
    main()