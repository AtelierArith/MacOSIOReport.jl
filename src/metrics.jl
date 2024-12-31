function cfio_get_residencies(item::CFDictionaryRef)::Vector{Tuple{String,Int64}}
    count = ccall((:IOReportStateGetCount, libIOReport), Int32, (CFDictionaryRef,), item)

    res = Vector{Tuple{String,Int64}}()

    for i = 0:(count-1)
        name_ref = ccall(
            (:IOReportStateGetNameForIndex, libIOReport),
            CFStringRef,
            (CFDictionaryRef, Int32),
            item,
            i,
        )
        name = String(CFString(name_ref))

        val = ccall(
            (:IOReportStateGetResidency, libIOReport),
            Int64,
            (CFDictionaryRef, Int32),
            item,
            i,
        )

        push!(res, (name, val))
    end

    return res
end

function cfio_watts(
    item::CFDictionaryRef,
    unit::String,
    duration::UInt64,
)::Union{Float64,String}
    val = ccall(
        (:IOReportSimpleGetIntegerValue, libIOReport),
        Int64,
        (CFDictionaryRef, Int32),
        item,
        0,
    )

    val /= (duration / 1000.0) # Convert duration from ms to seconds

    if unit == "mJ"
        return val / 1e3
    elseif unit == "uJ"
        return val / 1e6
    elseif unit == "nJ"
        return val / 1e9
    else
        error("Invalid energy unit: $unit")
    end
end

function calc_freq(item::CFDictionaryRef, freqs::Vector{UInt32})::Tuple{UInt32,Float32}
    items = cfio_get_residencies(item) # (ns, freq)
    len1, len2 = length(items), length(freqs)
    @assert len1 > len2 "calc_freq invalid data: $len1 vs $len2"

    # IDLE / DOWN for CPU; OFF for GPU; DOWN only on M2?/M3 Max Chips
    offset = findfirst(x -> x[1] != "IDLE" && x[1] != "DOWN" && x[1] != "OFF", items)
    @assert offset !== nothing "No valid offset found"

    usage = sum(x[2] for x in items[offset:end])
    total = sum(x[2] for x in items)
    count = length(freqs)
    @assert count > 0
    avg_freq = 0.0
    for i = 1:count
        percent = zero_div(items[i+offset-1][2], usage)
        avg_freq += percent * freqs[i]
    end

    usage_ratio = zero_div(usage, total)
    min_freq = first(freqs)
    max_freq = last(freqs)
    from_max = (max(avg_freq, min_freq) * usage_ratio) / max_freq

    return round(UInt32, avg_freq), from_max
end

function calc_freq_final(items, freqs)
    avg_freq = zero_div(sum(x[1] for x in items), length(items))
    avg_perc = zero_div(sum(x[2] for x in items), length(items))
    min_freq = first(freqs)

    m = max(avg_freq, min_freq)
    return round(UInt32, m), Float32(avg_perc)
end

@kwdef mutable struct Metrics
    # FIXME: Currently we can't get TempMetrics correctly
    # because `read_all_keys(smc)` fails in `init_smc()`
    # Need more learn the original Rust implementation
    # temp::TempMetrics = TempMetrics()
    #memory::MemMetrics # We omit this because we can't get it from HID Need more learn the original Rust implementation
    # freq, percent_from_max
    ecpu_usage::Tuple{UInt32,Float64} = (UInt32(0), 0.0)
    # freq, percent_from_max
    pcpu_usage::Tuple{UInt32,Float64} = (UInt32(0), 0.0)
    # freq, percent_from_max
    gpu_usage::Tuple{UInt32,Float64} = (UInt32(0), 0.0)
    # Watts
    cpu_power::Float64 = 0.0
    # Watts
    gpu_power::Float64 = 0.0
    # Watts
    ane_power::Float64 = 0.0
    # Watts
    all_power::Float64 = 0.0
    # Watts
    # sys_power::Float64 = 0.0
end


function get_metrics(sampler::Sampler, duration::UInt64)
    measures = UInt64(4)
    results = Metrics[]

    for (ioreport_iterator, sample_dt) in get_samples(sampler.ior, duration, measures)
        ecpu_usages = []
        pcpu_usages = []
        rs = Metrics()
        for x in ioreport_iterator
            if x.group == "CPU Stats" && x.subgroup == "CPU Core Performance States"
                if occursin("ECPU", x.channel)
                    push!(ecpu_usages, calc_freq(x.item, sampler.soc.ecpu_freqs))
                elseif occursin("PCPU", x.channel)
                    push!(pcpu_usages, calc_freq(x.item, sampler.soc.pcpu_freqs))
                end
            elseif x.group == "GPU Stats" && x.subgroup == "GPU Performance States"
                if x.channel == "GPUPH"
                    rs.gpu_usage = calc_freq(x.item, sampler.soc.gpu_freqs[2:end])
                end
            elseif x.group == "Energy Model"
                if x.channel == "CPU Energy"
                    rs.cpu_power += cfio_watts(x.item, x.unit, sample_dt)
                elseif x.channel == "GPU Energy"
                    rs.gpu_power += cfio_watts(x.item, x.unit, sample_dt)
                elseif startswith(x.channel, "ANE")
                    rs.ane_power += cfio_watts(x.item, x.unit, sample_dt)
                end
            end
        end
        rs.ecpu_usage = calc_freq_final(ecpu_usages, sampler.soc.ecpu_freqs)
        rs.pcpu_usage = calc_freq_final(pcpu_usages, sampler.soc.pcpu_freqs)
        push!(results, rs)
    end

    rs = Metrics()

    rs.ecpu_usage = (
        UInt32(round(zero_div(sum(x.ecpu_usage[1] for x in results), measures))),
        Float32(zero_div(sum(x.ecpu_usage[2] for x in results), measures)),
    )

    rs.pcpu_usage = (
        UInt32(round(zero_div(sum(x.pcpu_usage[1] for x in results), measures))),
        Float32(zero_div(sum(x.pcpu_usage[2] for x in results), measures)),
    )

    rs.gpu_usage = (
        UInt32(round(zero_div(sum(x.gpu_usage[1] for x in results), measures))),
        Float32(zero_div(sum(x.gpu_usage[2] for x in results), measures)),
    )

    rs.cpu_power = zero_div(sum(x.cpu_power for x in results), measures)
    rs.gpu_power = zero_div(sum(x.gpu_power for x in results), measures)
    rs.ane_power = zero_div(sum(x.ane_power for x in results), measures)
    rs.all_power = rs.cpu_power + rs.gpu_power + rs.ane_power
    #rs.sys_power = max(get_sys_power(sampler), rs.all_power)

    return rs
end