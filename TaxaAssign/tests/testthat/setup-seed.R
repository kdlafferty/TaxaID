# Seed the test run so its results do not depend on what ran earlier in the
# same R session. Several tests exercise Monte Carlo paths (n_sims > 0)
# without their own seed; without this, running another package's tests first
# changes the random stream they start from. Assertions are unchanged.
set.seed(20260929)
