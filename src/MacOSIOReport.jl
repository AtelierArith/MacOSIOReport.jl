module MacOSIOReport

using Metal: MTLDevice

include("utils.jl")

include("cftypes.jl")
include("cffuncs.jl")

include("socinfo.jl")
include("ioreport.jl")
include("sampler.jl")
include("metrics.jl")

export main

function handle_raw(msec)
    sampler = Sampler()  # Assuming a Sampler type exists
    while true
        m::Metrics = get_metrics(sampler, msec)
        @info m
        @info "E-CPU" Int(m.ecpu_usage[1]), 100 * m.ecpu_usage[2]
        @info "P-CPU" Int(m.pcpu_usage[1]), 100 * m.pcpu_usage[2]
        @info "GPU" Int(m.gpu_usage[1]), 100 * m.gpu_usage[2]
        @info "CPU Power" m.cpu_power
        @info "GPU Power" m.gpu_power
    end
end

# Main function
function main()
    msec = UInt64(1000)
    handle_raw(msec)
end

end # module MacOSIOReport
