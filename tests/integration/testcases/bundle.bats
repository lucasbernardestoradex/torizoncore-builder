load 'bats/bats-support/load.bash'
load 'bats/bats-assert/load.bash'
load 'bats/bats-file/load.bash'
load 'lib/common.bash'

@test "bundle: check help output" {
    run torizoncore-builder bundle --help
    assert_success
    assert_output --partial 'usage: torizoncore-builder bundle'
}

@test "bundle: check removed parameters" {
    run torizoncore-builder bundle --host-workdir "$(pwd)"
    assert_failure
    assert_output --partial 'the switch --host-workdir has been removed'

    run torizoncore-builder bundle --registry "index.docker.io"
    assert_failure
    assert_output --partial \
        'the switches --docker-username, --docker-password and --registry have been removed'

    run torizoncore-builder bundle --docker-username "USERNAME"
    assert_failure
    assert_output --partial \
        'the switches --docker-username, --docker-password and --registry have been removed'

    run torizoncore-builder bundle --docker-password "PASSWORD*"
    assert_failure
    assert_output --partial \
        'the switches --docker-username, --docker-password and --registry have been removed'
}

@test "bundle: check output directory overwriting" {
    local if_ci=""
    # Use a basic compose file.
    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose.yml" "$COMPOSE"

    if [ "$TCB_UNDER_CI" = "1" ]; then
        if_ci="1"
    fi

    # Test with an existing output directory and default name.
    local BUNDLEDIR='bundle'
    rm -fr $BUNDLEDIR && mkdir $BUNDLEDIR
    run torizoncore-builder bundle "$COMPOSE"
    assert_failure
    assert_output --partial "Bundle directory '$BUNDLEDIR' already exists"

    # Test with an existing output directory and non-default name.
    local BUNDLEDIR='bundle-non-default'
    rm -fr $BUNDLEDIR && mkdir $BUNDLEDIR
    run torizoncore-builder bundle --bundle-directory "$BUNDLEDIR" "$COMPOSE"
    assert_failure
    assert_output --partial "Bundle directory '$BUNDLEDIR' already exists"
    rm -fr "$BUNDLEDIR"

    # Test with an non-existing bundle directory.
    local BUNDLEDIR='bundle'
    rm -fr $BUNDLEDIR
    run torizoncore-builder bundle "$COMPOSE" \
        ${if_ci:+"--login" "$CI_DOCKER_HUB_PULL_USER" "$CI_DOCKER_HUB_PULL_PASSWORD"}
    assert_success
    assert_output --partial "Successfully created Docker Container bundle in \"$BUNDLEDIR\""

    if [ "$TCB_UNDER_CI" = "1" ]; then
        assert_output --partial "Attempting to log in to"
    fi

    # Finally force previous output to be overwritten.
    run torizoncore-builder bundle --force "$COMPOSE" \
        ${if_ci:+"--login" "$CI_DOCKER_HUB_PULL_USER" "$CI_DOCKER_HUB_PULL_PASSWORD"}
    assert_success
    assert_output --partial "Successfully created Docker Container bundle in \"$BUNDLEDIR\""
    rm -fr $BUNDLEDIR
}

@test "bundle: check --file parameter" {
    # Test with deprecated parameter.
    local BUNDLEDIR='bundle'
    local COMPOSE='docker-compose.yml'
    rm -fr "$BUNDLEDIR"
    rm -f "$COMPOSE"
    run torizoncore-builder bundle --file "$(pwd)"
    assert_failure
    assert_output --partial 'the switch --file (-f) has been removed'

    # Test with a missing compose file.
    local BUNDLEDIR='bundle'
    local COMPOSE='docker-compose.yml'
    rm -fr "$BUNDLEDIR"
    rm -f "$COMPOSE"
    run torizoncore-builder bundle "$COMPOSE"
    assert_failure
    assert_output --partial "Could not load the Docker compose file '$COMPOSE'"
}

