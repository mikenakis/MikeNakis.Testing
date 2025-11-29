#!/bin/bash

source definitions.bash > /dev/null

declare -r version_file_pathname=$(realpath version.txt)

function concatenate_with_dash
{
	declare result=""
	declare delimiter=""
	while [ $# -gt 0 ]; do
		if [[ ! -z "$1" ]]; then
			printf "%s%s" "$delimiter" "$1"
			delimiter="-"
		fi
		shift
	done
}

function run()
{
	declare branch=$(git branch --show-current)
	if [[ "$branch" == master ]]; then
		branch=""
	fi

	declare -r version=$(cat "$version_file_pathname")
	declare prefix
	declare pre_release
	IFS=- read -r prefix pre_release <<< "$version"

	concatenate_with_dash "$prefix" "$branch" "$pre_release"
}

run $@
