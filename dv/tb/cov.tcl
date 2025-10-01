# Coverage configuration for xrun

database -open waves -into waves.shm -default
probe -create -all -depth all -database waves
coverage -save cov.ucdb -du design_unit
run
exit
