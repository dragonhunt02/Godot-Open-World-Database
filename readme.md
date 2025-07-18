# Open World Database (OWDB) for Godot

A Godot addon that enables efficient streaming and persistence of large 3D open worlds through automatic chunk-based loading and hierarchical scene management.

## Overview

Creating large open worlds in Godot can quickly become a performance nightmare. With hundreds or thousands of nodes scattered across your map - NPCs, buildings, props, AI entities - your scene can grind to a halt as memory usage explodes and the engine struggles to process everything simultaneously.

**Open World Database** solves this by automatically managing your world content through intelligent chunking and streaming. Simply drop your scene nodes under the main OWDB node, and the system handles the rest - no complex setup, no workflow changes, just seamless integration with Godot's existing editor structure.

## Key Features

- **Automatic Chunk Management**: Dynamically loads/unloads content based on camera position
- **Size-Based Optimization**: Different chunk sizes for different object categories (small props use fine-grained chunks, large buildings use bigger chunks)
- **Seamless Editor Integration**: Works directly with Godot's scene system - just parent nodes to the OWDB node
- **Persistent World State**: Automatically saves world data to `.owdb` files alongside your scenes
- **Hierarchical Preservation**: Maintains parent-child relationships across chunk boundaries
- **Custom Property Support**: Preserves all node properties and metadata during streaming
- **Memory Efficient**: Only keeps nearby content in memory, dramatically reducing resource usage

## Installation

1. Download or clone this repository
2. Copy the `addons/open_world_database` folder to your project's `addons/` directory
3. Enable the plugin in Project Settings > Plugins

## Quick Start

1. Add an `OpenWorldDatabase` node to your scene
2. Parent all your world content (NPCs, buildings, props, etc.) under this node
3. The system automatically assigns unique IDs and begins tracking your content
4. Save your scene - the addon creates a `.owdb` file with all world data
5. During gameplay, content streams in and out based on camera position

```gdscript
# Optional: Set a custom camera for chunk loading
$OpenWorldDatabase.camera = $Player/Camera3D

# Optional: Adjust chunk loading range
$OpenWorldDatabase.chunk_load_range = 5  # Load 5 chunks in each direction
```

## How It Works

The addon monitors all nodes with scene files under the OWDB node, categorizing them by size:
- **Small** (≤0.5 units): Fine-grained 8x8 unit chunks
- **Medium** (≤2.0 units): 16x16 unit chunks  
- **Large** (≤8.0 units): 64x64 unit chunks
- **Huge** (>8.0 units): No chunking (always loaded)

As your camera moves through the world, the system automatically:
1. Unloads chunks that are too far away
2. Loads new chunks coming into range
3. Maintains proper hierarchical relationships
4. Preserves all node properties and transformations

## Configuration

The `OpenWorldDatabase` node exposes several configuration options:

- `size_thresholds`: Boundaries for object size categories
- `chunk_sizes`: Chunk dimensions for each size category
- `chunk_load_range`: How many chunks to load around the camera
- `debug_enabled`: Enable debug output
- `camera`: Custom camera node (auto-detected if not set)

## Roadmap

- **Child OWDB Support**: Nested OWDB nodes for complex scenes (e.g., furniture within buildings that can be independently chunked)
- **Async Loading**: Background loading to eliminate hitches
- **Compression**: Optional compression for `.owdb` files
- **Streaming Optimization**: Predictive loading based on movement direction
- **Multi-threading**: Parallel chunk processing for better performance

## Performance Benefits

Before OWDB:
- 10,000 nodes = 10,000 nodes in memory always
- Frame rate drops with scene complexity
- Memory usage grows linearly with world size

After OWDB:
- 10,000 nodes = ~100-500 nodes in memory (depending on chunk range)
- Consistent frame rates regardless of world size
- Memory usage stays constant based on loaded area

## License

MIT License

Copyright (c) 2024 Open World Database Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Contributing

Contributions are welcome! Please feel free to submit pull requests, report bugs, or suggest features.

## Support

If you encounter issues or have questions, please open an issue on the GitHub repository.

---

*Transform your Godot projects from small scenes to massive open worlds without the performance headaches.*