# flux.swift.cli

# FLUX.1 Image Generation Tool

## Overview

`flux.swift.cli` is a command-line interface (CLI) tool for generating images based on text prompts using the FLUX.1 model.

## Features

- **Text-to-image generation**: Generate images from text prompts.
- **Customizable parameters**: Control image size, inference steps, guidance scale, and more.
- **Model optimization**: Options for quantization and float16 precision.
- **Multiple model support**: Choose between FLUX.1 Schnell and FLUX.1 Dev models.

## Installation

Download the latest release from the [Releases](https://github.com/mzbac/flux.swift.cli/releases/tag/0.0.1) page as a `.zip` file and extract it to your desired location.

## Usage

Once extracted, run `flux.swift.cli` via the command line:

```bash
./flux --prompt "A cat is sitting on a tree" --width 512 --height 512 --steps 4 --guidance 3.5 --output output_image.png --quantize
```
![Cat on a tree](images/cat_on_tree.png)

## Options

```bash
--prompt <prompt>       # The text prompt to generate an image from (default: "A cat is sitting on a tree")
--width <width>         # Image width (default: 512)
--height <height>       # Image height (default: 512)
--steps <steps>         # Number of inference steps (default: 4)
--guidance <scale>      # Guidance scale (default: 3.5)
--output <path>         # Output image path (default: "output_image.png")
--repo <repository>     # FLUX model repository (default: "black-forest-labs/FLUX.1-schnell")
--seed <seed>           # Random seed for generation (default: 2)
--quantize              # Enable model quantization
--float16               # Enable float16 precision (default: true)
--model <type>          # FLUX model type: "schnell" or "dev" (default: "schnell")
--hf-token <token>      # Hugging Face API token (required for dev model)
```

## Model Types

- **FLUX.1 Schnell**: The default model, optimized for faster inference.
- **FLUX.1 Dev**: A non commercial model that requires a Hugging Face API token.

### Using FLUX.1 Dev Model

To use the FLUX.1 Dev model, you need a Hugging Face API token with "Read access to contents of all public gated repos you can access" permission. Use the `--model dev` and `--hf-token` options:

```bash
./flux --model dev --hf-token YOUR_HF_TOKEN --prompt "Your prompt here"
```

## Examples

1. Generate an image using the default FLUX.1 Schnell model:

```bash
./flux --prompt "A futuristic cityscape" --width 1024 --height 1024 --steps 10 --guidance 5.0 --output futuristic_city.png --quantize
```
![Futuristic cityscape](images/futuristic_city.png)

2. Generate an image using the FLUX.1 Dev model:

```bash
./flux --model dev --hf-token YOUR_HF_TOKEN --prompt "An alien landscape" --width 768 --height 768 --steps 20 --guidance 5.0 --output alien_landscape.png --quantize
```
![Alien landscape](images/alien_landscape.png)
3. Quick try with minimal parameters:

```bash
./flux --prompt "A serene mountain lake" --quantize
```
![Serene mountain lake](images/serene_mountain_lake.png)

