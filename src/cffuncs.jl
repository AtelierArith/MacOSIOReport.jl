function cfrelease(obj)
    if obj != C_NULL
        ccall(:CFRelease, Cvoid, (CFTypeRef,), obj)
    end
end

function cfstref(s::AbstractString)::CFStringRef
    Base.unsafe_convert(CFStringRef, CFString(s))
end

function IORegistryEntryCreateCFProperties(
    entry::UInt32,
    props_out::Ref{CFDictionaryRef},
    allocator::Ptr{Cvoid},
    options::UInt32,
)::Int32
    return ccall(
        :IORegistryEntryCreateCFProperties,
        Int32,
        (UInt32, Ptr{CFDictionaryRef}, Ptr{Cvoid}, UInt32),
        entry,
        props_out,
        allocator,
        options,
    )
end

function cfio_get_props(entry::UInt32, devname::String)::CFDictionaryRef
	propsref = Ref{CFDictionaryRef}(C_NULL)
	kCFAllocatorDefault = Ptr{Cvoid}(0)
	ret = IORegistryEntryCreateCFProperties(entry, propsref, kCFAllocatorDefault, UInt32(0))
	if ret != 0
		error("Failed to get properties for $devname")
	end
	return propsref[]
end

# cfdict_keys requires for running tests
function cfdict_keys(dict::CFDictionaryRef)::Vector{String}
    count =
        ccall(:CFDictionaryGetCount, Csize_t, (CFDictionaryRef,), dict)
    if count == 0
        return String[]
    end
    keys = Vector{CFStringRef}(undef, count)
    vals = Vector{CFTypeRef}(undef, count)
    ccall(
        :CFDictionaryGetKeysAndValues,
        Cvoid,
        (CFDictionaryRef, Ptr{CFStringRef}, Ptr{CFTypeRef}),
        dict,
        pointer(keys),
        pointer(vals),
    )
    return [String(CFString(keys[i])) for i = 1:count]
end

function cfdict_get_val(
    dict::Union{Ptr{Cvoid},CFDictionaryRef},
    key::AbstractString,
)::Union{Ptr{Cvoid},Nothing}
    # Convert the key to a CFStringRef
    cf_key = Base.unsafe_convert(CFStringRef, CFString(key))

    # Call CFDictionaryGetValue to get the value associated with the key
    value = ccall(
        :CFDictionaryGetValue,
        Ptr{Cvoid},
        (CFDictionaryRef, CFStringRef),
        dict,
        cf_key,
    )

    # Release the CFStringRef for the key
    cfrelease(cf_key)
    # Return the value or nothing if the value is C_NULL
    return value == C_NULL ? nothing : value
end

function IOIteratorNext(iterator::UInt32)::UInt32
    return ccall(:IOIteratorNext, UInt32, (UInt32,), iterator)
end

function IOServiceGetMatchingServices(
    mainPort::Integer,
    matching::CFDictionaryRef,
    existing_out::Ref{UInt32},
)::Int32
    return ccall(
        :IOServiceGetMatchingServices,
        Int32,
        (UInt32, CFDictionaryRef, Ptr{UInt32}),
        mainPort,
        matching,
        existing_out,
    )
end

function IORegistryEntryGetName(entry::UInt32, name::Ptr{Cchar})::Int32
    return ccall(
        :IORegistryEntryGetName,
        Int32,
        (UInt32, Ptr{Cchar}),
        entry,
        name,
    )
end

function IOServiceMatching(name::String)::CFDictionaryRef
    cstr = String(name) * "\0"
    return ccall(
        :IOServiceMatching,
        CFDictionaryRef,
        (Ptr{UInt8},),
        pointer(cstr),
    )
end

function to_mhz(vals::Vector{UInt32}, scale::UInt32)
    return [v ÷ scale for v in vals]
end

function get_dvfs_mhz(
    dict::CFDictionaryRef,
    key::String,
)::Tuple{Vector{UInt32},Vector{UInt32}}
    cfd = cfdict_get_val(dict, key)
    if cfd === nothing
        return (UInt32[], UInt32[])
    end
    obj = cfd::CFDataRef
    obj_len = ccall(:CFDataGetLength, Csize_t, (CFDataRef,), obj)
    buf = Vector{UInt8}(undef, obj_len)
    rng = CFRange(0, obj_len)
    ccall(
        :CFDataGetBytes,
        Cvoid,
        (CFDataRef, CFRange, Ptr{UInt8}),
        obj,
        rng,
        pointer(buf),
    )

    item_count = div(obj_len, 8)
    freqs = Vector{UInt32}(undef, item_count)
    volts = Vector{UInt32}(undef, item_count)
    for i = 0:(item_count-1)
        chunk = buf[8i+1:8i+8]
        fraw = only(reinterpret(UInt32, chunk[1:4]))
        vraw = only(reinterpret(UInt32, chunk[5:8]))
        freqs[i+1] = fraw
        volts[i+1] = vraw
    end
    return (volts, freqs)
end