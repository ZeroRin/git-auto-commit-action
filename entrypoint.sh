#!/bin/bash

set -eu

if "$INPUT_DISABLE_GLOBBING"; then
    set -o noglob;
fi

_main() {
    _check_if_git_is_available

    _switch_to_repository

    if _git_is_dirty || "$INPUT_SKIP_DIRTY_CHECK"; then

        # Check if $GITHUB_OUTPUT is available
        # (Feature detection will be removed in late December 2022)
        if [ -z ${GITHUB_OUTPUT+x} ]; then
            echo "::set-output name=changes_detected::true";
        else
            echo "changes_detected=true" >> $GITHUB_OUTPUT;
        fi

        _switch_to_branch

        _add_files

        if [ -n "$(git diff --staged)" ] || "$INPUT_SKIP_DIRTY_CHECK"; then
            _local_commit

            _tag_commit

        else

            # Check if $GITHUB_OUTPUT is available
            # (Feature detection will be removed in late December 2022)
            if [ -z ${GITHUB_OUTPUT+x} ]; then
                echo "::set-output name=changes_detected::false";
            else
                echo "changes_detected=false" >> $GITHUB_OUTPUT;
            fi

            echo "Working tree clean. Nothing to commit.";
        fi
    else

        # Check if $GITHUB_OUTPUT is available
        # (Feature detection will be removed in late December 2022)
        if [ -z ${GITHUB_OUTPUT+x} ]; then
            echo "::set-output name=changes_detected::false";
        else
            echo "changes_detected=false" >> $GITHUB_OUTPUT;
        fi

        echo "Working tree clean. Nothing to commit.";
    fi
    _push_to_github
}

_check_if_git_is_available() {
    if hash -- "$INPUT_INTERNAL_GIT_BINARY" 2> /dev/null; then
        echo "::debug::git binary found.";
    else
        echo "::error ::git-auto-commit could not find git binary. Please make sure git is available."
        exit 1;
    fi
}

_switch_to_repository() {
    echo "INPUT_REPOSITORY value: $INPUT_REPOSITORY";
    cd "$INPUT_REPOSITORY";
}

_git_is_dirty() {
    echo "INPUT_STATUS_OPTIONS: ${INPUT_STATUS_OPTIONS}";
    echo "::debug::Apply status options ${INPUT_STATUS_OPTIONS}";

    echo "INPUT_FILE_PATTERN: ${INPUT_FILE_PATTERN}";
    read -r -a INPUT_FILE_PATTERN_EXPANDED <<< "$INPUT_FILE_PATTERN";

    # shellcheck disable=SC2086
    [ -n "$(git status -s $INPUT_STATUS_OPTIONS -- ${INPUT_FILE_PATTERN_EXPANDED:+${INPUT_FILE_PATTERN_EXPANDED[@]}})" ]
}

_switch_to_branch() {
    echo "INPUT_BRANCH value: $INPUT_BRANCH";

    # Fetch remote to make sure that repo can be switched to the right branch.
    if "$INPUT_SKIP_FETCH"; then
        echo "::debug::git-fetch has not been executed";
    else
        git fetch --depth=1;
    fi

    # If `skip_checkout`-input is true, skip the entire checkout step.
    if "$INPUT_SKIP_CHECKOUT"; then
        echo "::debug::git-checkout has not been executed";
    else
        # Create new local branch if `create_branch`-input is true
        if "$INPUT_CREATE_BRANCH"; then
            # shellcheck disable=SC2086
            git checkout -B $INPUT_BRANCH --;
        else
            # Switch to branch from current Workflow run
            # shellcheck disable=SC2086
            git checkout $INPUT_BRANCH --;
        fi
    fi
}

