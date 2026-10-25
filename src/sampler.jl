mutable struct Sampler
    soc::SocInfo
    ior::IOReport
end

function Sampler()
    soc = SocInfo()
    ior = IOReport()
    sampler = Sampler(soc, ior)
    finalizer(close, sampler)
    sampler
end

Base.close(sampler::Sampler) = close(sampler.ior)
Base.isopen(sampler::Sampler) = isopen(sampler.ior)

