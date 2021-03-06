# simp-core Acceptance and Integration Tests

This directory contains

* Test suites that can be used to test SIMP in its entirety, including all non ISO components.
* A test suite that builds a SIMP ISO.

| Suite                    | Category    | Description                                                 |
| ------------------------ | ----------- | ----------------------------------------------------------- |
| default                  | Integration | Uses components from `Puppetfile.tracking`                  |
| ipa                      | Integration | Uses components from `Puppetfile.tracking` with IPA clients |
| install_from_rpm         | Release     | Uses RPMs from SIMP's packagecloud.io repos                 |
| install_from_tar         | Release     | Uses RPMs from the tarball built in the ISO build process   |
| install_from_core_module | Release     | Uses the SIMP metamodule and the Puppet Forge               |
| rpm_docker               | Build       | Used to build the SIMP ISO                                  |


## Overview

In general, the SIMP integration/release test suites follow the same general procedure:

1. Spin up 3 vagrant boxes, one puppetserver (EL version changes based on
   nodeset) and two clients (one EL6 and one EL7)
2. Install, start and configure the puppetserver

   * This is the step where most tests are different. See the subsections below
     for more details

3. Add all the agents to the puppetserver, and run `puppet agent -t`
   until there are no more changes
4. Modify the Puppet environment and run additional tests

The SIMP ISO-building test suite spins up a Docker container for the target OS,
builds/download RPMs, and then builds the ISO.

## Running a test suite

1. Set up your environment with a [ruby version manager](https://rvm.io/), [vagrant](https://www.vagrantup.com/), and [VirtualBox](https://www.virtualbox.org/)
2. Install Ruby 2.1.9 (follow the guides from the link above)
3. Install bundler: `gem install bundler`
4. Install other dependencies: `bundle install`
5. If you need to run a test for a different OS or Puppet version, copy the
  environment variables from whichever job matches what you need from the
  `.gitlab-ci.yaml`.
6. Run the tests:

```bash
# to run the default suite on OEL using Puppet 5 and an OEL7 simp server
export PUPPET_VERSION='~> 5.3'
export BEAKER_PUPPET_COLLECTION='puppet5'
export SIMP_BEAKER_OS='oracle'
bundle exec rake beaker:suites[default,el7_server]
```

There are two nodesets per integration/release test suite, `el7_server` and `el6_server`.
They control the version of EL on the puppetserver. The default nodeset is a symlink
to `el7_server`. You can also set `SIMP_BEAKER_OS` to `oracle` to run the tests on OEL.



### `default` Suite

_Install method_: `Puppetfile.tracking` and `r10k`

This test parses the current `Puppetfile.tracking` to make a Puppetfile that's
suitable for a control repo, then uses `r10k` to install the SIMP environment.
It does not use `simp config` or `simp bootstrap`, but instead just runs Puppet
directly.

When the `Puppetfile.tracking` is set to the `master` branches of our component
modules, this test makes sure our most up-to-date code is compatible.



### `ipa` Suite

_Install method_: `Puppetfile.tracking` and `r10k`

This test parses is very similar to the default test above it, except it adds a
new host to be an IPA server and adds all the hosts as clients with the
``simp::ipa::install`` class.

The IPA server has issues on EL6, so the `el6_server` nodeset should not be run
and will not pass.

When the `Puppetfile.tracking` is set to the `master` branches of our component
modules, this test makes sure our most up-to-date code is compatible.



### `install_from_rpm` Suite

_Install method_: RPMs, defaulting to the PackageCloud yum repo

This test attempts to set up two repos:

1. The SIMP repo, containing all the SIMP and the Puppet module RPMs
2. The dependency repo, containing extra RPMs required by SIMP that aren't in
   the CentOS Base repos.

It then installs the `simp` RPM and runs `simp config` and `simp bootstrap`.

Use the following ENV variables to configure the test:

#### `BEAKER_repo`

* **unset** - If unset, the test will use the 6_X repos on PackageCloud
* **fully qualified path** - If set to a fully qualified path, the test will
  assume this is a repo file that contains definitions for both the SIMP
  repo and the SIMP dependencies repo
* **version** - If set, and does not start with `/`, the test will assume it
  is an different version for the SIMP PackageCloud

#### `BEAKER_puppet_repo`

* **unset** - If unset, the repos listed in `BEAKER_repo` include Puppet RPMs.

  * The PackageCloud dependency repo does include a Puppet RPM.

* **true** - The test will install the Puppet `pc1` repo distribution RPMs from
  the root of [yum.puppetlabs.com](yum.puppetlabs.com).



### `install_from_tar` Suite

_Install method_: RPMs from a release tarball

This test attempts to set up two repos:

1. The SIMP repo, containing all the SIMP and the Puppet module RPMs packaged in
   a release tarball.  The release tarball is built as part of an SIMP ISO build.
2. The dependency repo, containing extra RPMs required by SIMP that aren't in
   the CentOS Base repos.

Then, using the repos, it

1. Installs the `simp` RPM and runs `simp config` and `simp bootstrap` on the
   SIMP server
2. Runs `puppet agent -t` on the SIMP server and 2 clients (1 CentOS6, 1 CentOS7)
   until convergence.

In this configuration, one of the clients is also the remote syslog server.

_Tests run_:

1. Verifies rsyslog integration.  Specifically, it stimulates applications
   to generate events of interest, and then verifies the actual application
   messages get logged locally and remotely, as expected.


Use the following ENV variables to configure the test:

#### `BEAKER_repo`

* **unset** - If unset, the test will use the 6_X repos on PackageCloud
* **version** - If set, and does not start with `/`, the test will assume it
  is an different version for the SIMP PackageCloud

#### `BEAKER_release_tarball`

* **unset** - The test will glob for a tarball in the DVD_Overlay directory
  under the `simp-core/build` directory, where the build process would leave it
* **url** - A full URL to a tarball
* **path** - A file location on the machine running this test



### `install_from_core_module` Suite

_Install method_: Puppet Forge, using the `simp/simp_core` metamodule described in `metadata.json`

This test runs `puppet module build` in the root directory of `simp-core`,
building a development version of the `simp/simp_core` metamodule. Then, it spins
up a puppetserver and trys to install the development version of the module,
using the Puppet Forge as a source for all dependent modules. It does not use
`simp config` or `simp bootstrap`, but instead just runs Puppet directly.

NOTE: If there are unreleased components referenced in the `metadata.json` of
the `simp/simp_core` metamodule, the `puppet module install` for the module will
fail.



### `rpm_docker` Suite

This suite is used to build a SIMP ISO. Please see the
[SIMP documentation](https://simp.readthedocs.io/en/master/getting_started_guide/ISO_Build/Building_SIMP_From_Source.html)
for more detailed instructions.
