const libIOReport = "libIOReport"

const IOReportSubscriptionRef = Ptr{Cvoid}

function IOReportChannelGetGroup(a::CFDictionaryRef)::CFStringRef
    return ccall(
        (:IOReportChannelGetGroup, libIOReport),
        CFStringRef,
        (CFDictionaryRef,),
        a,
    )
end

function IOReportChannelGetSubGroup(a::CFDictionaryRef)::CFStringRef
    return ccall(
        (:IOReportChannelGetSubGroup, libIOReport),
        CFStringRef,
        (CFDictionaryRef,),
        a,
    )
end

function IOReportChannelGetChannelName(a::CFDictionaryRef)::CFStringRef
    return ccall(
        (:IOReportChannelGetChannelName, libIOReport),
        CFStringRef,
        (CFDictionaryRef,),
        a,
    )
end

function IOReportChannelGetUnitLabel(a::CFDictionaryRef)::CFStringRef
    return ccall(
        (:IOReportChannelGetUnitLabel, libIOReport),
        CFStringRef,
        (CFDictionaryRef,),
        a,
    )
end

function cfio_get_group(item::CFDictionaryRef)
    grpref = IOReportChannelGetGroup(item)
    if grpref == C_NULL
        return ""
    end
    return String(CFString(grpref))
end

function cfio_get_subgroup(item::CFDictionaryRef)
    sgref = IOReportChannelGetSubGroup(item)
    if sgref == C_NULL
        return ""
    end
    return String(CFString(sgref))
end

function cfio_get_channel(item::CFDictionaryRef)
    cname = IOReportChannelGetChannelName(item)
    if cname == C_NULL
        return ""
    end
    return String(CFString(cname))
end

function cfio_get_get_unitlabel(item::CFDictionaryRef)
    unitlabel = IOReportChannelGetUnitLabel(item)
    if unitlabel == C_NULL
        return ""
    end
    return String(CFString(unitlabel))
end


function IOReportCreateSamples(
    subs::IOReportSubscriptionRef,
    chan::CFMutableDictionaryRef,
    v::CFTypeRef,
)::CFDictionaryRef
    return ccall(
        (:IOReportCreateSamples, libIOReport),
        CFDictionaryRef,
        (IOReportSubscriptionRef, CFMutableDictionaryRef, CFTypeRef),
        subs,
        chan,
        v,
    )
end

function IOReportCreateSamplesDelta(
    a::CFDictionaryRef,
    b::CFDictionaryRef,
    c::CFTypeRef,
)::CFDictionaryRef
    return ccall(
        (:IOReportCreateSamplesDelta, libIOReport),
        CFDictionaryRef,
        (CFDictionaryRef, CFDictionaryRef, CFTypeRef),
        a,
        b,
        c,
    )
end

mutable struct IOReportIterator
    sample::CFDictionaryRef
    index::Int64
    items::CFArrayRef
    items_size::UInt64
end

function IOReportIterator(data::CFDictionaryRef)
    chval = cfdict_get_val(data, "IOReportChannels")
    if chval === nothing
        # Possibly empty
        index = 0
        sz = 0
        return IOReportIterator(data, index, C_NULL, sz)
    end
    items = chval::CFArrayRef
    index = 0
    sz = ccall(:CFArrayGetCount, Csize_t, (CFArrayRef,), items)
    return IOReportIterator(data, index, items, sz)
end

mutable struct IOReportIteratorItem
    group::String
    subgroup::String
    channel::String
    unit::String
    item::CFDictionaryRef
end

function Base.iterate(iter::IOReportIterator, state::Int64 = 0)
    if state >= iter.items_size
        cfrelease(iter.sample)
        # Remark
        #cfrelease(iter.items) <-- do not release iter.items here
        return nothing
    end
    item = ccall(
        :CFArrayGetValueAtIndex,
        CFDictionaryRef,
        (CFArrayRef, Clong),
        iter.items,
        state,
    )

    group = cfio_get_group(item)
    subgroup = cfio_get_subgroup(item)
    channel = cfio_get_channel(item)
    ulabel = IOReportChannelGetUnitLabel(item) |> CFString |> String
    unitstr = (ulabel == C_NULL) ? "" : strip(ulabel)

    current_item = IOReportIteratorItem(group, subgroup, channel, unitstr, item)

    return current_item, state + 1
