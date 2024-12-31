mutable struct IOServiceIterator
    existing::UInt32
end

function IOServiceIterator(service_name::String)
    cexists = Ref{UInt32}(0)
    matchdict = IOServiceMatching(service_name)
    ret = IOServiceGetMatchingServices(0, matchdict, cexists)
    if ret != 0
        error("$(service_name) not found")
    end
    return IOServiceIterator(cexists[])
end

function IOObjectRelease(obj::UInt32)::UInt32
    return ccall(:IOObjectRelease, UInt32, (UInt32,), obj)
end

function Base.iterate(iter::IOServiceIterator, state=Int64(iter.existing))
    nextobj = IOIteratorNext(iter.existing)
    if nextobj == 0
        IOObjectRelease(iter.existing)
        return nothing
    end
    namebuf = Vector{Cchar}(undef, 128)
    ret = IORegistryEntryGetName(nextobj, pointer(namebuf))
    if ret != 0
        return nothing
    end
    name = unsafe_string(pointer(namebuf))
    return ((nextobj, name), nextobj)
end

struct SocInfo
    ecpu_freqs::Vector{UInt32}
    pcpu_freqs::Vector{UInt32}
    gpu_freqs::Vector{UInt32}
end

function SocInfo()
    chip_name = String(MTLDevice(1).name)
    before_m4 =
        occursin("M1", chip_name) || occursin("M2", chip_name) || occursin("M3", chip_name)
        cpu_scale = before_m4 ? UInt32(1_000_000) : UInt32(1_000)
        gpu_scale = UInt32(1_000_000)

        iter = IOServiceIterator("AppleARMIODevice")

        socinfo = nothing
        for (entry, sname) in iter
            if sname == "pmgr"
                props = cfio_get_props(entry, sname)
                (_, ecpu_freqs) = get_dvfs_mhz(props, "voltage-states1-sram")
                (_, pcpu_freqs) = get_dvfs_mhz(props, "voltage-states5-sram")
                (_, gpu_freqs) = get_dvfs_mhz(props, "voltage-states9")

                ecpu_freqs = to_mhz(ecpu_freqs, cpu_scale)
                pcpu_freqs = to_mhz(pcpu_freqs, cpu_scale)
                gpu_freqs = to_mhz(gpu_freqs, gpu_scale)
                socinfo = (; ecpu_freqs, pcpu_freqs, gpu_freqs)
                cfrelease(props)
            end
        end
        return SocInfo(
            socinfo.ecpu_freqs,
            socinfo.pcpu_freqs,
            socinfo.gpu_freqs,
        )
end
