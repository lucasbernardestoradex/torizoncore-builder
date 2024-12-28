bats_load_library 'bats/bats-support/load.bash'
bats_load_library 'bats/bats-assert/load.bash'
bats_load_library 'bats/bats-file/load.bash'
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
    local ci_dockerhub_login="$(ci-dockerhub-login-flag)"

    # Use a basic compose file.
    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose.yml" "$COMPOSE"

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
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"}
    assert_success
    assert_output --partial "Successfully created Docker Container bundle in \"$BUNDLEDIR\""

    if [ "${ci_dockerhub_login}" = "1" ]; then
        assert_output --partial "Attempting to log in to"
    fi

    # Finally force previous output to be overwritten.
    run torizoncore-builder bundle --force "$COMPOSE" \
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"}
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
    assert_output --partial "File does not exist: $COMPOSE"
}

@test "bundle: check --platform parameter" {
    local ci_dockerhub_login="$(ci-dockerhub-login-flag)"

    # Use a basic compose file.
    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose.yml" "$COMPOSE"

    # Test with platform employed on 32-bit architectures.
    local BUNDLEDIR='bundle'
    local PLATFORM='linux/arm/v7'
    rm -fr "$BUNDLEDIR"
    run torizoncore-builder --log-level debug bundle --platform "$PLATFORM" "$COMPOSE" \
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"}
    assert_success
    assert_output --partial "Default platform: $PLATFORM"

    if [ "${ci_dockerhub_login}" = "1" ]; then
        assert_output --partial "Attempting to log in to"
    fi

    # Test with platform employed on 64-bit architectures.
    local BUNDLEDIR='bundle'
    local PLATFORM='linux/arm64'
    rm -fr "$BUNDLEDIR"
    run torizoncore-builder --log-level debug bundle --platform "$PLATFORM" "$COMPOSE" \
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"}
    assert_success
    assert_output --partial "Default platform: $PLATFORM"

    # Test with an unexisting platform.
    local BUNDLEDIR='bundle'
    local PLATFORM='dummy-platform'
    rm -fr "$BUNDLEDIR"
    run torizoncore-builder --log-level debug bundle --platform "$PLATFORM" "$COMPOSE" \
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"}
    assert_failure
    assert_output --partial "container images download failed"

    if [ "${ci_dockerhub_login}" = "1" ]; then
        assert_output --partial "Attempting to log in to"
    fi
}

