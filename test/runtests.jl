using Test
using ReTestItems
using MacOSIOReport

if Sys.isapple() && Sys.ARCH == :aarch64
	ReTestItems.runtests(MacOSIOReport)
else
	@test true
end
