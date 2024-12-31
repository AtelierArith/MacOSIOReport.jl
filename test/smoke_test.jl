@testitem "smoke_test" begin

    using Test
    using MacOSIOReport: cfio_get_chan, cfdict_keys, cfio_get_subs
    using MacOSIOReport: get_samples, get_metrics, cfio_copy_channels
    using MacOSIOReport: IOReport, Sampler
    using ObjectiveC.CoreFoundation: CFDictionaryRef

    @testset "cfio_get_chan" begin
        r = cfio_get_chan()
        @test r isa CFDictionaryRef
        @test "IOReportChannels" in cfdict_keys(r)
    end

    @testset "Sampler" begin
        sampler = Sampler()
        @test true
    end

    @testset "get_samples" begin
        ior = IOReport()
        results = get_samples(ior, UInt(1000), UInt(4))
        @test true
    end

    @testset "get_metrics" begin
        sampler = Sampler()
        duration = UInt(1000)
        get_metrics(sampler::Sampler, duration)
        @test true
    end
end
