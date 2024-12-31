# MacOSIOReport.jl

This Julia package provides functionality to monitor CPU and GPU usage on M-series macOS systems(i.e., Apple Silicon). It is inspired by and partially ports the [vladkens/macmon](https://github.com/vladkens/macmon) project, originally written in Rust.

## Prerequisites

- macOS with Apple Silicon (M-series) processor
- Julia (install using [juliaup](https://github.com/JuliaLang/juliaup))

## Installation

1. Clone the repository:

## Usage

```sh
$ cat demo.jl
using MacOSIOReport: handle_raw

function main()
    msec = UInt64(1000)
    handle_raw(msec)
end

main()
$ julia --project demo.jl
```

```
[ Info: MacOSIOReport.Metrics((0x0000058a, 0.07975462824106216), (0x0000044f, 0.009710949845612049), (0x0000014d, 0.0050773611292243), 0.29085867707151625, 0.015137907338430791, 0.0, 0.30599658440994704)
┌ Info: E-CPU
└   (Int(m.ecpu_usage[1]), 100 * m.ecpu_usage[2]) = (1418, 7.975462824106216)
┌ Info: P-CPU
└   (Int(m.pcpu_usage[1]), 100 * m.pcpu_usage[2]) = (1103, 0.9710949845612049)
┌ Info: GPU
└   (Int(m.gpu_usage[1]), 100 * m.pcpu_usage[2]) = (333, 0.9710949845612049)
┌ Info: CPU Power
└   m.cpu_power = 0.29085867707151625
┌ Info: GPU Power
└   m.gpu_power = 0.015137907338430791
```

This means:
- E-CPU (Efficiency cores) are running at 1418MHz with 7.9% usage
- P-CPU (Performance cores) are running at 1103MHz with 0.97% usage
- GPU is running at 333MHz with 0.97% usage
- CPU is consuming 0.29 watts of power
- GPU is consuming 0.015 watts of power