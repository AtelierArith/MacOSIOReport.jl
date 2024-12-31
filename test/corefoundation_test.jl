@testitem "corefoundation" begin
    using ObjectiveC.CoreFoundation: CFString
    using MacOSIOReport: cfstref, cfrelease
    @testset "cfstref" begin
        jlstr = "example"
        ref = cfstref(jlstr)
        @test String(CFString(ref)) == jlstr
        @testset "cfrelease" begin
            cfrelease(ref)
            @test true
        end
    end
end