#!/bin/bash

set -e # magical incantation to immediately exit if any command has a non-zero exit status. PEARL: it still won't fail if any of the following `set` commands fails.
set -u # magical incantation to mmediately exit if an undefined variable is referenced.
set -o pipefail # magical incantation to prevent pipelines from masking errors. (Use `command1 | command2 || true` to mask.)
shopt -s extglob # magical incantation to enable extended pattern matching.

# set -x # magical incantation to enable echoing commands for the purpose of troubleshooting.

function increment_version()
{
	local part_to_increment=$1
	local version=$2
	local major
	local minor
	local patch

	IFS=. read -r major minor patch <<< "$version"
	case "$part_to_increment" in
		"increment_major")
			major=$((major+1))
			minor=0
			patch=0
			;;
		"increment_minor")
			minor=$((minor+1))
			patch=0
			;;
		"increment_patch")
			patch=$((patch+1))
			;;
		*)
			printf "%s: Invalid argument: '%s'\n" "$0" "$1"
			return 1 # does this cause the script to fail?
	esac
	printf "%s.%s.%s" "$major" "$minor" "$patch"
}

function create_next_version()
{
	local part_to_increment=$1
	local version=$2

	local next_version=$(increment_version "$part_to_increment" "$version")
	printf "old version: %s new version: %s\n" "$version" "$next_version"
	printf "%s" "$next_version" > version.txt
	git add version.txt
	git commit --message="increment version from $version to $next_version"
}

function write_and_commit_version_file()
{
	local version=$1
	local next_version=$2

	printf "old version: %s new version: %s\n" "$version" "$next_version"
	printf "%s" "$next_version" > version.txt
	git add version.txt
	git commit --message="increment version from $version to $next_version"
}

function assert_no_untracked_files()
{
	local untracked_files=$(git ls-files -o --directory --exclude-standard --no-empty-directory)
	if [ "$untracked_files" != "" ]; then
		echo "You have untracked files:"
		echo $untracked_files
		echo "Please add, stage, and commit first."
		return 1
	fi
}

function assert_no_tracked_but_unstaged_changes()
{
	local unstaged_files=$(git diff-files --name-only)
	if [ "$unstaged_files" != "" ]; then
		echo "You have tracked but unstanged changes:"
		echo $unstaged_files
		echo "Please stage and commit first."
		return 1
	fi
}

function assert_no_staged_but_uncommitted_changes()
{
	local uncommitted_files=$(git diff-index --name-only --cached HEAD)
	if [ "$uncommitted_files" != "" ]; then
		echo "You have staged but uncommitted changes:"
		echo $uncommitted_files
		echo "Please unstage or commit first."
		return 1
	fi
}

function remove_quietly()
{
	local file=$1
	if [ -f "$file" ]; then
		rm "$file"
	fi
}

function do_build()
{
	local configuration=$1
	dotnet build -check --configuration $configuration --verbosity normal
}

function do_test()
{
	dotnet test -check --configuration Debug --verbosity normal
}

function do_pack()
{
	local configuration=$1
	remove_quietly ${project_name}/bin/${configuration}/*.nupkg
	dotnet pack -check --configuration ${configuration} --property:PublicRelease=true
}

function do_push_to_github_packages()
{
	local configuration=$1
	do_pack ${configuration}
	dotnet nuget push ${project_name}/bin/${configuration}/*.nupkg --source https://nuget.pkg.github.com/MikeNakis/index.json --api-key ${github_packages_nuget_api_key}
}

function do_push_to_nuget_org()
{
	local configuration=$1
	do_pack ${configuration}
	dotnet nuget push ${project_name}/bin/${configuration}/*.nupkg --source https://api.nuget.org/v3/index.json --api-key ${nuget_org_nuget_api_key}
}

function do_increment_version()
{
	local version=$(cat version.txt)
	git tag "$version"
	create_next_version increment_patch $version
	printf "Pushing version.txt and tag...\n"
	git push origin HEAD --tags
}

function get_xml_value()
{
	local file=$1
	local element=$2

	# From Stack Overflow: "Extract XML Value in bash script" https://stackoverflow.com/a/17334043/773113
	cat ${file} | sed -ne "/${element}/{s/.*<${element}>\(.*\)<\/${element}>.*/\1/p;q;}"
}

# Parse command-line arguments
while [ $# -gt 0 ]; do
	case "$1" in
		Command=*)
			declare -l command="${1#*=}"
			;;
		ProjectName=*)
			project_name="${1#*=}"
			;;
		GitHubPackagesNuGetApiKey=*)
			github_packages_nuget_api_key="${1#*=}"
			;;
		NuGetOrgNuGetApiKey=*)
			nuget_org_nuget_api_key="${1#*=}"
			;;
		*)
			printf "%s: Invalid argument: '%s'\n" "$0" "$1"
			exit 1
	esac
	shift
done

case "$command" in
	"auto")
		;;
	"manual")
		;;
	*)
		printf "%s: Unknown command: '%s'\n" "$0" "$command"
		exit 1
esac

if [ ! -f *.sln? ]; then
	printf "%s: Current directory is not a solution directory.\n" "$0"
fi

project_file=${project_name}/${project_name}.csproj
if [ ! -f ${project_file} ]; then
	printf "%s: Project file not found: %s.\n" "$0" "${project_file}"
fi

# PEARL: In MSBuild, a missing <OutputType> element defaults to 'Lib'; however, a present but empty <OutputType> element
#    appears to default to 'Exe'! (WTF?)
# Note that we are not accounting for a present but empty <OutputType> element here.
declare -l output_type=$(get_xml_value ${project_file} OutputType)
printf "%s: output_type='%s'.\n" "$0" "${output_type}"

declare -l pack_as_tool=$(get_xml_value ${project_file} PackAsTool)
printf "%s: pack_as_tool='%s'.\n" "$0" "${pack_as_tool}"

assert_no_staged_but_uncommitted_changes

do_build Debug
do_test # builds and tests the Debug configuration

do_build Develop
do_build Release

if [[ "$output_type" == "" || "$output_type" == "lib" ]]; then

	if [[ "$command" == "auto" ]]; then
		do_push_to_github_packages Develop
	else
		do_push_to_nuget_org Develop
	fi

	if [[ "$command" == "auto" ]]; then
		do_push_to_github_packages Release
	else
		do_push_to_nuget_org Release
	fi

elif [[ "$output_type" == "exe" && "$pack_as_tool" == "true" ]]; then

	if [[ "$command" == "auto" ]]; then
		do_push_to_github_packages Release
	else
		do_push_to_nuget_org Release
	fi

fi

do_increment_version
