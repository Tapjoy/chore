# How To Release Chore

## Non-Tapjoy Contributors

1. Open a PR against the main branch (currently `master`) with the changes in it
    - make sure to update the [version](../lib/chore/version.rb)!

1. Tag (at least) a Tapjoy engineer for review when the PR is ready
   (see [Contributors](https://github.com/Tapjoy/chore/graphs/contributors) page)

1. Assuming the PR is accepted, a Tapjoy engineer will cut a release with the changes.

## Tapjoy Engineers

Once a PR has been reviewed and accepted for release

1. Merge the PR into the main branch

1. [Create a new GitHub Release](https://github.com/Tapjoy/chore/releases/new) based on the updated main branch and tag
   it with the appropriate version (e.g. v4.0.0). Make sure to provide a useful title (PR title, for example) and
   description.

    A new release should subsequently show up in the GitHub [Releases](https://github.com/Tapjoy/chore/releases) page

1. Generate and publish YARD documentation

    ```
    # Generate the docs from the updated main branch, then switch to the gh-pages branch and copy updated code
    bundle exec rake yard
    git checkout gh-pages
    cp -af rdoc/* .
    git add . # Make sure to remove any unwanted changes that weren't captured in the `.gitignore` before moving on
    git commit -m "${VERSION} documentation" # Make sure to substitute the version!
    git push
    ```

    The [Chore Github Pages](https://tapjoy.github.io/chore) site should be updated with the updated documentation.

1. Build and publish the new gem to RubyGems

    ```
    gem build chore-core.gemspec
    # Do the push from a version of Ruby >= 2.6, as they have much better tooling for this
    gem push chore-core-${GEM_VERSION}.gem
    ```
