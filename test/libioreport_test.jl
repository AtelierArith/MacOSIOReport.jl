@testitem "libIOReport" begin
    using Test
    using MacOSIOReport: CFArrayRef, IOReport
    using MacOSIOReport: cfdict_keys, cfio_copy_channels, cfdict_get_val

    @testset "cfio_copy_channels" begin
        ch = cfio_copy_channels("Invalid", "")
        @test "IOReportChannels" ∉ cfdict_keys(ch)
    end

    @testset "IOReport" begin
        ior = IOReport()

        @test "IOReportChannels" ∈ cfdict_keys(ior.chan)
        items::CFArrayRef = cfdict_get_val(
            ior.chan, "IOReportChannels"
        )

        nvalues = ccall(
            :CFArrayGetCount, Cint, (CFArrayRef,), items
        )
        @test nvalues ≥ 1
    end
end