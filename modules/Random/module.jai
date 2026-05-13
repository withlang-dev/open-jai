#scope_export;

random_seed :: (seed: u64) #foreign;
random_get :: () -> u64 #foreign;
random_get_zero_to_one :: () -> float64 #foreign;
random_get_within_range :: (minimum: float64, maximum: float64) -> float64 #foreign;
