# Handmade Zig

Learning Zig by following along with the [Handmade Hero](https://handmadehero.org/) series of videos by Casey Muratori. This implementation follows Casey's approach as closely as Zig allows with some minor departures when I want to explore some specific Zig feature (like using `@Vector` to get SIMD vector math for example).

## Running
Since the executable looks for the library in the same directory as the executable the regular `zig build run` approach doesn't work. The easiest solution is to build it first and then launch the built executable (so that it can find the library) with the correct working directory (so that it can find the assets).

PowerShell:
```
zig build ; Start-Process -NoNewWindow -FilePath ./zig-out/bin/handmade-zig.exe -WorkingDirectory ./data
```

## Assets
Graphical assets are not included as they are not created by me. They need to be added to the `data/` directory manually. We currently expect the assets found in this location of the pre-order data: `handmade_hero_legacy_art.zip/v0_hhas`.

### Packing the assets
The asset files need to be packed using the asset packer before running the game. The current version of the asset builder doesn't produce files compatible with the game anymore since we made the reader compatible with asset files created by Casey, use the original files from `handmade_hero_legacy_art.zip/v0_hhas`.
```
zig build build-assets
```

## Hot reloading
The game is split up into an executable for the runtime and a DLL that contains the actual game. This allows hot reloading for most of the game code. When the DLL is rebuilt, the game will automatically reload it.

To make this even more automatic you can run a separate terminal which automatically rebuilds the DLL when you save a file:
```
zig build --watch -Dpackage=Library
```

## Debugging
The included debugger config under `.vscode/launch.json` is compatible with the [nvim-dap plugin](https://github.com/mfussenegger/nvim-dap) in Neovim and the [C/C++ extension](https://github.com/Microsoft/vscode-cpptools) in VS Code. Using regular Visual Studio with C/C++ tooling appears to give the most reliable results. Another alternative that works almost as well as Visual Studio is [Rad Debugger](https://github.com/EpicGamesExt/raddebugger).

When running outside of an IDE, `OutputDebugString` messages can be viewed using [DebugView](https://learn.microsoft.com/en-us/sysinternals/downloads/debugview).


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
* https://www.khronos.org/opengl/wiki/OpenGL_Type
* https://www.khronos.org/files/opengl-quick-reference-card.pdf
* https://www.khronos.org/opengl/wiki/Core_Language_(GLSL)

### General graphics
* https://developer.nvidia.com/gpugems/gpugems3
* https://developer.nvidia.com/gpugems/gpugems2
* https://developer.nvidia.com/gpugems/gpugems
