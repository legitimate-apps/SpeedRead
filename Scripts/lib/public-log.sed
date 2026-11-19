# Applied to xcodebuild output before a lane script prints it. CI logs on this repo are public.
#
# When a destination cannot be matched, xcodebuild lists every device it can see. On a runner
# that also serves as someone's desk Mac, that list includes their own iPhone and iPad by name
# and hardware id. Simulators are kept (they are what the reader needs to debug the lane);
# every other destination line is replaced.
/{ platform:[^,}]*Simulator/b
s/{ platform:.*/{ physical device: hidden from public CI logs }/
