@testitem "metrics" begin
    using JET
    using MacOSIOReport

    @testset "JET" begin
        if VERSION ≥ v"1.10"
            JET.test_package(MacOSIOReport; target_defined_modules = true)
        end
    end
end
