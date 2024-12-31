# Helpers
function zero_div(a::T, b::T) where {T<:Real}
    b == zero(T) ? zero(T) : a / b
end

zero_div(a, b) = zero_div(promote(float(a), float(b))...)
