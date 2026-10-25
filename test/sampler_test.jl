@testitem "sampler" begin
    using Test

    using MacOSIOReport: IOServiceIterator
    begin
        iter = IOServiceIterator("AppleARMIODevice")
        @test isopen(iter)
        close(iter)
        @test !isopen(iter)
    end
end
