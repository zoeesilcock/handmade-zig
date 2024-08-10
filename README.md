# Handmade Zig

Learning Zig by following along with the [Handmade Hero](https://handmadehero.org/) series of videos by Casey Muratori.


## Assets
Graphical assets are not included as they are not created by me. They need to be added to the `data/` directory manually. We currently expect the `test` and `test2` directories of assets found in this location of the pre-order data: `handmade_hero_legacy_art.zip/early_data`.

## Debugging
The included debugger config under `.vscode/launch.json` is compatible with the [nvim-dap plugin](https://github.com/mfussenegger/nvim-dap) in Neovim and the [C/C++ extension](https://github.com/Microsoft/vscode-cpptools) in VS Code.

When running outside of an IDE, `OutputDebugString` messages can be viewed using [DebugView](https://learn.microsoft.com/en-us/sysinternals/downloads/debugview).

## Build options
* Timing: use the `-Dtiming` flag when building to enable printing timing (ms/frame, fps and cycles/frame) to the debug output.

## Reference

### Intel
* https://www.intel.com/content/www/us/en/docs/intrinsics-guide
* https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html

### AMD
* https://learn.microsoft.com/en-us/cpp/intrinsics/x64-amd64-intrinsics-list?view=msvc-170
* https://www.amd.com/content/dam/amd/en/documents/processor-tech-docs/programmer-references/24592.pdf
