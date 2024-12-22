# build-aur-packages

Github Action that builds AUR packages and provides the built packages as
package repository in the github workspace.
From there, other actions can use the package repository to install packages or
upload the repository to some share or ...

See
[here for a real world example](https://github.com/kopp/aurci2).

Usage:
Use this in a job that allows to run dockers (e.g. linux machine) like this:

```yaml
jobs:
  build_repository:
    runs-on: ubuntu-latest
    steps:
    - name: Build Packages
      uses: kopp/build-aur-packages@v1
      with:
        packages: >
          azure-cli
          kwallet-git
          micronucleus-git
        missing_pacman_dependencies: >
          libusb-compat
```

This example will build packages

```
          azure-cli
          kwallet-git
          micronucleus-git
```

Since the package `micronucleus-git` has the dependencies not properly
declared, you can force `pacman` to install the missing dependency by passing
it to `missing_pacman_dependencies`.
If a dependency from AUR is missing, you can pass this to
`missing_aur_dependencies`.

The resulting repository information will be copied to the github workspace.


# Maintenance

## Update GPG key

It will be necessary to update the gpg key stored in this repository.
To do so, run

    gpg --export --armor 6BC26A17B9B7018A > gpg_key_6BC26A17B9B7018A.gpg.asc


## Update tag

The tags should only change if the API (i.e. the yaml description parameter for
the action) changes.
Hence when the Dockerfile needs to be adapted because some package needs a fix,
the tag(s) should be re-set to the commit fixing the issue.
To achieve that, use (e.g. for `v1`):

    git push origin :refs/tags/v1
    git tag -fa v1
    git push origin master --tags



# Development

To build a package and create the corresponding repository files, build the docker image

    docker build -t builder .

then run it, passing the packages as environment variables.
The names of the variables are derived from the `action.yaml`.

    mkdir workspace
    docker run --rm -it \
        -v $(pwd)/workspace:/workspace \
        -e "GITHUB_WORKSPACE=/workspace" -e "INPUT_PACKAGES=go-do" \
        builder


## How this works

This repository contains/provides a github action.
This is defined in [`action.yaml`](./action.yaml), in particular this defines the inputs
and that this action uses `docker` by building and running [`Dockerfile`](./Dockerfile).

The Docker image we build is an Arch Linux image, with some tweaks to `pacman`
and related tools so that they run on github workers.
It will build `aurutils` and use it to create a new package database `aurci2`.
This local database is directly added as local repository to `pacman` (via `pacman.conf`).

After this is done, the docker image is ready.
When the docker container is executed, it runs [`update_repository.sh`](./update_repository.sh).
This will pick up all inputs from the github action (which are passed as environmen variables)
`INPUT_<name>`.
It will then install dependencies via `pacman` and use `aur sync` to fetch and build aur
packages.
They are added to the `aurci2` local database.

Finally, all files (in particular including the database files) are copied to the
`$GITHUB_WORKSPACE`, where other actions can pick them up, e.g. as in
[this example](https://github.com/kopp/aurci2/blob/master/.github/workflows/build_repository.yaml)
where they are published as github release.