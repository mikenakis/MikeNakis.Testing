#!/bin/bash

set -o errexit # Fail if any command has a non-zero exit status. Equivalent to `-e`. PEARL: it still won't fail if any of the following `set` commands fails.
set -o nounset # Fail if an undefined variable is referenced. Equivalent to `-u`.
set -o pipefail # Prevent pipelines from masking errors. (Use `command1 | command2 || true` to mask.)
set -C # do not overwrite an existing file when redirecting. use >| instead of > to override.
shopt -s expand_aliases # Do not ignore aliases. (What kind of idiot made ignoring aliases the default behavior?)
#shopt -s extglob # enable extended pattern matching.

# set -x # enable echoing commands for the purpose of troubleshooting.

declare -r version_file_pathname=$(realpath version.txt)

function increment_version()
{
	declare -r part_to_increment=$1
	declare -r version=$2
	declare -i major
	declare -i minor
	declare -i patch

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
			printf "%s: Invalid argument: '%s'\n" "$0" "${part_to_increment}"
			exit 1
	esac
	printf "%s.%s.%s" "$major" "$minor" "$patch"
}

function create_next_version()
{
	declare -r part_to_increment=$1
	declare -r version=$2

	declare -r next_version=$(increment_version "$part_to_increment" "$version")
	printf "old version: %s new version: %s\n" "$version" "$next_version"
	printf "%s" "$next_version" >| ${version_file_pathname}
	git add ${version_file_pathname}
	git commit --message="increment version from $version to $next_version"
}

function assert_no_untracked_files()
{
	declare -r untracked_files=$(git ls-files -o --directory --exclude-standard --no-empty-directory)
	if [ "$untracked_files" != "" ]; then
		echo "You have untracked files:"
		echo $untracked_files
		echo "Please add, stage, and commit first."
		return 1
	fi
}

function assert_no_tracked_but_unstaged_changes()
{
	declare -r unstaged_files=$(git diff-files --name-only)
	if [ "$unstaged_files" != "" ]; then
		echo "You have tracked but unstanged changes:"
		echo $unstaged_files
		echo "Please stage and commit first."
		return 1
	fi
}

function assert_no_staged_but_uncommitted_changes()
{
	declare -r uncommitted_files=$(git diff-index --name-only --cached HEAD)
	if [ "$uncommitted_files" != "" ]; then
		echo "You have staged but uncommitted changes:"
		echo $uncommitted_files
		echo "Please unstage or commit first."
		return 1
	fi
}

function remove_if_exists()
{
	declare -r pattern=$1

	for i in ${pattern}; do
		if [ -f "${i}" ]; then 
			rm "${i}"; 
		fi
	done
}

function do_build()
{
	declare -r configuration=$1

	dotnet build -check --verbosity minimal --configuration ${configuration} --no-restore
}

function do_test()
{
	declare -r configuration=$1

	dotnet test -check --verbosity normal --configuration ${configuration} --no-build
}

function do_publish()
{
	declare -r command=$1
	declare -r configuration=$2
	declare -r project_name=$3
	declare -r github_packages_nuget_api_key=$4
	declare -r nuget_org_nuget_api_key=$5

	declare -r package_pathname=${project_name}/bin/${configuration}/*.nupkg
	echo "${package_pathname}"

	# PEARL: dotnet nuget push will push a package specified using a wildcard, but if the wildcard matches more than one file, then it
	#    will sabotage the developer by failing with a misleading error message that says "File does not exist" instead of "More than
	#    one file exists".  For this reason, we have to remove all files matching the wildcard before creating the package.
	remove_if_exists "${package_pathname}"
	dotnet pack -check --verbosity normal --configuration ${configuration} --no-build --property:PublicRelease=true
	
	ls ${package_pathname} # omit double-quotes to allow expansion

	if [[ "${command}" == "auto" ]]; then
		dotnet nuget push ${package_pathname} --source https://nuget.pkg.github.com/MikeNakis/index.json --api-key ${github_packages_nuget_api_key}
	else
		dotnet nuget push ${package_pathname} --source https://api.nuget.org/v3/index.json --api-key ${nuget_org_nuget_api_key}
	fi
}

function do_increment_version()
{
	declare -r version=$(cat ${version_file_pathname})
	git tag "$version"
	create_next_version increment_patch $version
	printf "Pushing version file and tag...\n"
	git push origin HEAD --tags
}

function get_xml_value()
{
	declare -r file=$1
	declare -r element=$2

	# From Stack Overflow: "Extract XML Value in bash script" https://stackoverflow.com/a/17334043/773113
	cat ${file} | sed -ne "/${element}/{s/.*<${element}>\(.*\)<\/${element}>.*/\1/p;q;}"
}

