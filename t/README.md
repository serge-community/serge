Serge uses 'golden master' testing approach for integration tests.
When making changes to tests, or when modifications to Serge code
expect to bring changes to golden master data (database snapshots,
generated translation interchange files and localized files),
run `./engine.t --init` to update golden master data snapshots,
then examine changes carefully using `git diff`. Golden master
data needs to be committed together with the code changes that
cause data mutation.

Run just `./engine.t` to compare current data with the previously
saved data snapshots and report mismatches.
