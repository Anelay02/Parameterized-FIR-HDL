#!/usr/bin/env python3
# =============================================================================
# File: welch_model.py
# Author: Ayoub el idrissi Achraf
# Description: Reproduces and compares the output of the HDL testbench.
# =============================================================================

import sys
from pathlib import Path
import matplotlib.pyplot as plt


# =============================================================================
# 1. PARAMETERS - keep these synchronized with tb_Welch.v
# =============================================================================

WINDOW_LEN    = 256
INPUT_SIZE    = 16
OUTPUT_SIZE   = 16
CLK_PERIOD_NS = 10.0
RUN_SAMPLES   = 4 * WINDOW_LEN
SIGNAL_STEP   = 257       # input = (sample_index * SIGNAL_STEP) mod 2^INPUT_SIZE

RESULTS_DIR = Path(__file__).resolve().parents[1] / "results"
CSV_PATH = RESULTS_DIR / "tb_Welch.csv"
IMG_DIR = Path(__file__).resolve().parents[1] / "Img"
PLOT_PATH = IMG_DIR / "welch_compare.png"


# =============================================================================
# 2. THE DUT
# =============================================================================

def welch_new(window_len, input_size, output_size):
    """Create a fresh state dictionary for one Welch RTL instance."""
    assert window_len >= 2 and (window_len & (window_len - 1)) == 0
    assert output_size <= input_size
    precision = max(output_size + 1, window_len.bit_length() - 2)
    state = {
        "WINDOW_LEN": window_len,
        "INPUT_SIZE": input_size,
        "OUTPUT_SIZE": output_size,
        "PRECISION": precision,
        "ADDR_WIDTH": window_len.bit_length() - 1,
        "delay_line": [0] * (window_len - 1),
        "o_data": 0,
        "o_valid": 0,
    }
    state["COEFFICIENT_SUM"] = sum(
        welch_raw_coefficient(state, tap) for tap in range(window_len)
    )
    return state


def welch_raw_coefficient(state, tap_index):
    """Return the unnormalised Q(PRECISION) Welch coefficient for one tap."""
    p = state["PRECISION"]
    addr_width = state["ADDR_WIDTH"]
    x_int = tap_index << (p + 1 - addr_width)
    term1 = (x_int << 1) & ((1 << (p + 2)) - 1)
    square = (x_int * x_int + (1 << (p - 1))) & ((1 << (2 * p + 2)) - 1)
    term2 = (square >> p) & ((1 << (p + 2)) - 1)
    return (term1 - term2) & ((1 << (p + 1)) - 1)


def welch_coefficient(state, tap_index):
    """Return a rounded, unity-gain Q(PRECISION) FIR coefficient."""
    p = state["PRECISION"]
    return ((welch_raw_coefficient(state, tap_index) << p) +
            (state["COEFFICIENT_SUM"] >> 1)) // state["COEFFICIENT_SUM"]


def welch_step(state, i_data, i_valid):
    """Simulate one rising edge of the zero-padded sliding-window FIR."""
    p = state["PRECISION"]
    if i_valid:
        # Match Welch.v: i_data is x[n], delay_line[k-1] is x[n-k].
        accumulator = welch_coefficient(state, 0) * i_data
        for tap in range(1, state["WINDOW_LEN"]):
            accumulator += welch_coefficient(state, tap) * state["delay_line"][tap - 1]
        accumulator &= (1 << (state["INPUT_SIZE"] + p + 1 + state["ADDR_WIDTH"])) - 1
        scaled_output = accumulator >> p
        state["o_data"] = min(scaled_output, (1 << state["OUTPUT_SIZE"]) - 1)
        state["delay_line"] = [i_data] + state["delay_line"][:-1]
    state["o_valid"] = 1 if i_valid else 0


# =============================================================================
# 3. THE TESTBENCH
# =============================================================================

def known_input(sample_index):
    """The deterministic input signal used by tb_Welch.v."""
    return (sample_index * SIGNAL_STEP) % (1 << INPUT_SIZE)


def run_testbench():
    """Run the Verilog stimulus sequence in memory."""
    dut = welch_new(WINDOW_LEN, INPUT_SIZE, OUTPUT_SIZE)
    rows = []
    # Reset is released at 15 ns. Sample 0 is logged at 26 ns (#1 after edge).
    first_log_time_ns = 2.5 * CLK_PERIOD_NS + 1.0
    for sample_index in range(RUN_SAMPLES):
        i_data = known_input(sample_index)
        welch_step(dut, i_data, 1)
        rows.append((first_log_time_ns + sample_index * CLK_PERIOD_NS,
                     i_data, 1, dut["o_valid"], dut["o_data"]))

    final_i_data = known_input(RUN_SAMPLES - 1)
    welch_step(dut, final_i_data, 0)
    rows.append((first_log_time_ns + RUN_SAMPLES * CLK_PERIOD_NS,
                 final_i_data, 0, dut["o_valid"], dut["o_data"]))
    return rows


