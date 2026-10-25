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

function cfio_get_group(item::CFDictionaryRef)::String
    grpref = IOReportChannelGetGroup(item)
    if grpref == C_NULL
        return ""
    end
    return String(CFString(grpref))
end

function cfio_get_subgroup(item::CFDictionaryRef)::String
    sgref = IOReportChannelGetSubGroup(item)
    if sgref == C_NULL
        return ""
    end
    return String(CFString(sgref))
end

function cfio_get_channel(item::CFDictionaryRef)::String
    cname = IOReportChannelGetChannelName(item)
    if cname == C_NULL
        return ""
    end
    return String(CFString(cname))
end

function cfio_get_unitlabel(item::CFDictionaryRef)::String
    unitlabel = IOReportChannelGetUnitLabel(item)
    unitlabel == C_NULL ? "" : strip(String(CFString(unitlabel)))
end

cfio_get_get_unitlabel(item::CFDictionaryRef) = cfio_get_unitlabel(item)

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

Base.IteratorSize(::Type{IOReportIterator}) = Base.SizeUnknown()

function Base.close(iter::IOReportIterator)
    cfrelease(iter.sample)
    iter.sample = C_NULL
    iter.items = C_NULL
    iter.items_size = 0
    nothing
end

Base.isopen(iter::IOReportIterator) = iter.sample != C_NULL

function IOReportIterator(data::CFDictionaryRef)
    chval = cfdict_get_val(data, "IOReportChannels")
    if chval === nothing
        # Possibly empty
        index = 0
        sz = 0
        iter = IOReportIterator(data, index, C_NULL, sz)
        finalizer(close, iter)
        return iter
    end
    items = chval::CFArrayRef
    index = 0
    sz = ccall(:CFArrayGetCount, Csize_t, (CFArrayRef,), items)
    iter = IOReportIterator(data, index, items, sz)
    finalizer(close, iter)
    return iter
end

mutable struct IOReportIteratorItem
    group::String
    subgroup::String
    channel::String
    unit::String
    item::CFDictionaryRef
end

function Base.close(item::IOReportIteratorItem)
    cfrelease(item.item)
    item.item = C_NULL
    nothing
end

Base.isopen(item::IOReportIteratorItem) = item.item != C_NULL

function _make_iterator_item(
    group::String,
    subgroup::String,
    channel::String,
    unit::String,
    item::CFDictionaryRef,
)
    current_item = IOReportIteratorItem(
        group,
        subgroup,
        channel,
        unit,
        cfretain(item),
    )
    finalizer(close, current_item)
    current_item
end

function Base.iterate(iter::IOReportIterator, state::Int64 = 0)
    if state >= iter.items_size
        close(iter)
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
    unitstr = cfio_get_unitlabel(item)

    current_item = _make_iterator_item(group, subgroup, channel, unitstr, item)

    return current_item, state + 1
end

function cfio_copy_channels(
	group::String,
	subgroup::Union{String, Nothing},
)
	gname = cfstref(group)
	sname = isnothing(subgroup) ? C_NULL : cfstref(subgroup)
	try
		return ccall(
			(:IOReportCopyChannelsInGroup, libIOReport),
			CFDictionaryRef,
			(CFStringRef, CFStringRef, Cint, Cint, Cint),
			gname,
			sname,
			0,
			0,
			0,
		)
	finally
		cfrelease(gname)
		cfrelease(sname)
	end
end

function cfio_get_subs(
	chan::CFDictionaryRef,
)::Tuple{IOReportSubscriptionRef,CFMutableDictionaryRef}
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

    subscribed_channels = s[]
    if rs === C_NULL || subscribed_channels === C_NULL
        cfrelease(rs)
        cfrelease(subscribed_channels)
        error("Failed to create subscription")
    end

    return rs, subscribed_channels
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
    prev::Union{Nothing,Tuple{CFDictionaryRef,Float64}}
end

function Base.close(report::IOReport)
    prev = report.prev
    report.prev = nothing
    if prev !== nothing
        cfrelease(prev[1])
    end
    cfrelease(report.chan)
    report.chan = C_NULL
    cfrelease(report.subs)
    report.subs = C_NULL
    nothing
end

Base.isopen(report::IOReport) = report.subs != C_NULL

function IOReport()
    chan = cfio_get_chan()
    subs = C_NULL
    subscribed_chan = C_NULL
    try
        subs, subscribed_chan = cfio_get_subs(chan)
        cfrelease(chan)
        chan = C_NULL
        report = IOReport(subs, subscribed_chan, nothing)
        subs = C_NULL
        subscribed_chan = C_NULL
        finalizer(close, report)
        return report
    catch
        cfrelease(subscribed_chan)
        cfrelease(subs)
        cfrelease(chan)
        rethrow()
    end
end

function get_samples(report::IOReport, duration::UInt64, count::UInt64)
    isopen(report) || throw(ArgumentError("cannot sample a closed IOReport"))
    c = clamp(count, 1, 32)
    result = Vector{Tuple{IOReportIterator,UInt64}}(undef, c)
    step_msec = duration / c
    step_sec = step_msec / 1000

    previous = report.prev === nothing ? raw_sample(report) : report.prev
    # Transfer ownership of the previous sample to this call. If sampling is
    # interrupted, the report must not retain a pointer that this function has
    # already released.
    report.prev = nothing
    prev_sample::CFDictionaryRef = previous[1]
    prev_time::Float64 = previous[2]
    completed = 0

    try
        for i = 1:c
            next_sample::CFDictionaryRef = C_NULL
            delta::CFDictionaryRef = C_NULL
            try
                sleep(step_sec)
                next_sample, next_time = raw_sample(report)
                delta = IOReportCreateSamplesDelta(prev_sample, next_sample, C_NULL)
                delta == C_NULL && error("Failed to create IOReport sample delta")
                elapsed = (next_time - prev_time) * 1000
                sample_dt = max(round(UInt64, elapsed), 1)
                result[i] = (IOReportIterator(delta), sample_dt)
                delta = C_NULL
                completed = i

                cfrelease(prev_sample)
                prev_sample = next_sample
                next_sample = C_NULL
                prev_time = next_time
            finally
                cfrelease(delta)
                cfrelease(next_sample)
            end
        end

        report.prev = (prev_sample, prev_time)
        prev_sample = C_NULL
        return result
    catch
        for i = 1:completed
            close(result[i][1])
        end
        rethrow()
    finally
        cfrelease(prev_sample)
    end
end

function raw_sample(report::IOReport)::Tuple{CFDictionaryRef,Float64}
    samples = IOReportCreateSamples(report.subs, report.chan, C_NULL)
    return (samples, time())
end
