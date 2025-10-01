# Waveform configuration for xrun

database -open waves -into waves.shm -default
probe -create $env(TOP_MODULE) -depth all -database waves
run
exit
