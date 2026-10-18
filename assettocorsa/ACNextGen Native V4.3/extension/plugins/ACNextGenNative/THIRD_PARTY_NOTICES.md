# Third-party sources

- `third_party/json.hpp`: nlohmann/json 3.12.0, Copyright 2013–2025 Niels Lohmann, MIT. License text is in `third_party/LICENSE-json.txt`. Source: https://github.com/nlohmann/json/tree/v3.12.0
- `reference/sim_info.py`: Original AC shared-memory definitions from https://github.com/ac-custom-shaders-patch/acc-extension-apps/blob/master/apps/python/AccExtHelper/sim_info.py . The source retains its attribution to Rombik and its permission statement. `include/ac_shared_memory.h` is generated from those field definitions.
- `reference/*.lua`: pinned ACNextGen model sources used for translation and equivalence tests. They are never loaded by the production DLL.
- Build-time packages: luaparser 4.2.0 and Lupa 2.6 are installed separately with pip. Python, Zig, and their toolchains are not vendored in this repository.

This notice does not assign a new license to ACNextGen's own sources. No Assetto Corsa binaries or third-party car model, texture, sound, or physics data are included.
