@testitem "helper functions" begin
    using Test
    using MacOSIOReport: zero_div

    @testset "zero_div" begin
        @test zero_div(5, 0) == float(0)
        @test zero_div(5, 2) == 5 / 2
    end
end