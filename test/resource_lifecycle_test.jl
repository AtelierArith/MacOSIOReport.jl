@testitem "resource lifecycle and iterator contract" begin
    using Test
    using MacOSIOReport: IOReport, IOReportIterator, Sampler, cfio_get_chan, cfio_get_subs,
        cfio_get_unitlabel, cfrelease, get_samples

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
        items = collect(iterator)
        @test items isa Vector
        @test !isopen(iterator)
        @test all(isopen, items)
        foreach(close, items)

        iterator = first(get_samples(report, UInt64(1), UInt64(1)))[1]
        @test isopen(iterator)
        close(iterator)
        @test !isopen(iterator)
        close(iterator)
        close(report)
    end

    @testset "subscriptions retain the effective channel dictionary" begin
        channels = cfio_get_chan()
        subscription = C_NULL
        subscribed_channels = C_NULL
        try
            subscription, subscribed_channels = cfio_get_subs(channels)
            @test subscription != C_NULL
            @test subscribed_channels != C_NULL
        finally
            cfrelease(subscribed_channels)
            cfrelease(subscription)
            cfrelease(channels)
        end
    end
end
