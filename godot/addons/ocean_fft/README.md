# ocean_fft (vendored)

FFT ocean wave pipeline (JONSWAP/TMA spectra, Stockham FFT compute shaders, displacement/normal/foam maps)
taken from **2Retr0/GodotOceanWaves** (MIT, (c) 2024 Ethan Truong): https://github.com/2Retr0/GodotOceanWaves
See `LICENSE`.

Local modifications:
- shader paths point to `res://addons/ocean_fft/shaders/compute/`
- the displacement map texture has `TEXTURE_USAGE_CAN_COPY_FROM_BIT` so the CPU can read it back (buoyancy).
The rendering side (clipmap, water shader, wake, spray, shallows) lives in `res://scripts` / `res://shaders`.
- push constants are sent with their exact size (Godot 4.7 rejects the 16-byte padded blocks)
- separate descriptor set for the modulate pass (read-only spectrum image), required by Godot 4.7 validation
