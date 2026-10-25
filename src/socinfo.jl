"""
    IOServiceIterator(service_name::String)

Iterate over `(entry, name)` pairs for an IOKit service. The iterator owns each
entry until the next iteration or `close(iter)`; callers must retain an entry
themselves if it needs to outlive that interval. Close the iterator in a `finally`
block when iteration may end early. Cleanup is idempotent and also runs on GC.
"""
mutable struct IOServiceIterator
    existing::UInt32
    current::UInt32
end

function IOServiceIterator(existing::UInt32)
    iter = IOServiceIterator(existing, UInt32(0))
    finalizer(close, iter)
    return iter
end

function IOServiceIterator(service_name::String)
    cexists = Ref{UInt32}(0)
    matchdict = IOServiceMatching(service_name)
    ret = IOServiceGetMatchingServices(0, matchdict, cexists)
    if ret != 0
        cexists[] != 0 && IOObjectRelease(cexists[])
        error("$(service_name) not found (IOKit error $ret)")
    end
    return IOServiceIterator(cexists[])
end

function IOObjectRelease(obj::UInt32)::UInt32
    return ccall(:IOObjectRelease, UInt32, (UInt32,), obj)
end

Base.IteratorSize(::Type{IOServiceIterator}) = Base.SizeUnknown()
Base.isopen(iter::IOServiceIterator) = iter.existing != 0

function _release_current!(iter::IOServiceIterator)
    current = iter.current
    iter.current = 0
    current != 0 && IOObjectRelease(current)
    nothing
end

function Base.close(iter::IOServiceIterator)
    _release_current!(iter)
    existing = iter.existing
    iter.existing = 0
    existing != 0 && IOObjectRelease(existing)
    nothing
end

# The returned entry is borrowed until the next iteration or close(iter).
function Base.iterate(iter::IOServiceIterator, state = nothing)
    isopen(iter) || return nothing
    _release_current!(iter)
    iter.current = IOIteratorNext(iter.existing)
    if iter.current == 0
        close(iter)
        return nothing
    end
    try
        namebuf = zeros(Cchar, 128)
        ret = IORegistryEntryGetName(iter.current, pointer(namebuf))
        ret == 0 || error("Failed to read IOKit entry name (IOKit error $ret)")
        name = GC.@preserve namebuf unsafe_string(pointer(namebuf))
        return ((iter.current, name), nothing)
    catch
        close(iter)
        rethrow()
    end
end

struct SocInfo
    ecpu_freqs::Vector{UInt32}
    pcpu_freqs::Vector{UInt32}
    gpu_freqs::Vector{UInt32}
end

is_pmgr_node(name::String) = name == "pmgr" || name == "pmgr-child"

# Each eight-byte acc-clusters record starts with the table index and tier.
# Use the two highest tiers, matching macmon's discovery on newer SoCs.
function parse_acc_clusters(data::AbstractVector{UInt8})
    clusters = Tuple{UInt8,String}[]
    for i = 1:8:(length(data)-7)
        push!(clusters, (data[i+1], "voltage-states$(data[i])-sram"))
    end
    length(clusters) >= 2 || return nothing
    sort!(clusters; by = first)
    return clusters[end-1][2], clusters[end][2]
end

function cpu_freqs(props::CFDictionaryRef, key::String, is_ecpu::Bool, scale::UInt32)
    _, freqs = get_dvfs_mhz(props, key)
    if isempty(freqs)
        data = cfdict_get_val(props, "acc-clusters")
        data === nothing && return UInt32[]
        keys = parse_acc_clusters(cfdata_bytes(data))
        keys === nothing && return UInt32[]
        _, freqs = get_dvfs_mhz(props, keys[is_ecpu ? 1 : 2])
    end
    return to_mhz(freqs, scale)
end

function read_soc_node!(soc::SocInfo, props::CFDictionaryRef, cpu_scale::UInt32)
    # A stub node or a later node must not overwrite a discovered table.
    if isempty(soc.ecpu_freqs)
        append!(soc.ecpu_freqs, cpu_freqs(props, "voltage-states1-sram", true, cpu_scale))
    end
    if isempty(soc.pcpu_freqs)
        append!(soc.pcpu_freqs, cpu_freqs(props, "voltage-states5-sram", false, cpu_scale))
    end
    if isempty(soc.gpu_freqs)
        _, freqs = get_dvfs_mhz(props, "voltage-states9")
        append!(soc.gpu_freqs, to_mhz(freqs, UInt32(1_000_000)))
    end
    return soc
end

function SocInfo()
    chip_name = String(MTLDevice(1).name)
    hz_freqs = any(prefix -> occursin(prefix, chip_name), ("M1", "M2", "M3", "A1"))
    cpu_scale = hz_freqs ? UInt32(1_000_000) : UInt32(1_000)
    soc = SocInfo(UInt32[], UInt32[], UInt32[])
    iter = IOServiceIterator("AppleARMIODevice")
    try
        for (entry, name) in iter
            is_pmgr_node(name) || continue
            props = cfio_get_props(entry, name)
            try
                read_soc_node!(soc, props, cpu_scale)
            finally
                cfrelease(props)
            end
        end
    finally
        close(iter)
    end
    return soc
end
