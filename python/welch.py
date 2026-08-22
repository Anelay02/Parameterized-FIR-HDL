#!/usr/bin/env python3
# =============================================================================
# File: welch.py
# Description: Observe the Welch window function in time and frequency domain.
# =============================================================================

import numpy as np
import matplotlib.pyplot as plt


# =============================================================================
# 1. PARAMETERS
# =============================================================================

WINDOW_LEN = 256

TIME_PLOT_PATH = "../Img/welch_time.png"
FREQ_PLOT_PATH = "../Img/welch_frequency.png"


# =============================================================================
# Plot styling
# =============================================================================

TEXT_COLOR = "#999999"   # titles, labels, ticks, spines
GRID_COLOR = "#888888"   # gridlines (kept faint via alpha)

WINDOW_COLOR = "#1f77b4" # Welch window / magnitude response

def _style_axes(ax):
    """Apply readable-on-light-and-dark styling to a single Axes."""

    ax.set_facecolor("none")

    ax.title.set_color(TEXT_COLOR)
    ax.xaxis.label.set_color(TEXT_COLOR)
    ax.yaxis.label.set_color(TEXT_COLOR)

    ax.tick_params(axis="both", colors=TEXT_COLOR)

    for spine in ax.spines.values():
        spine.set_color(TEXT_COLOR)

    ax.grid(alpha=0.25, color=GRID_COLOR)


# =============================================================================
# 2. Time domain window
# =============================================================================

def welch_window(N):
    """Generate an N-point Welch window."""

    n = np.arange(N)
    x = (n - (N - 1) / 2) / ((N - 1) / 2)
    w = 1 - x**2

    return w

w = welch_window(WINDOW_LEN)

fig, ax = plt.subplots(figsize=(8, 4.5))
fig.patch.set_alpha(0.0)

ax.plot( np.arange(WINDOW_LEN), w, lw=2.0, color=WINDOW_COLOR, label="Welch window")
ax.set_title(f"Welch window (N={WINDOW_LEN})")
ax.set_xlabel("sample")
ax.set_ylabel("amplitude")
_style_axes(ax)

legend = ax.legend(loc="upper right",fontsize=8,facecolor="none",edgecolor=TEXT_COLOR)

for text in legend.get_texts():
    text.set_color(TEXT_COLOR)

fig.tight_layout()
fig.savefig( TIME_PLOT_PATH, dpi=110, transparent=True)
plt.close(fig)


# =============================================================================
# 3. Frequency domain window
# =============================================================================

FFT_LEN = 16 * WINDOW_LEN

W = np.fft.fft(w, n=FFT_LEN)
W = np.fft.fftshift(W)
f = np.fft.fftshift( np.fft.fftfreq(FFT_LEN, d=1.0))


magnitude = np.abs(W)
magnitude /= np.max(magnitude)
magnitude_db = 20 * np.log10(np.maximum(magnitude, 1e-12))


fig, ax = plt.subplots(figsize=(8, 4.5))

fig.patch.set_alpha(0.0)

ax.plot(f,magnitude_db,lw=2.0,color=WINDOW_COLOR,label="Welch window")

ax.set_title(f"Welch window frequency response (N={WINDOW_LEN})")
ax.set_xlabel("normalized frequency [cycles/sample]")
ax.set_ylabel("magnitude [dB]")
ax.set_ylim(-120, 5)
_style_axes(ax)

legend = ax.legend(loc="upper right",fontsize=8,facecolor="none",edgecolor=TEXT_COLOR,)

for text in legend.get_texts():
    text.set_color(TEXT_COLOR)

fig.tight_layout()
fig.savefig( FREQ_PLOT_PATH, dpi=110, transparent=True)
plt.close(fig)
