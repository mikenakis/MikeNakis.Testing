#!/bin/bash

source definitions.bash > /dev/null

declare -r version_file_pathname=$(realpath version.txt)

function do_restore()
{
	info "Restore"
	[[ $dry_run == true ]] && return
	dotnet restore -check --verbosity minimal
}

function do_build()
{
	declare -r configuration=$1
	info "Build '$1' configuration"
	[[ $dry_run == true ]] && return
	dotnet build -check --verbosity minimal --configuration "$configuration" --no-restore
}

function do_test()
{
	declare -r configuration=$1
	info "Test '$1' configuration"
	[[ $dry_run == true ]] && return
	dotnet test -check --verbosity normal --configuration "$configuration" --no-build
}

function do_publish()
{
	declare -r configuration=$1
	declare -r project_name=$2
	declare -r destination=$3

	declare -r package_pathname=$project_name/bin/$configuration/*.nupkg

	info "Publish '$configuration' configuration to '$destination' (project '$project_name')"
	[[ $dry_run == true ]] && return

	# PEARL: dotnet nuget push gives the developer the convenience of specifying the package to push using a wildcard,
	#    but if the wildcard matches more than one file, then it will sabotage the developer by failing with a
	#    misleading error message that says "File does not exist" instead of "More than one file exists".  For this
	#    reason, we have to remove all files matching the wildcard before creating the package.
	remove_if_exists "$package_pathname"
	dotnet pack -check --verbosity normal --configuration "$configuration" --no-build

	case "$destination" in
		"github-packages")
			dotnet nuget push "$package_pathname" --source https://nuget.pkg.github.com/MikeNakis/index.json --api-key "$github_packages_nuget_api_key"
			;;
		"nuget-org")
			dotnet nuget push "$package_pathname" --source https://api.nuget.org/v3/index.json --api-key "$nuget_org_nuget_api_key"
			;;
		*)
			error "Invalid publish destination: '$destination'"
			exit 1
	esac
}

function get_last_commit_message()
{
	# PEARL: as the case is with virtually all git commands, the git command that prints the last commit message looks
	#   absolutely nothing like a command that would print the last commit message. Linus Torvalds you are not just a
	#   geek, you are a fucking dork.
	# from https://stackoverflow.com/a/7293026/773113
	# and https://stackoverflow.com/questions/7293008/display-last-git-commit-comment#comment105325732_7293026
	git log -1 --pretty=format:%B
}

function run()
{
	declare project_name=""
	declare github_packages_nuget_api_key=""
	declare nuget_org_nuget_api_key=""
	declare dry_run=false

	while [ $# -gt 0 ]; do
		case "$1" in
			--project-name=*)
				project_name="${1#*=}"
				;;
			--github-packages-nuget-api-key=*)
				github_packages_nuget_api_key="${1#*=}"
				;;
			--nuget-org-nuget-api-key=*)
				nuget_org_nuget_api_key="${1#*=}"
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

	if [ -z "$project_name" ]; then
		error "Missing argument: '--project-name'"
		exit 1
	fi

	if [ -z "$github_packages_nuget_api_key" ]; then
		error "Missing argument: '--github-packages-nuget-api-key'"
		exit 1
	fi

	if [ -z "$nuget_org_nuget_api_key" ]; then
		error "Missing argument: '--nuget-org-nuget-api-key'"
		exit 1
	fi

	if [ ! -f *.sln? ]; then
		error "Current directory is not a solution directory."
	fi

	declare -r project_file=$project_name/$project_name.csproj
	if [ ! -f "$project_file" ]; then
		error "Project file not found: '$project_file'"
	fi

	declare -r -l output_type=$(get_output_type "$project_file")
	info "Output Type: $output_type"
	
	declare -r -l pack_as_tool=$(get_pack_as_tool "$project_file")
	info "Pack as tool: $pack_as_tool"

	declare -r configurations=$(get_configurations "$project_file")
	info "Configurations: $configurations"

	declare -r publishing_destination=$(get_publishing_destination)
	info "Publishing destination: $publishing_destination"

	if [[ "$output_type" == "exe" && $configurations == *Develop* ]]; then
		warn "This project builds an executable but has a 'Develop' configuration!?"
	fi
	
	# The logic:
	#  First, do a dotnet restore.
	#  Then, build and test the 'Debug' configuration, or the 'Optimized' configuration if one has been defined.
	#  Then, if we are publishing, then:
	#      If this is a library, or an exe packaged as tool, then:
	#          build and publish the 'Develop' and 'Release' configurations, each if defined.

	do_restore

	if [[ "$configurations" == *Optimized* ]]; then
		do_build Optimized
		do_test Optimized
	elif [[ "$configurations" == *Debug* ]]; then
		do_build Debug
		do_test Debug
	fi

	if [[ "$publishing_destination" != "none" ]]; then

		if [[ "$output_type" == "library" || "$output_type" == "exe" && "$pack_as_tool" == "true" ]]; then

			if [[ "$configurations" == *Develop* ]]; then
				do_build Develop
				do_publish Develop "$project_name" "$publishing_destination"
			fi
			if [[ "$configurations" == *Release* ]]; then
				do_build Release
				do_publish Release "$project_name" "$publishing_destination"
			fi

		fi

	fi
}

function get_output_type
{
	declare -r project_file=$1

	# PEARL: In an MSBuild project file, a missing OutputType property defaults to 'Library'; however, a present but
	#    empty OutputType property seems to default to 'Exe'! (WTF?) Note: we are not accounting for a present but empty
	#    OutputType property here.
	declare -l output_type=$(get_xml_value "$project_file" OutputType library)

	case "$output_type" in
		"library")
			;;
		"exe")
			;;
		*)
			error "Invalid output type: '$output_type'"
			exit 1
	esac

	printf "$output_type"
}

function get_configurations
{
	declare -r project_file=$1

	declare -r configurations=$(get_xml_value "$project_file" Configurations)

	declare t="$configurations"
	t=${t/Debug}
	t=${t/Optimized}
	t=${t/Develop}
	t=${t/Release}
	t=${t//;}
	if [[ "$t" != "" ]]; then
		error "Invalid configuration: '$t'."
		exit 1
	fi

	printf "$configurations"
}

function get_pack_as_tool
{
	declare -r project_file=$1

	declare -l pack_as_tool=$(get_xml_value "$project_file" PackAsTool false)

	case "$pack_as_tool" in
		"true")
			;;
		"false")
			;;
		*)
			error "Invalid 'PackAsTool' value: '$pack_as_tool'"
			exit 1
	esac

	printf "$pack_as_tool"
}

function get_publishing_destination
{
	declare -r last_commit_message=$(get_last_commit_message)

	declare publishing_destination=
	declare -r release_commit_message_prefix="Release of version "
	if [[ $last_commit_message == $release_commit_message_prefix* ]]; then
		declare -r version=${last_commit_message#"$release_commit_message_prefix"}
		declare -i major
		declare -i minor
		declare -i patch
		IFS=. read -r major minor patch <<< "$version"
		if [[ $patch == 0 ]]; then
			printf "nuget-org"
		else
			printf "github-packages"
		fi
	else
		printf "none"
	fi
}

run $@
