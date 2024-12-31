@testitem "metrics" begin
    using Aqua
    import MacOSIOReport

    @testset "Aqua" begin
        Aqua.test_all(MacOSIOReport; deps_compat = false)
    end
end
