# Experimental undershot waterwheel calculation

This pure native calculation relates a trusted local water sample to a signed
shaft rate. The lower rim must enter water without striking its bed; horizontal
flow along the axle has no effect, and reversing tangential flow reverses the
shaft. Rate scales with tangential speed and inversely with radius. Water above
the axle is outside this simple undershot approximation. It is not a fluid,
torque, load or paddle simulation.

This component is not yet connected to the World, the river, construction,
checkpoint restoration or the view. The caller must supply spatially valid water
samples and compatible units. No gameplay or rendered result is established by
its standalone controls.
