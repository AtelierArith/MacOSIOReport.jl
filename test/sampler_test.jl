@testitem "sampler" begin
    using Test

    using MacOSIOReport: IOServiceIterator, IOObjectRelease
    begin
        existing = IOServiceIterator("AppleARMIODevice").existing
        @test existing ≥ 1
        a = IOObjectRelease(existing)
        @test Int(a) == 0
    end
end