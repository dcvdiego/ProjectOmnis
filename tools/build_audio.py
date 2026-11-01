#!/usr/bin/env python3
"""Builds game/assets/audio/ from CC0 source recordings plus procedural sounds.

The generated .ogg files are committed, so nobody needs to run this to play.
It documents exactly how every sound was made and lets anyone rebuild or
re-cut them. Needs Python 3 with numpy, and ffmpeg on PATH.

    python3 tools/build_audio.py SOURCE_DIR

SOURCE_DIR must contain the unpacked downloads listed in SOURCES (all CC0, see
CREDITS.md). Sounds in PROCEDURAL are synthesised here from seeded noise and
sine waves (no samples, no AI).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "assets" / "audio"
SR = 48000

# Where each source came from (all CC0 1.0).
SOURCES = {
	"ffsl": "The Free Firearm Sound Library, 'Prepared SFX Library.7z' — https://opengameart.org/content/the-free-firearm-sound-library (freefirearmsfx.com)",
	"fantozzi": "Fantozzi's Footsteps, Fantozzi-footsteps.7z — https://opengameart.org/content/fantozzis-footsteps-grasssand-stone",
	"metalsteps": "Metal footsteps on concrete by Thimras, metal_steps_48k24b.7z — https://opengameart.org/content/metal-footsteps-on-concrete",
	"leather": "Footsteps (leather, cloth, armor), footsteps.zip — https://opengameart.org/content/footsteps-leather-cloth-armor",
	"sfx100": "100 CC0 SFX #2 by rubberduck, sfx_100_v2.zip — https://opengameart.org/content/100-cc0-sfx-2",
	"bmaczero": "Metal Impact Sounds / Gun Reload Sound Effects by BMacZero — https://opengameart.org/content/metal-impact-sounds, https://opengameart.org/content/gun-reload-sound-effects",
	"springyspringo": "Gun Reload Sounds by SpringySpringo — https://opengameart.org/content/gun-reload-sounds",
}

FFSL = "ffsl/Prepared SFX Library"
# (output, source file, channels, [shot onsets in seconds] or None, length s)
GUNSHOTS = [
	# Near-distance single shots, stereo: what the shooter hears.
	("weapons/ak47_shot", f"{FFSL}/AK-47/C_28P.wav", 2, [0.61, 3.26, 6.02, 9.16], 1.3),
	("weapons/m1911_shot", f"{FFSL}/1911/A_42P.wav", 2, [0.94, 5.00], 1.3),
	# Mid-distance takes, mono: other players' guns (positional).
	("weapons/ak47_shot_far", f"{FFSL}/AK-47/C_31P.wav", 1, [0.34, 4.40], 1.6),
	("weapons/m1911_shot_far", f"{FFSL}/1911/A_34P.wav", 1, [1.54, 6.65], 1.6),
]
# (output, source file, channels, peak dBFS)
CLIPS = [
	("weapons/rifle_reload", "springyspringo/assaultriflereload1_0.wav", 1, -3.0),
	("weapons/pistol_reload", "springyspringo/gunreload1.wav", 1, -3.0),
	("weapons/weapon_switch", "bmaczero/clipload1.wav", 1, -6.0),
	("weapons/dry_fire", "bmaczero/clipload2.wav", 1, -6.0),
	("impacts/concrete_1", "sfx100/sfx100v2_stones_01.ogg", 1, -3.0),
	("impacts/concrete_2", "sfx100/sfx100v2_stones_02.ogg", 1, -3.0),
	("impacts/metal_1", "bmaczero/clink1_0.wav", 1, -3.0),
	("impacts/metal_2", "bmaczero/clink2.wav", 1, -3.0),
	("impacts/metal_3", "bmaczero/clink3.wav", 1, -3.0),
	("impacts/flesh_1", "sfx100/sfx100v2_hit_01.ogg", 1, -3.0),
	("impacts/flesh_2", "sfx100/sfx100v2_hit_02.ogg", 1, -3.0),
	("impacts/body_fall", "bmaczero/thud2.wav", 1, -3.0),
]
for i, side in enumerate(["L1", "R1", "L2", "R2", "L3", "R3"]):
	CLIPS.append((f"footsteps/concrete_{i + 1}", f"fantozzi/Fantozzi-footsteps/flac/Fantozzi-Stone{side}.flac", 1, -6.0))
for i in range(6):
	CLIPS.append((f"footsteps/metal_{i + 1}", f"metalsteps/metal_steps_{i + 1:02d}.wav", 1, -6.0))
for i, name in enumerate(["step_cloth1", "step_cloth2", "step_cloth3", "step_cloth4"]):
	CLIPS.append((f"footsteps/gear_{i + 1}", f"leather/footsteps/{name}.ogg", 1, -10.0))


def load(path: Path, channels: int) -> np.ndarray:
	raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", str(channels), "-ar", str(SR),
		"-f", "f32le", "-"], capture_output=True, check=True).stdout
	return np.frombuffer(raw, dtype=np.float32).reshape(-1, channels).copy()


def write(name: str, x: np.ndarray, quality: int = 5) -> None:
	dest = OUT / f"{name}.ogg"
	dest.parent.mkdir(parents=True, exist_ok=True)
	x = np.atleast_2d(x.T).T if x.ndim == 1 else x
	subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", str(x.shape[1]), "-i", "-",
		"-c:a", "libvorbis", "-q:a", str(quality), str(dest)], input=x.astype(np.float32).tobytes(), check=True)
	print(f"  {dest.relative_to(ROOT)} ({dest.stat().st_size // 1024} KiB)")


def normalize(x: np.ndarray, peak_db: float) -> np.ndarray:
	peak = float(np.abs(x).max())
	return x * (10 ** (peak_db / 20) / peak) if peak > 0 else x


def trim(x: np.ndarray, threshold_db: float = -50.0) -> np.ndarray:
	"""Drops leading/trailing silence and adds short fades so nothing clicks."""
	level = np.abs(x).max(axis=1)
	loud = np.where(level > 10 ** (threshold_db / 20) * level.max())[0]
	if len(loud) == 0:
		return x
	x = x[max(loud[0] - int(0.002 * SR), 0):loud[-1] + 1]
	return fade(x, 0.002, min(0.03, len(x) / SR / 4))


def fade(x: np.ndarray, fade_in: float, fade_out: float) -> np.ndarray:
	n_in, n_out = int(fade_in * SR), int(fade_out * SR)
	env = np.ones(len(x))
	if n_in:
		env[:n_in] = np.linspace(0, 1, n_in)
	if n_out:
		env[-n_out:] *= np.linspace(1, 0, n_out) ** 2
	return x * env[:, None]


def build_sources(src: Path) -> None:
	for name, file, channels, onsets, length in GUNSHOTS:
		x = load(src / file, channels)
		for i, t in enumerate(onsets):
			start = int(max(t - 0.004, 0) * SR)
			shot = x[start:start + int(length * SR)]
			write(f"{name}_{i + 1}", normalize(fade(shot, 0.001, length * 0.6), -1.0))
	for name, file, channels, peak in CLIPS:
		write(name, normalize(trim(load(src / file, channels)), peak))


# --- Procedural sounds -----------------------------------------------------------

def _noise(seconds: float, seed: int) -> np.ndarray:
	return np.random.default_rng(seed).standard_normal(int(seconds * SR))


def _bandpass(x: np.ndarray, low: float, high: float) -> np.ndarray:
	f = np.fft.rfftfreq(len(x), 1 / SR)
	X = np.fft.rfft(x)
	X[(f < low) | (f > high)] = 0
	return np.fft.irfft(X, len(x))


def _loop(x: np.ndarray, crossfade: float = 0.25) -> np.ndarray:
	"""Makes a seamless loop by crossfading the tail into the head."""
	n = int(crossfade * SR)
	head, body, tail = x[:n], x[n:-n], x[-n:]
	ramp = np.linspace(0, 1, n)
	return np.concatenate([tail * (1 - ramp) + head * ramp, body])


def build_procedural() -> None:
	t = lambda s: np.arange(int(s * SR)) / SR
	# Hit marker: two quick high ticks.
	tt = t(0.07)
	tick = np.sin(2 * np.pi * 2600 * tt) * np.exp(-tt * 90) + 0.4 * np.sin(2 * np.pi * 5200 * tt) * np.exp(-tt * 140)
	write("ui/hit_marker", normalize(tick, -6.0))
	# Kill confirm: lower, longer tick.
	tt = t(0.18)
	kill = np.sin(2 * np.pi * 1500 * tt) * np.exp(-tt * 30) + 0.5 * np.sin(2 * np.pi * 2250 * tt) * np.exp(-tt * 40)
	write("ui/kill_confirm", normalize(kill, -6.0))
	# Wind rush at speed: low/mid filtered noise with slow movement, looped.
	n = _bandpass(_noise(4.0, 1), 120, 1800)
	wobble = 0.75 + 0.25 * np.sin(2 * np.pi * 0.5 * t(4.0)) * np.sin(2 * np.pi * 0.23 * t(4.0) + 1.0)
	write("movement/wind_loop", normalize(_loop(n * wobble), -6.0))
	# Slide scrape: gritty band-passed noise with fast random amplitude, looped.
	n = _bandpass(_noise(2.0, 2), 700, 5000)
	grit = np.abs(_bandpass(_noise(2.0, 3), 5, 40))
	write("movement/slide_loop", normalize(_loop(n * (0.4 + grit / grit.max())), -6.0))
	# Jump-jet puff (double jump / wall kick): a short swept noise burst.
	tt = t(0.4)
	n = _noise(0.4, 4)
	sweep = np.concatenate([_bandpass(n[i:i + 960], 300 + 3000 * (i / len(n)), 2500 + 4000 * (i / len(n)))
		for i in range(0, len(n), 960)])[:len(tt)]
	env = np.minimum(tt / 0.02, 1) * np.exp(-tt * 9)
	write("movement/jump_jet", normalize(sweep * env, -4.0))
	# Landing thump: low sine drop plus a little noise.
	tt = t(0.3)
	thump = np.sin(2 * np.pi * (90 - 50 * tt / 0.3) * tt) * np.exp(-tt * 18) + 0.15 * _bandpass(_noise(0.3, 5), 80, 600) * np.exp(-tt * 30)
	write("movement/land_thump", normalize(thump, -3.0))


def main(argv: list[str]) -> None:
	if not argv:
		print(__doc__)
		for key, desc in SOURCES.items():
			print(f"  {key}/  {desc}")
		raise SystemExit(1)
	build_sources(Path(argv[0]))
	build_procedural()


if __name__ == "__main__":
	main(sys.argv[1:])
