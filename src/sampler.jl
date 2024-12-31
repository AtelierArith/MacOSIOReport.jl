mutable struct Sampler
    soc::SocInfo
    ior::IOReport
end

function Sampler()
    soc = SocInfo()
    ior = IOReport()
    Sampler(soc, ior)
end

