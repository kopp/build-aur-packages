# build-aur-packages

Github Action that builds AUR packages and provides the built packages as
repository in the workspace.
From there, you can use them to install, upload, ...

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

This example wil build packages

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
