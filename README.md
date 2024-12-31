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