@test "bundle: check without --bundle-directory parameter" {
    local ci_dockerhub_login="$(ci-dockerhub-login-flag)"

    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose.yml" "$COMPOSE"

    rm -rf bundle
    run torizoncore-builder bundle "$COMPOSE" \
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"}
    assert_success

    if [ "${ci_dockerhub_login}" = "1" ]; then
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
    local ci_dockerhub_login="$(ci-dockerhub-login-flag)"

    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose.yml" "$COMPOSE"
    local BUNDLE_DIR=$(mktemp -d -u tmpdir.XXXXXXXXXXXXXXXXXXXXXXXXX)

    run torizoncore-builder bundle --bundle-directory "$BUNDLE_DIR" "$COMPOSE" \
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"}
    assert_success

    if [ "${ci_dockerhub_login}" = "1" ]; then
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

@test "bundle: check double dollar sign in compose file" {
    local ci_dockerhub_login="$(ci-dockerhub-login-flag)"
    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose-env-double-dollar-test.yml" "$COMPOSE"
    rm -rf bundle

    # Check if double dollar sign in config values (not keys) is replaced by a single one
    run torizoncore-builder bundle "$COMPOSE" \
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"}
    assert_success
    assert_output --partial "Replacing '\$\$' with '\$'"

    if [ "${ci_dockerhub_login}" = "1" ]; then
        assert_output --partial "Attempting to log in to"
    fi

    run ls -l bundle/$COMPOSE
    assert_success
    run ls -l bundle/docker-storage.tar.xz
    assert_success

    run cat bundle/$COMPOSE
    refute_output --partial "\$\$HOME"
    assert_output --partial "\$\$var: \$HOME"
    rm -rf bundle

    # Check if double dollar sign is NOT replaced if --keep-double-dollar-sign is specified
    run torizoncore-builder bundle --keep-double-dollar-sign "$COMPOSE" \
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"}
    assert_success
    refute_output --partial "Replacing '\$\$' with '\$'"

    if [ "${ci_dockerhub_login}" = "1" ]; then
        assert_output --partial "Attempting to log in to"
    fi

    run ls -l bundle/$COMPOSE
    assert_success
    run ls -l bundle/docker-storage.tar.xz
    assert_success

    run cat bundle/$COMPOSE
    assert_output --partial "\$\$HOME"
    refute_output --partial "\$\$var: \$HOME"

    rm -f "$COMPOSE"
    rm -rf bundle
}

@test "bundle: check --dind-param parameter" {
    local ci_dockerhub_login="$(ci-dockerhub-login-flag)"

    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose.yml" "$COMPOSE"

    # Pass an invalid parameter to DinD and check if it fails.
    rm -rf bundle
    run torizoncore-builder-ex \
        --env "DUMP_DIND_LOGS=1" \
        --\
        bundle "$COMPOSE" \
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"} \
        --dind-param="--invalid-param"
    assert_failure
    assert_output --regexp "Status: unknown flag: --invalid-param"

    rm -f "$COMPOSE"
    rm -rf bundle
}

@test "bundle: check --dind-env parameter" {
    local ci_dockerhub_login="$(ci-dockerhub-login-flag)"

    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose.yml" "$COMPOSE"

    # Set environment variables to ask DinD to access the network through a proxy that is not available.
    rm -rf bundle
    run torizoncore-builder-ex \
        --env "DUMP_DIND_LOGS=1" \
        --\
        bundle "$COMPOSE" \
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"} \
        --dind-env "HTTP_PROXY=http://localhost:33456" \
        --dind-env "HTTPS_PROXY=http://localhost:33456"

    assert_failure
    assert_output --regexp "Error: container images download failed: .*proxyconnect.*:33456: connect: connection refused"

    rm -f "$COMPOSE"
    rm -rf bundle
}

@test "bundle: check environment variable forwarding" {
    local ci_dockerhub_login="$(ci-dockerhub-login-flag)"

    local COMPOSE='docker-compose.yml'
    cp "$SAMPLES_DIR/compose/hello/docker-compose.yml" "$COMPOSE"

    # Set environment variables to ask DinD to access the network through a proxy that is not available.
    rm -rf bundle
    run torizoncore-builder-ex \
        --env "DUMP_DIND_LOGS=1" \
        --env "HTTP_PROXY=http://localhost:33457" \
        --env "HTTPS_PROXY=http://localhost:33457" \
        --env "NO_PROXY=127.0.0.0/8" \
        --env "DIND_FORWARD_VARS=HTTP_PROXY,HTTPS_PROXY" \
        --\
        bundle "$COMPOSE" \
        ${ci_dockerhub_login:+"--login" "${CI_DOCKER_HUB_PULL_USER}" "${CI_DOCKER_HUB_PULL_PASSWORD}"} \

    assert_failure
    assert_output --regexp "Error: container images download failed: .*proxyconnect.*:33457: connect: connection refused"

    rm -f "$COMPOSE"
    rm -rf bundle
}

@test "bundle: check registry pattern" {
    local COMPOSE_FILE="$SAMPLES_DIR/compose/hello/docker-compose.yml"
    local INVALID_REGISTRIES=(
      "http://registry.com"
      "tcp://registry/something"
      "https://registry.com")

    for registry in "${INVALID_REGISTRIES[@]}"; do
      run torizoncore-builder bundle --login-to "${registry}" None None "${COMPOSE_FILE}"
      assert_failure
      assert_output --partial "invalid registry specified"

      run torizoncore-builder bundle --cacert-to "${registry}" None "${COMPOSE_FILE}"
      assert_failure
      assert_output --partial "invalid registry specified"
    done
}
