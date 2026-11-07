@testitem "sample interval" begin
    using Test
    using MacOSIOReport: sample_interval_msec, sample_clock

    @testset "sample_interval_msec" begin
        @test sample_interval_msec(1.0, 1.5) == UInt64(500)
        @test sample_interval_msec(1.0, 1.0004) == UInt64(1)
        # A clock that went backwards must not throw InexactError.
        @test sample_interval_msec(10.0, 8.076) == UInt64(1)
    end

    @testset "sample_clock is monotonic" begin
        t1 = sample_clock()
        t2 = sample_clock()
        @test t1 isa Float64
        @test t2 >= t1
    end
end