function run()
{
	declare -l command=""
	declare project_name=""
	declare github_packages_nuget_api_key=""
	declare nuget_org_nuget_api_key=""

	while [ $# -gt 0 ]; do
		case "$1" in
			Command=*)
				command="${1#*=}"
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

	if [ -z "${command}" ]; then
		printf "%s: Missing argument: '%s'\n" "$0" "Command"
		exit 1
	fi

	if [ -z "${project_name}" ]; then
		printf "%s: Missing argument: '%s'\n" "$0" "ProjectName"
		exit 1
	fi

	if [ -z "${github_packages_nuget_api_key}" ]; then
		printf "%s: Missing argument: '%s'\n" "$0" "GitHubPackagesNuGetApiKey"
		exit 1
	fi

	if [ -z "${nuget_org_nuget_api_key}" ]; then
		printf "%s: Missing argument: '%s'\n" "$0" "NuGetOrgNuGetApiKey"
		exit 1
	fi

	case "$command" in
		"auto")
			;;
		"manual")
			;;
		*)
			printf "%s: Unknown command: '%s'\n" "$0" "${command}"
			exit 1
	esac

	if [ ! -f *.sln? ]; then
		printf "%s: Current directory is not a solution directory.\n" "$0"
	fi

	declare -r project_file=${project_name}/${project_name}.csproj
	if [ ! -f ${project_file} ]; then
		printf "%s: Project file not found: %s.\n" "$0" "${project_file}"
	fi

	# PEARL: In an MSBuild project file, a missing OutputType property defaults to 'Library'; however, a present but empty OutputType
	#    property seems to default to 'Exe'! (WTF?) Note: we are not accounting for a present but empty OutputType property here.
	declare -r -l output_type=$(get_xml_value ${project_file} OutputType)
	printf "%s: output_type='%s'.\n" "$0" "${output_type}"

	declare -r -l pack_as_tool=$(get_xml_value ${project_file} PackAsTool)
	printf "%s: pack_as_tool='%s'.\n" "$0" "${pack_as_tool}"

	declare -r configurations=$(get_xml_value ${project_file} Configurations)
	printf "%s: configurations='%s'.\n" "$0" "${configurations}"
	declare t=${configurations}
	t=${t/Debug}
	t=${t/Optimized}
	t=${t/Develop}
	t=${t/Release}
	t=${t//;}
	echo t="${t}"
	if [ ! -z ${t} ]; then
		printf "%s: invalid configurations: '%s'.\n" "$0" "${configurations}"
		exit 1
	fi

	assert_no_staged_but_uncommitted_changes # required by do_increment_version

	dotnet restore -check --verbosity minimal

	if [[ ${configurations} == *Optimized* ]]; then
		do_build Optimized
		do_test Optimized
	elif [[ ${configurations} == *Debug* ]]; then
		do_build Debug
		do_test Debug
	fi

	if [[ "$output_type" == "" || "$output_type" == "library" ]]; then

		if [[ ${configurations} == *Develop* ]]; then
			do_build Develop
			do_publish ${command} Develop ${project_name} ${github_packages_nuget_api_key} ${nuget_org_nuget_api_key}
		fi

		if [[ ${configurations} == *Release* ]]; then
			do_build Release
			do_publish ${command} Release ${project_name} ${github_packages_nuget_api_key} ${nuget_org_nuget_api_key}
		fi

	elif [[ "$output_type" == "exe" && "$pack_as_tool" == "true" ]]; then

		if [[ ${configurations} == *Release* ]]; then
			do_build Release
			do_publish ${command} Release ${project_name} ${github_packages_nuget_api_key} ${nuget_org_nuget_api_key}
		fi

	fi

	do_increment_version
}

run $@