_add_files() {
    echo "INPUT_ADD_OPTIONS: ${INPUT_ADD_OPTIONS}";
    echo "::debug::Apply add options ${INPUT_ADD_OPTIONS}";

    echo "INPUT_FILE_PATTERN: ${INPUT_FILE_PATTERN}";
    read -r -a INPUT_FILE_PATTERN_EXPANDED <<< "$INPUT_FILE_PATTERN";

    # shellcheck disable=SC2086
    git add ${INPUT_ADD_OPTIONS} ${INPUT_FILE_PATTERN:+"${INPUT_FILE_PATTERN_EXPANDED[@]}"};
}

_local_commit() {
    echo "INPUT_COMMIT_OPTIONS: ${INPUT_COMMIT_OPTIONS}";
    echo "::debug::Apply commit options ${INPUT_COMMIT_OPTIONS}";

    # shellcheck disable=SC2206
    INPUT_COMMIT_OPTIONS_ARRAY=( $INPUT_COMMIT_OPTIONS );

    echo "INPUT_COMMIT_USER_NAME: ${INPUT_COMMIT_USER_NAME}";
    echo "INPUT_COMMIT_USER_EMAIL: ${INPUT_COMMIT_USER_EMAIL}";
    echo "INPUT_COMMIT_MESSAGE: ${INPUT_COMMIT_MESSAGE}";
    echo "INPUT_COMMIT_AUTHOR: ${INPUT_COMMIT_AUTHOR}";

    git -c user.name="$INPUT_COMMIT_USER_NAME" -c user.email="$INPUT_COMMIT_USER_EMAIL" \
        commit -m "$INPUT_COMMIT_MESSAGE" \
        --author="$INPUT_COMMIT_AUTHOR" \
        ${INPUT_COMMIT_OPTIONS:+"${INPUT_COMMIT_OPTIONS_ARRAY[@]}"};


    # Check if $GITHUB_OUTPUT is available
    # (Feature detection will be removed in late December 2022)
    if [ -z ${GITHUB_OUTPUT+x} ]; then
        echo "::set-output name=commit_hash::$(git rev-parse HEAD)";
    else
        echo "commit_hash=$(git rev-parse HEAD)" >> $GITHUB_OUTPUT;
    fi
}

_tag_commit() {
    echo "INPUT_TAGGING_MESSAGE: ${INPUT_TAGGING_MESSAGE}"

    if [ -n "$INPUT_TAGGING_MESSAGE" ]
    then
        echo "::debug::Create tag $INPUT_TAGGING_MESSAGE";
        git -c user.name="$INPUT_COMMIT_USER_NAME" -c user.email="$INPUT_COMMIT_USER_EMAIL" tag -a "$INPUT_TAGGING_MESSAGE" -m "$INPUT_TAGGING_MESSAGE";
    else
        echo "No tagging message supplied. No tag will be added.";
    fi
}

_push_to_github() {

    echo "INPUT_PUSH_OPTIONS: ${INPUT_PUSH_OPTIONS}";
    echo "::debug::Apply push options ${INPUT_PUSH_OPTIONS}";

    # shellcheck disable=SC2206
    INPUT_PUSH_OPTIONS_ARRAY=( $INPUT_PUSH_OPTIONS );

    if [ -z "$INPUT_BRANCH" ]
    then
        # Only add `--tags` option, if `$INPUT_TAGGING_MESSAGE` is set
        if [ -n "$INPUT_TAGGING_MESSAGE" ]
        then
            echo "::debug::git push origin --tags";
            git push origin --follow-tags --atomic ${INPUT_PUSH_OPTIONS:+"${INPUT_PUSH_OPTIONS_ARRAY[@]}"};
        else
            echo "::debug::git push origin";
            git push origin ${INPUT_PUSH_OPTIONS:+"${INPUT_PUSH_OPTIONS_ARRAY[@]}"};
        fi

    else
        echo "::debug::Push commit to remote branch $INPUT_BRANCH";
        git push --set-upstream origin "HEAD:$INPUT_BRANCH" --follow-tags --atomic ${INPUT_PUSH_OPTIONS:+"${INPUT_PUSH_OPTIONS_ARRAY[@]}"};
    fi
}

_main
