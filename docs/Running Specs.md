# How To Run Specs

Our CI provider (Travis) doesn't run specs for this repo because it's public. We absolutely need to ensure that specs pass in order to review changesets for this repo, and some environments (e.g. M1 Macs) can't run older versions of Ruby. To handle this situation, we've added a Docker-based worfklow to make it easy in those cases.

1. Make sure you have GNU Make & Docker installed
1. Run `make dev-specs`

Note that this will populate your local `vendor/bundle`, which you can use for reference when debugging/iterating.
