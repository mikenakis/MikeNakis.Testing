#!/bin/bash

source $(dirname "$0")/definitions.bash > /dev/null

function run()
{
	run_this_script_in_its_directory

	declare -l part_to_increment=""
	declare dry_run=false

	while [ $# -gt 0 ]; do
		case "$1" in
			--increment=*)
				part_to_increment="${1#*=}"
				;;
			--dry-run)
				dry_run=true
				;;
			*)
				error "Invalid argument: '$1'"
				exit 1
		esac
		shift
	done

	if [ ! -f *.sln? ]; then
		error "Current directory is not a solution directory."
		exit 1
	fi

	assert_no_staged_but_uncommitted_changes

	declare -r version_file_pathname=$(realpath version.txt)
	declare -r previous_version=$(cat "$version_file_pathname")

	IFS=- read -r current_version pre_release <<< "$previous_version"
	if [[ "$pre_release" != "PreRelease" ]]; then
		error "The version '$previous_version' is not a pre-release version! This should never happen!"
		exit 1
	fi

	declare -r next_version="$(increment_version "$current_version" "$part_to_increment")-PreRelease"

	info "Previous version: $previous_version"
	info "Current version:  $current_version"
	info "Next version:     $next_version"
	declare -r version_tag_name="$current_version"

	[[ $dry_run == true ]] && return

	printf "$current_version" >| "$version_file_pathname"
	git add "$version_file_pathname"
	git commit --quiet --message="Release of version $current_version"
	git tag "$version_tag_name"
	info "Pushing current version and tag..."
	# PEARL: GitHub will execute an "on: push" workflow twice, on the exact same commit, if we push both files and tags
	#    using a command like `git push origin HEAD  --tags`. Several hours of troubleshooting and trying various tricks
	#    yielded no solution: the '--atomic' option has no effect, either with '--tags' or with the explicit tag name.
    #    The only solution seems to be to specify that the workflow must run on branches, which excludes tags.
	git push --quiet origin HEAD
	git push --tags

	# declare -r wait_time="45s"
	# info "Waiting for $wait_time..."
	# sleep "$wait_time"

	printf "$next_version" >| "$version_file_pathname"
	git add "$version_file_pathname"
	# PEARL: Still as of 2025 GitHub does not support `git push -o ci.skip`. So, we have to use `[skip ci]` in the
	#    commit message, which is the only thing that works on both GitHub and GitLab.
	git commit --quiet --message="Increment version to $next_version [skip ci]"
	info "Pushing next version..."
	git push --quiet origin HEAD
}

run $@
