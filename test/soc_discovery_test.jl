@testitem "SoC discovery and IOKit ownership" begin
    using MacOSIOReport:
        IOServiceIterator,
        SocInfo,
        cfstref,
        cfrelease,
        parse_acc_clusters,
        read_soc_node!,
        is_pmgr_node

    # Use CoreFoundation equality so separately allocated CFString keys match.
    function with_properties(f, properties)
        refs = Ptr{Cvoid}[]
        props = ccall(
            :CFDictionaryCreateMutable,
            MacOSIOReport.CFDictionaryRef,
            (Ptr{Cvoid}, Clong, Ptr{Cvoid}, Ptr{Cvoid}),
            C_NULL,
            0,
            cglobal(:kCFTypeDictionaryKeyCallBacks),
            cglobal(:kCFTypeDictionaryValueCallBacks),
        )
        try
            for (key, bytes) in properties
                keyref = cfstref(key)
                push!(refs, keyref)
                data = ccall(
                    :CFDataCreate,
                    Ptr{Cvoid},
                    (Ptr{Cvoid}, Ptr{UInt8}, Clong),
                    C_NULL,
                    bytes,
                    length(bytes),
                )
                push!(refs, data)
                ccall(
                    :CFDictionarySetValue,
                    Cvoid,
                    (MacOSIOReport.CFDictionaryRef, Ptr{Cvoid}, Ptr{Cvoid}),
                    props,
                    keyref,
                    data,
                )
            end
            return f(props)
        finally
            cfrelease(props)
            foreach(cfrelease, refs)
        end
    end

    # DVFS tables contain little-endian (frequency, voltage) UInt32 pairs.
    table(freqs) = collect(
        reinterpret(
            UInt8,
            htol.(reduce(vcat, ([UInt32(freq), UInt32(800)] for freq in freqs))),
        ),
    )
    clusters = UInt8[5, 2, 0, 0, 0, 0, 0, 0, 23, 1, 0, 0, 0, 0, 0, 0]

    @testset "discovery uses tiers and preserves tables across stub nodes" begin
        @test parse_acc_clusters(clusters) ==
              ("voltage-states23-sram", "voltage-states5-sram")
        @test parse_acc_clusters(UInt8[]) === nothing
        @test parse_acc_clusters(clusters[1:7]) === nothing
        @test is_pmgr_node("pmgr")
        @test is_pmgr_node("pmgr-child")
        @test !is_pmgr_node("other")
        soc = SocInfo(UInt32[], UInt32[], UInt32[])
        with_properties(Dict{String,Vector{UInt8}}()) do props
            read_soc_node!(soc, props, UInt32(1_000))
        end
        @test isempty(soc.ecpu_freqs)
        with_properties(
            Dict(
                "acc-clusters" => clusters,
                "voltage-states23-sram" => table([600_000, 912_000]),
                "voltage-states5-sram" => table([660_000, 3_504_000]),
                "voltage-states9" => table([0, 444_000_000]),
            ),
        ) do props
            read_soc_node!(soc, props, UInt32(1_000))
        end
        @test soc.ecpu_freqs == UInt32[600, 912]
        @test soc.pcpu_freqs == UInt32[660, 3504]
        @test soc.gpu_freqs == UInt32[0, 444]
        with_properties(Dict("voltage-states1-sram" => table([999_000]))) do props
            read_soc_node!(soc, props, UInt32(1_000))
        end
        @test soc.ecpu_freqs == UInt32[600, 912]
        @test soc.pcpu_freqs == UInt32[660, 3504]

        legacy = SocInfo(UInt32[], UInt32[], UInt32[])
        with_properties(
            Dict(
                "acc-clusters" => clusters,
                "voltage-states1-sram" => table([600_000_000]),
                "voltage-states23-sram" => table([999_000_000]),
            ),
        ) do props
            read_soc_node!(legacy, props, UInt32(1_000_000))
        end
        @test legacy.ecpu_freqs == UInt32[600]
    end

    @testset "native iterator supports early close, finalization, and exhaustion" begin
        for cleanup in (close, finalize)
            iter = IOServiceIterator("AppleARMIODevice")
            retained_entry = UInt32(0)
            try
                @test iterate(iter) !== nothing
                @test iter.current != 0
                retained_entry = iter.current
                @test ccall(:IOObjectRetain, UInt32, (UInt32,), retained_entry) == 0
                before = ccall(:IOObjectGetUserRetainCount, UInt32, (UInt32,), retained_entry)
                cleanup(iter)
                after = ccall(:IOObjectGetUserRetainCount, UInt32, (UInt32,), retained_entry)
                @test before == after + 1
                @test iter.current == 0
                @test !isopen(iter)
                @test iterate(iter) === nothing
                close(iter)
            finally
                close(iter)
                retained_entry != 0 && MacOSIOReport.IOObjectRelease(retained_entry)
            end
        end
        iter = IOServiceIterator("AppleARMIODevice")
        try
            @test !isempty([name for (_, name) in iter])
            @test !isopen(iter)
            @test iter.current == 0
        finally
            close(iter)
        end
    end
end

@testitem "missing metric data and per-die energy" begin
    using MacOSIOReport:
        calc_freq_final,
        energy_field,
        add_energy!,
        Metrics,
        Sampler,
        SocInfo,
        IOReport,
        get_metrics

    @test calc_freq_final(Any[], UInt32[600, 1200]) == (UInt32(0), 0.0f0)
    @test calc_freq_final([(UInt32(600), 0.5f0)], UInt32[]) == (UInt32(0), 0.0f0)
    @test calc_freq_final(
        [(UInt32(600), 0.25f0), (UInt32(1200), 0.75f0)],
        UInt32[600, 1200],
    ) == (UInt32(900), 0.5f0)

    rs = Metrics()
    for (channel, watts) in [
        ("DIE_0_CPU Energy", 2.0),
        ("DIE_1_CPU Energy", 3.0),
        ("GPU Energy", 4.0),
        ("ANE0_0", 0.5),
        ("ANE0_1", 0.5),
    ]
        add_energy!(rs, channel, watts)
    end
    @test rs.cpu_power == 5.0
    @test rs.gpu_power == 4.0
    @test rs.ane_power == 1.0
    @test energy_field("CPU Energy") === :cpu_power
    @test energy_field("DRAM Energy") === nothing

    # Real channels with absent DVFS tables must not reach calc_freq assertions.
    sampler = Sampler(SocInfo(UInt32[], UInt32[], UInt32[]), IOReport())
    try
        metrics = get_metrics(sampler, UInt64(20))
        @test metrics.ecpu_usage == (UInt32(0), 0.0)
        @test metrics.pcpu_usage == (UInt32(0), 0.0)
        @test metrics.gpu_usage == (UInt32(0), 0.0)
    finally
        close(sampler)
    end
end