@test "bundle: check --platform parameter" {
    local if_ci=""
    # Use a basic compose file.
    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose.yml" "$COMPOSE"

    if [ "$TCB_UNDER_CI" = "1" ]; then
        if_ci="1"
    fi

    # Test with platform employed on 32-bit architectures.
    local BUNDLEDIR='bundle'
    local PLATFORM='linux/arm/v7'
    rm -fr "$BUNDLEDIR"
    run torizoncore-builder --log-level debug bundle --platform "$PLATFORM" "$COMPOSE" \
        ${if_ci:+"--login" "$CI_DOCKER_HUB_PULL_USER" "$CI_DOCKER_HUB_PULL_PASSWORD"}
    assert_success
    assert_output --partial "Default platform: $PLATFORM"

    if [ "$TCB_UNDER_CI" = "1" ]; then
        assert_output --partial "Attempting to log in to"
    fi

    # Test with platform employed on 64-bit architectures.
    local BUNDLEDIR='bundle'
    local PLATFORM='linux/arm64'
    rm -fr "$BUNDLEDIR"
    run torizoncore-builder --log-level debug bundle --platform "$PLATFORM" "$COMPOSE" \
        ${if_ci:+"--login" "$CI_DOCKER_HUB_PULL_USER" "$CI_DOCKER_HUB_PULL_PASSWORD"}
    assert_success
    assert_output --partial "Default platform: $PLATFORM"

    # Test with an unexisting platform.
    local BUNDLEDIR='bundle'
    local PLATFORM='dummy-platform'
    rm -fr "$BUNDLEDIR"
    run torizoncore-builder --log-level debug bundle --platform "$PLATFORM" "$COMPOSE" \
        ${if_ci:+"--login" "$CI_DOCKER_HUB_PULL_USER" "$CI_DOCKER_HUB_PULL_PASSWORD"}
    assert_failure
    assert_output --partial "container images download failed"

    if [ "$TCB_UNDER_CI" = "1" ]; then
        assert_output --partial "Attempting to log in to"
    fi
}

@test "bundle: check without --bundle-directory parameter" {
    local if_ci=""
    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose.yml" "$COMPOSE"

    if [ "$TCB_UNDER_CI" = "1" ]; then
        if_ci="1"
    fi

    rm -rf bundle
    run torizoncore-builder bundle "$COMPOSE" \
        ${if_ci:+"--login" "$CI_DOCKER_HUB_PULL_USER" "$CI_DOCKER_HUB_PULL_PASSWORD"}
    assert_success

    if [ "$TCB_UNDER_CI" = "1" ]; then
        assert_output --partial "Attempting to log in to"
    fi

    run ls -l bundle/$COMPOSE
    assert_success
    run ls -l bundle/docker-storage.tar.xz
    assert_success

    rm -f "$COMPOSE"
    rm -rf bundle
}

@test "bundle: check with --bundle-directory parameter" {
    local if_ci=""
    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose.yml" "$COMPOSE"
    local BUNDLE_DIR=$(mktemp -d -u tmpdir.XXXXXXXXXXXXXXXXXXXXXXXXX)

    if [ "$TCB_UNDER_CI" = "1" ]; then
        if_ci="1"
    fi

    run torizoncore-builder bundle --bundle-directory "$BUNDLE_DIR" "$COMPOSE" \
        ${if_ci:+"--login" "$CI_DOCKER_HUB_PULL_USER" "$CI_DOCKER_HUB_PULL_PASSWORD"}
    assert_success

    if [ "$TCB_UNDER_CI" = "1" ]; then
        assert_output --partial "Attempting to log in to"
    fi

    run ls -l $BUNDLE_DIR/$COMPOSE
    assert_success
    run ls -l $BUNDLE_DIR/docker-storage.tar.xz
    assert_success

    check-file-ownership-as-workdir "$BUNDLE_DIR"
    check-file-ownership-as-workdir "$BUNDLE_DIR/docker-storage.tar.xz"

    rm -f "$COMPOSE"
    rm -rf "$BUNDLE_DIR"
}