end

function cfio_copy_channels(
	group::String,
	subgroup::Union{String, Nothing},
)
	gname = cfstref(group)
	sname = isnothing(subgroup) ? C_NULL : cfstref(subgroup)
	chan = ccall(
		(:IOReportCopyChannelsInGroup, libIOReport),
		CFDictionaryRef,
		(CFStringRef, CFStringRef, Cint, Cint, Cint),
		gname,
		sname,
		0,
		0,
		0,
	)
    return chan
end

function cfio_get_subs(chan::CFDictionaryRef)::IOReportSubscriptionRef
    # Create a mutable pointer for the subscription
    s = Ref{Ptr{Cvoid}}(C_NULL)

    # Call the C function IOReportCreateSubscription
    rs = ccall(
        :IOReportCreateSubscription,
        IOReportSubscriptionRef,
        (Ptr{Cvoid}, Ptr{Cvoid}, Ref{Ptr{Cvoid}}, Cint, Ptr{Cvoid}),
        C_NULL,
        chan,
        s,
        0,
        C_NULL,
    )

    # Check if the result is null
    if rs === C_NULL
        throw("Failed to create subscription")
    end

    # Return the subscription reference
    return rs
end

function cfio_get_chan()
    ch1 = cfio_copy_channels(
		"Energy Model",
		nothing
	)

	ch2 = cfio_copy_channels(
		"CPU Stats",
		"CPU Core Performance States",
	)

	ch3 = cfio_copy_channels(
		"GPU Stats",
		"GPU Performance States"
	)

	ccall(
		(:IOReportMergeChannels, "libIOReport"),
		Cvoid,
		(Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
		ch1,
		ch2,
		C_NULL,
	)

	ccall(
		(:IOReportMergeChannels, "libIOReport"),
		Cvoid,
		(Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
		ch1,
		ch3,
		C_NULL,
	)

	sz = ccall(:CFDictionaryGetCount, Cint, (Ptr{Cvoid},), ch1)

    chan = ccall(
        (:CFDictionaryCreateMutableCopy),
        CFDictionaryRef,
        (Ptr{Cvoid}, Cint, Ptr{Cvoid}),
        C_NULL,
        sz,
        ch1,
    )

	cfrelease(ch1)
	cfrelease(ch2)
	cfrelease(ch3)

	if "IOReportChannels" ∉ cfdict_keys(chan)
		throw("Failed to get channels in cfio_get_chan")
	end

    return chan
end

mutable struct IOReport
    subs::IOReportSubscriptionRef
    chan::CFMutableDictionaryRef
    prev::Union{Nothing,Tuple{CFDictionaryRef,Union{Nothing,Float64}}}
end

function IOReport()
    chan = cfio_get_chan()
    subs = cfio_get_subs(chan)
    return IOReport(subs, chan, (C_NULL, nothing))
end

function get_samples(report::IOReport, duration::UInt64, count::UInt64)
    c = clamp(count, 1, 32)
    result = Vector{Tuple{IOReportIterator,UInt64}}(undef, c)
    step_msec = duration / c
    step_sec = step_msec / 1000

    prev = report.prev[1] == C_NULL ? raw_sample(report) : report.prev

    for i = 1:c
        sleep(step_sec)
        next = raw_sample(report)
        sample_prev::CFDictionaryRef = prev[1]
        sample_next::CFDictionaryRef = next[1]
        Δ = IOReportCreateSamplesDelta(sample_prev, sample_next, C_NULL)
        cfrelease(sample_prev)
        tprev, tnext = prev[2], next[2]
        elapsed = (tnext - tprev) * 1000
        sample_dt = max(round(UInt64, elapsed), 1)
        result[i] = (IOReportIterator(Δ), sample_dt)
        prev = next
    end

    report.prev = prev
    return result
end

function raw_sample(report::IOReport)::Tuple{CFDictionaryRef,Float64}
    samples = IOReportCreateSamples(report.subs, report.chan, C_NULL)
    return (samples, time())
end