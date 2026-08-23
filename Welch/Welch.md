# Welch Window FIR Filter

This project implements a parametrizable fixed-point **Welch window** as a
sample-by-sample FIR weighting stage. It is one member of a larger family of
FIR filters; this document covers only the Welch implementation.

The current RTL is Verilog-2001. A matching VHDL-2008 implementation and
testbench are intended to be added alongside it.

## Contents

```text
.
├── Img/
│   ├── welch_time.png       # Welch window in the time domain
│   ├── welch_frequency.png  # Window frequency response
│   └── welch_compare.png    # Python model compared with HDL output
├── python/
│   ├── welch.py             # Generates the explanatory plots
│   └── welch_model.py       # Bit-exact model and CSV comparison
├── results/
│   └── tb_Welch.csv         # Reference testbench output
├── rtl/
│   ├── Welch.v              # Verilog-2001 implementation
│   └── Welch.vhd             # Planned VHDL-2008 implementation
├── tb/
│   ├── tb_Welch.v           # Verilog testbench
│   └── tb_Welch.vhd          # Planned VHDL-2008 testbench
└── Welch.md
```

## Theory

Windowing multiplies each input sample by a coefficient that varies across a
frame. The Welch window used by the RTL is

$$
w[n] = 1 - x[n]^2,
\qquad x[n] = \frac{2n}{N} - 1,
\qquad 0 \leq n < N.
$$

It is zero at the beginning of the frame, reaches one around its midpoint, and
returns close to zero at the end. `WINDOW_LEN` (`N`) must be a power of two so
that the coordinate scaling can be implemented with a shift. The sample
counter wraps naturally after `N` samples, creating a repeated window frame.

![Welch window in the time domain](Img/welch_time.png)

![Welch window frequency response](Img/welch_frequency.png)

The plot above uses the common symmetric plotting form with `(N - 1)` in the
normalization denominator, which makes the endpoints visually reach exactly
zero. The bit-exact RTL behavior described below uses `N` directly and is the
one that actually gets built into hardware; `welch_model.py` matches the RTL,
not the plotting convention.

### From the equation to the RTL

Substituting `x[n]` into `w[n]` and expanding removes the offset of `-1`,
which is convenient because the datapath can then stay unsigned:

$$
w[n] = 1-\left(\frac{2n}{N}-1\right)^2 = 2\underbrace{\left(\frac{2n}{N}\right)}_{u[n]} - u[n]^2 ,
\qquad u[n] = \frac{2n}{N}.
$$

The RTL computes exactly this last form, `w[n] = 2u[n] - u[n]^2`, working
entirely on the unsigned quantity `u[n]` instead of the signed `x[n]`:

```text
x_int       = samples_counter << (PRECISION + 1 - log2(WINDOW_LEN))   // u[n], fixed-point
term1       = x_int << 1                                              // 2*u[n]
square      = x_int * x_int + rounding_constant                       // u[n]^2, pre-rounding
term2       = square >> PRECISION                                     // u[n]^2, rounded back to PRECISION bits
coefficient = term1 - term2                                           // w[n] = 2*u[n] - u[n]^2
product     = coefficient * i_data                                    // windowed sample
```

Because `N` is a power of two, `2n/N` is obtained from the sample counter `n`
with a pure left shift: `x_int` is simply `n` re-expressed with `PRECISION`
fractional bits, no divider needed. Squaring `x_int` doubles its number of
fractional bits, so `square` is shifted right by `PRECISION` (with a rounding
constant added beforehand) to bring `term2` back to the same fixed-point scale
as `term1` before the subtraction. The result, `coefficient`, is the window
value `w[n]` in `[0, 1]`, and multiplying it by `i_data` produces the
windowed, still fixed-point-scaled, sample in `product`. `o_data` is formed by
taking the `OUTPUT_SIZE` most significant bits of `product` (dropping the top
guard bit and the low-order fractional bits), which rescales the product back
down to an integer sample.

### Fixed-point precision

With `P = PRECISION` fractional bits, a real value is stored as
`round(value * 2^P)`. The coefficient value `1.0` is therefore represented by
`2^P`, requiring `P + 1` unsigned bits — this is `COEFF_WIDTH`.

`P` is picked with the conservative rule

$$
P = \max(O + 1,\ \log_2(N) - 1),
$$

where `O` is `OUTPUT_SIZE` and `N` is `WINDOW_LEN`. Each term protects a
different thing:

- **`OUTPUT_SIZE + 1`** keeps the coefficient's own rounding error smaller
  than one output LSB, so quantizing the window doesn't add visible error on
  top of the output's own resolution.
- **`log2(N) - 1`** keeps enough fractional bits that the counter-to-`x_int`
  shift (`PRECISION + 1 - log2(N)`) stays non-negative, so every one of the
  `N` positions in the frame still lands on a distinct fixed-point value
  instead of being rounded away.

`INPUT_SIZE` does not enter this formula: it only scales the width of the
multiplication (`PRODUCT_WIDTH`) and the range of samples the filter accepts,
not the precision of the window itself.

For example, with `N = 256` and `OUTPUT_SIZE = 16`,
`PRECISION = max(17, 7) = 17`, and `COEFF_WIDTH = 18`.

## Interface

### Parameters

| Name | Default | Description |
|---|---:|---|
| `INPUT_SIZE` | `16` | Unsigned input width in bits. |
| `WINDOW_LEN` | `64` | Number of samples per frame. Must be at least 2 and a power of two. |
| `OUTPUT_SIZE` | `16` | Unsigned output width. Must not exceed `INPUT_SIZE`. |

The internal widths are derived from these parameters:
`PRECISION` stores coefficient fractional bits, `COEFF_WIDTH` stores the
coefficient including the range bit, and `PRODUCT_WIDTH` covers the input and
coefficient multiplication.

### Ports

| Name | Direction | Description |
|---|---|---|
| `i_clk` | input | Rising-edge clock. |
| `i_rst_n` | input | Asynchronous active-low reset. |
| `i_data` | input | Unsigned input sample. |
| `i_valid` | input | Advances the counter and updates the output when high. |
| `o_data` | output | Registered windowed sample. Holds its value when `i_valid` is low. |
| `o_valid` | output | Registered copy of `i_valid`. |

The output is registered, so the valid flag identifies the cycle in which the
corresponding `o_data` value is available. Reset clears the counter, output,
and valid flag.

## Simulation and comparison

`tb/tb_Welch.v` drives a deterministic unsigned ramp:

```text
i_data = (sample_index * 257) modulo 2^INPUT_SIZE
```

It runs for four complete window frames, writes `tb_Welch.csv`, and records one
extra idle cycle to verify that `o_valid` deasserts while `o_data` is retained.

The Python model repeats the same stimulus and every finite-width operation in
the RTL. A successful comparison reports `BIT-EXACT MATCH`. The model also
creates `welch_compare.png` from the HDL and Python output traces:

![Python model compared with HDL output](Img/welch_compare.png)

The HDL simulator and Python environment are toolchain-dependent. The
testbench can be compiled with a Verilog simulator such as Icarus Verilog;
run `python/welch_model.py` after placing the generated CSV where its
`CSV_PATH` points. The planned VHDL files should use the same parameters,
stimulus, CSV format, and expected results.

## Reference

- [Window function - Wikipedia](https://en.wikipedia.org/wiki/Window_function)

This project was developed with AI assistance.
