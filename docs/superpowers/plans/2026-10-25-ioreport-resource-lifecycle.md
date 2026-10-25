# IOReport Resource Lifecycle and Iterator Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the `Sampler() → get_metrics` path used by `TerminalSystemMonitor.jl` release its CoreFoundation/IOReport resources and make low-level sample iterators safe for null metadata and generic Julia collection.

**Architecture:** Add idempotent `Base.close`/`Base.isopen` methods and finalizers to the owning Julia wrappers (`IOReport`, `Sampler`, and `IOReportIterator`). Keep raw CoreFoundation ownership explicit: the wrapper releases only objects returned with ownership by the corresponding Apple API, and all later cleanup is safe to repeat. Normalize unit-label decoding through one null-safe helper and declare the iterator size unknown because it has no `length` method.

**Tech Stack:** Julia 1.10+, ObjectiveC/CoreFoundation, macOS IOReport C API, Test/ReTestItems, the existing TerminalSystemMonitor extension.

**Spec:** User request to audit and repair the API path from `TerminalSystemMonitor.jl` into this `MacOSIOReport.jl` port of `./extern/macmon`.

## Global Constraints

- Preserve the existing `Sampler` and `get_metrics` call signatures used by `TerminalSystemMonitorMacOSIOReportExt`.
- Do not stage or modify the user-provided untracked `extern/macmon/` reference tree or unrelated untracked documentation files.
- Keep cleanup idempotent because both explicit cleanup and Julia finalizers may run.
- Verify with the full package test suite and the real TerminalSystemMonitor macOS extension call path.

## Review Focus

- A monitor refresh constructs samplers repeatedly; every IOReport subscription and retained sample must become unreachable without leaking native objects. Test explicit and repeated cleanup.
- A caller may abandon a sample iterator after an exception; its owned sample must still be releasable. Test `close` before exhaustion and idempotent finalization state.
- IOReport channel metadata may omit a unit label; decoding a null `CFStringRef` must produce `""` without calling `CFString` on null. Test an empty channel dictionary.
- `collect(iterator)` must not assume a `length` method that the iterator does not provide. Test collection of a real delta sample.
- Existing TSM CPU/GPU plotting methods must still load and return their plots after the lifecycle changes. Run both extension methods in a clean temporary TSM environment.

### Task 1: Add failing lifecycle and iterator-contract tests

**Files:**
- Create: `test/resource_lifecycle_test.jl`

**Interfaces:**
- Consumes: existing `IOReport`, `IOReportIterator`, `Sampler`, `get_samples`, and `cfio_get_unitlabel` names from `MacOSIOReport`.
- Produces: executable regression tests for `Base.close`, `Base.isopen`, null-safe unit labels, and `collect`.

- [x] **Step 1: Write the failing tests**

```julia
@testitem "resource lifecycle and iterator contract" begin
    using Test
    using MacOSIOReport: IOReport, IOReportIterator, Sampler, cfio_get_unitlabel, cfrelease,
        get_samples

    @testset "IOReport and Sampler cleanup is idempotent" begin
        report = IOReport()
        @test isopen(report)
        close(report)
        @test !isopen(report)
        close(report)
        @test_throws ArgumentError get_samples(report, UInt64(1), UInt64(1))

        sampler = Sampler()
        @test isopen(sampler)
        close(sampler)
        @test !isopen(sampler)
        close(sampler)
    end

    @testset "unit labels tolerate null CoreFoundation values" begin
        empty_channel = ccall(
            :CFDictionaryCreateMutable,
            MacOSIOReport.CFDictionaryRef,
            (Ptr{Cvoid}, Csize_t, Csize_t, Ptr{Cvoid}),
            C_NULL,
            0,
            0,
            C_NULL,
        )
        try
            @test cfio_get_unitlabel(empty_channel) == ""
        finally
            cfrelease(empty_channel)
        end
    end

    @testset "sample iterators can be collected and closed early" begin
        report = IOReport()
        iterator = first(get_samples(report, UInt64(1), UInt64(1)))[1]
        @test collect(iterator) isa Vector
        @test !isopen(iterator)

        iterator = first(get_samples(report, UInt64(1), UInt64(1)))[1]
        @test isopen(iterator)
        close(iterator)
        @test !isopen(iterator)
        close(iterator)
        close(report)
    end
end
```

- [x] **Step 2: Run the new test to verify it fails for the missing API**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: the new test item fails because `IOReport`/`Sampler` do not yet implement `isopen`/`close`, `cfio_get_unitlabel` is not defined, and `collect(IOReportIterator)` requests a missing `length` method.

- [x] **Step 3: Commit the red tests**

```bash
git add test/resource_lifecycle_test.jl test/runtests.jl
git commit -m "test: cover IOReport resource lifecycle"
```

### Task 2: Implement owned-resource cleanup and safe iteration

**Files:**
- Modify: `src/ioreport.jl:104-300`
- Modify: `src/sampler.jl:1-10`

**Interfaces:**
- Consumes: the failing tests from Task 1 and existing IOReport sampling behavior.
- Produces: idempotent `close`/`isopen` for `IOReport`, `IOReportIterator`, and `Sampler`; finalizers for native owners; `cfio_get_unitlabel`; `collect`-compatible iterator metadata; and a clear error when sampling a closed report.

- [x] **Step 1: Implement the minimal ownership model**

```julia
Base.IteratorSize(::Type{IOReportIterator}) = Base.SizeUnknown()

function cfio_get_unitlabel(item::CFDictionaryRef)::String
    unitlabel = IOReportChannelGetUnitLabel(item)
    unitlabel == C_NULL ? "" : strip(String(CFString(unitlabel)))
end

Base.close(iter::IOReportIterator) = begin
    if iter.sample != C_NULL
        cfrelease(iter.sample)
        iter.sample = C_NULL
    end
    iter.items = C_NULL
    iter.items_size = 0
    nothing
end

Base.isopen(iter::IOReportIterator) = iter.sample != C_NULL
```

Use the same idempotent release pattern for `IOReport` and `Sampler`, attach finalizers in their constructors, replace the iterator's direct unit-label conversion with `cfio_get_unitlabel`, and make `get_samples` reject a closed report with `ArgumentError`.

- [x] **Step 2: Run the focused lifecycle tests and fix only test-diagnosed issues**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: the new lifecycle test item and all existing test items pass with no native-resource double-release crash.

- [x] **Step 3: Run the real TSM integration smoke check**

Run a clean temporary copy of `TerminalSystemMonitor.jl` with this package developed by path, then evaluate:

```julia
using TerminalSystemMonitor, MacOSIOReport, MLDataDevices
TerminalSystemMonitor.plot_cpu_utilization_rates(MLDataDevices.MetalDevice)
TerminalSystemMonitor.plot_gpu_utilization_rates(MLDataDevices.MetalDevice)
```

Expected: the extension loads and both methods return one plot without API or cleanup errors.

- [ ] **Step 4: Commit the implementation**

```bash
git add src/ioreport.jl src/sampler.jl
git commit -m "fix: release IOReport resources safely"
```

### Task 3: Review, verify, and integrate

**Files:**
- Modify: only files identified by the review if a regression test demonstrates a critical or important issue.

- [ ] **Step 1: Review the branch against `main` and classify findings**
- [ ] **Step 2: Run the full package test suite after any review fixes**
- [ ] **Step 3: Push the feature branch and open a pull request against `main`**
- [ ] **Step 4: Wait for required checks, merge the pull request, and verify the merged `main` checkout**

