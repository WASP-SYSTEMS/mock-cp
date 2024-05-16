# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased] – 2024-MM-DD

### Changed

- Updated `mock-cp-src` repo reference to tag v1.1.0.

## [2.0.3] – 2024-05-16

### Added

- Made GitHub actions generate and publish a docker image that is referenced
  in the `project_yaml` file in the `docker_image` field.
- Added a `.dockerignore` file to the repo.

## [2.0.2] – 2024-05-14

### Fixed

- Fixed incorrect `address` field in `project.yaml`.

## [2.0.1] – 2024-05-14

### Changed

- Switched from https to ssh in `project.yaml` file's `address` field.

## [2.0.0] – 2024-05-14

First release of the AIxCC Mock Challenge Project, which is
compliant with CP Sandbox v2.0.0.

<!-- markdownlint-disable-file MD024 -->
