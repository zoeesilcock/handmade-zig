# Handmade Zig

Learning Zig by following along with the [Handmade Hero](https://handmadehero.org/) series of videos by Casey Muratori.


## Assets
Graphical assets are not included as they are not created by me. They need to be added to the `data/` directory manually. We currently expect the assets found in this location of the pre-order data: `handmade_hero_legacy_art.zip/v0_hhas`.

### Packing the assets
The asset files need to be packed using the asset packer before running the game. The current version of the asset builder doesn't produce files compatible with the game anymore since we made the reader compatible with asset files created by Casey, use the original files from `handmade_hero_legacy_art.zip/v0_hhas`.
```
zig build build-assets
```

## Debugging
The included debugger config under `.vscode/launch.json` is compatible with the [nvim-dap plugin](https://github.com/mfussenegger/nvim-dap) in Neovim and the [C/C++ extension](https://github.com/Microsoft/vscode-cpptools) in VS Code. Using Visual Studio with C/C++ tooling appears to give the most reliable results. Another alternative that works almost as well as Visual Studio is [Rad Debugger](https://github.com/EpicGamesExt/raddebugger).

When running outside of an IDE, `OutputDebugString` messages can be viewed using [DebugView](https://learn.microsoft.com/en-us/sysinternals/downloads/debugview).

## Build options
* Timing: use the `-Dtiming` flag when building to enable printing timing (ms/frame, fps and cycles/frame) to the debug output.

## Analyzing generated assembly
The build is setup to emit the generated assembly code which can be used to analyze the code for bottlenecks using `llvm-mca` which is bundled with LLVM version 18+.

```
asm volatile("# LLVM-MCA-BEGIN ProcessPixel");
// Code to analyze.
// ...
asm volatile("# LLVM-MCA-END ProcessPixel");
```

Analyze the emitted assembly code:
```
llvm-mca .\zig-out\bin\handmade-dll.asm -bottleneck-analysis -o .\zig-out\bin\handmade-dll-mca.txt
```

## Reference

### Intel
* https://www.intel.com/content/www/us/en/docs/intrinsics-guide
* https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html

### AMD
* https://learn.microsoft.com/en-us/cpp/intrinsics/x64-amd64-intrinsics-list?view=msvc-170
* https://www.amd.com/content/dam/amd/en/documents/processor-tech-docs/programmer-references/24592.pdf

### OpenGL
* https://docs.gl/
* https://registry.khronos.org/OpenGL/api/GL/glcorearb.h
