using ObjectiveC.CoreFoundation: CFStringRef, CFString, CFDictionaryRef

const CFTypeRef = Ptr{Cvoid}
const CFArrayRef = Ptr{Cvoid}
const CFMutableDictionaryRef = CFDictionaryRef
const CFDataRef = Ptr{Cvoid}
# A small CFRange struct used in CFDataGetBytes
struct CFRange
    location::Clong
    length::Clong
end