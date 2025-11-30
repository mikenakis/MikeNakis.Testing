#!/bin/bash

source definitions.bash > /dev/null

declare -r version_file_pathname=$(realpath version.txt)

function run()
{
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

	case "$part_to_increment" in
		"major")
			;;
		"minor")
			;;
		"patch")
			;;
		"")
			part_to_increment=patch
			;;
		*)
			error "Invalid increment: '$part_to_increment'. Expected 'major', 'minor', or 'patch' (the default.)"
			exit 1
	esac

	if [ ! -f *.sln? ]; then
		error "Current directory is not a solution directory."
		exit 1
	fi

	assert_no_staged_but_uncommitted_changes

	declare -r previous_version=$(cat "$version_file_pathname")
	declare major_minor_patch
	declare pre_release
	IFS=- read -r major_minor_patch pre_release <<< "$previous_version"
	if [[ "$pre_release" != "PreRelease" ]]; then
		error "The version '$previous_version' is not a pre-release version! This should never happen!"
		exit 1
	fi
	declare -i old_major
	declare -i old_minor
	declare -i old_patch
	IFS=. read -r old_major old_minor old_patch <<< "$major_minor_patch"
	printf -v current_version "%s.%s.%s" "$old_major" "$old_minor" "$old_patch"
	if [[ "$current_version" != "$major_minor_patch" ]]; then
		error internal error!
		exit 1
	fi

	declare -i new_major
	declare -i new_minor
	declare -i new_patch
	case "$part_to_increment" in
		"major")
			new_major=$((old_major+1))
			new_minor=0
			new_patch=0
			;;
		"minor")
			new_major=$old_major
			new_minor=$((old_minor+1))
			new_patch=0
			;;
		"patch")
			new_major=$old_major
			new_minor=$old_minor
			new_patch=$((old_patch+1))
			;;
		*)
			error "Invalid increment: '$part_to_increment' expected 'major', 'minor', or 'patch'"
			exit 1
	esac
	printf -v next_version "%s.%s.%s-PreRelease" "$new_major" "$new_minor" "$new_patch"

	echo "Previous version: $previous_version"
	echo "Current version: $current_version"
	echo "Next version: $next_version"

	[[ $dry_run == true ]] && return

	printf "$current_version" >| "$version_file_pathname"
	git add "$version_file_pathname"
	git tag "$current_version"
	git commit --message="Release of version $current_version"
	info "Pushing current version and tag..."
	git push origin HEAD --tags

	# info "Waiting for a few seconds..."
	# sleep 10s

	printf "$next_version" >| "$version_file_pathname"
	# PEARL: Still as of 2025 GitHub does not support `git push -o ci.skip`. So, we have to use `[skip ci]` in the
	#    commit message, which is the only thing that works on both GitHub and GitLab.
	git commit --message="Increment version to $next_version [skip ci]"
	info "Pushing next version..."
	git push origin HEAD
}

run $@