# =============================================================================
# 4. CSV READING / COMPARISON
# =============================================================================

CSV_HEADER = "time_ns,i_data,i_valid,o_valid,o_data"


def read_csv(path):
    """Read the HDL testbench CSV into the tuple format used by run_testbench()."""
    rows = []
    with open(path, "r", encoding="utf-8") as file:
        header = file.readline().strip()
        if header != CSV_HEADER:
            raise ValueError(f"Unexpected CSV header: {header!r}")
        for line in file:
            values = line.strip().split(",")
            if len(values) == 5:
                rows.append((float(values[0]),) + tuple(int(value) for value in values[1:]))
    return rows


def compare(ref_rows, py_rows, label=""):
    """Compare two row sets column by column. Returns True if identical."""
    names = CSV_HEADER.split(",")
    print(f"--- Comparison {label} ---")
    print(f"  rows: reference={len(ref_rows)}  python={len(py_rows)}")
    mismatches = 0
    for index, (ref, py) in enumerate(zip(ref_rows, py_rows)):
        if ref != py:
            mismatches += 1
            if mismatches <= 5:
                different = [names[i] for i in range(len(ref)) if ref[i] != py[i]]
                print(f"  line {index + 2}: {different}  ref={ref}  py={py}")
    ok = mismatches == 0 and len(ref_rows) == len(py_rows)
    print("  RESULT: " + ("BIT-EXACT MATCH" if ok else f"{mismatches} mismatching rows"))
    return ok


# =============================================================================
# 5. PLOTTING
# =============================================================================

TEXT_COLOR = "#999999"
GRID_COLOR = "#888888"
REF_COLOR = "#d2691e"
PY_COLOR = "#1f77b4"


def _style_axes(axis):
    axis.set_facecolor("none")
    axis.title.set_color(TEXT_COLOR)
    axis.xaxis.label.set_color(TEXT_COLOR)
    axis.yaxis.label.set_color(TEXT_COLOR)
    axis.tick_params(axis="both", colors=TEXT_COLOR)
    for spine in axis.spines.values():
        spine.set_color(TEXT_COLOR)
    axis.grid(alpha=0.25, color=GRID_COLOR)


def plot(ref_rows, py_rows, filename=PLOT_PATH):
    """Overlay the Welch RTL CSV and the bit-exact Python output."""
    filename.parent.mkdir(parents=True, exist_ok=True)
    ref_valid = [row for row in ref_rows if row[3]]
    py_valid = [row for row in py_rows if row[3]]
    fig, axis = plt.subplots(figsize=(15, 4.5))
    fig.patch.set_alpha(0.0)
    title = fig.suptitle(
        f"Welch: Python model vs HDL CSV  "
        f"(N={WINDOW_LEN}, IN={INPUT_SIZE}b, OUT={OUTPUT_SIZE}b)"
    )
    title.set_color(TEXT_COLOR)
    axis.plot([row[0] for row in ref_valid], [row[4] for row in ref_valid],
              lw=2.5, color=REF_COLOR, label="HDL CSV")
    axis.plot([row[0] for row in py_valid], [row[4] for row in py_valid],
              lw=1.3, ls="--", color=PY_COLOR, label="Python model")
    axis.set_title("Welch output (o_data)")
    axis.set_xlabel("time [ns]")
    axis.set_ylabel("unsigned output code")
    _style_axes(axis)
    legend = axis.legend(loc="upper right", fontsize=8, facecolor="none", edgecolor=TEXT_COLOR)
    for text in legend.get_texts():
        text.set_color(TEXT_COLOR)
    fig.tight_layout()
    fig.savefig(filename, dpi=110, transparent=True)
    print(f"Plot saved to {filename}")

    count = min(len(ref_valid), len(py_valid))
    errors = [py_valid[i][4] - ref_valid[i][4] for i in range(count)]
    max_error = max(map(abs, errors), default=0)
    mean_error = sum(errors) / count if count else 0.0
    print(f"  Welch error (python - HDL): max |err| = {max_error}, mean = {mean_error:.4f}")


# =============================================================================
# 6. MAIN
# =============================================================================

def main():
    print(f"WINDOW_LEN={WINDOW_LEN} INPUT_SIZE={INPUT_SIZE} OUTPUT_SIZE={OUTPUT_SIZE}")
    print(f"RUN_SAMPLES={RUN_SAMPLES} SIGNAL_STEP={SIGNAL_STEP}")
    if not CSV_PATH.exists():
        print(f"(reference CSV '{CSV_PATH}' not found - run tb_Welch.v first)")
        sys.exit(1)
    ref_rows = read_csv(CSV_PATH)
    py_rows = run_testbench()
    compare(ref_rows, py_rows, f"{CSV_PATH} vs Python model")
    plot(ref_rows, py_rows)


if __name__ == "__main__":
    main()
