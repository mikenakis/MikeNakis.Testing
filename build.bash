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
	declare -r command=$1
	declare -r configuration=$2
	declare -r project_name=$3
	declare -r github_packages_nuget_api_key=$4
	declare -r nuget_org_nuget_api_key=$5

	declare -r package_pathname=$project_name/bin/$configuration/*.nupkg

	info "Publish '$configuration' configuration (project '$project_name')"
	[[ $dry_run == true ]] && return

	# PEARL: dotnet nuget push will push a package specified using a wildcard, but if the wildcard matches more than one file, then it
	#    will sabotage the developer by failing with a misleading error message that says "File does not exist" instead of "More than
	#    one file exists".  For this reason, we have to remove all files matching the wildcard before creating the package.
	remove_if_exists "$package_pathname"
	dotnet pack -check --verbosity normal --configuration "$configuration" --no-build
	
	if [[ "$command" == "auto" ]]; then
		dotnet nuget push "$package_pathname" --source https://nuget.pkg.github.com/MikeNakis/index.json --api-key "$github_packages_nuget_api_key"
	else
		dotnet nuget push "$package_pathname" --source https://api.nuget.org/v3/index.json --api-key "$nuget_org_nuget_api_key"
	fi
}

function run()
{
	declare -l command=""
	declare project_name=""
	declare github_packages_nuget_api_key=""
	declare nuget_org_nuget_api_key=""
	declare dry_run=false

	while [ $# -gt 0 ]; do
		case "$1" in
			--command=*)
				command="${1#*=}"
				;;
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
				error "Invalid argument: '%s'" "$1"
				exit 1
		esac
		shift
	done

	if [ -z "$command" ]; then
		error "Missing argument: '%s'" "Command"
		exit 1
	fi

	if [ -z "$project_name" ]; then
		error "Missing argument: '%s'" "ProjectName"
		exit 1
	fi

	if [ -z "$github_packages_nuget_api_key" ]; then
		error "Missing argument: '%s'" "GitHubPackagesNuGetApiKey"
		exit 1
	fi

	if [ -z "$nuget_org_nuget_api_key" ]; then
		error "Missing argument: '%s'" "NuGetOrgNuGetApiKey"
		exit 1
	fi

	case "$command" in
		"auto")
			;;
		"manual")
			;;
		*)
			error "Unknown command: '%s'" "$command"
			exit 1
	esac

	if [ ! -f *.sln? ]; then
		error "Current directory is not a solution directory."
	fi

	declare -r project_file=$project_name/$project_name.csproj
	if [ ! -f "$project_file" ]; then
		error "Project file not found: %s" "$project_file"
	fi

	declare -r -l output_type=$(get_output_type "$project_file")
	
	declare -r -l pack_as_tool=$(get_pack_as_tool "$project_file")

	declare -r configurations=$(get_configurations "$project_file")

	if [[ "$output_type" == "exe" && $configurations == *Develop* ]]; then
		warn "This project builds an executable but has a 'Develop' configuration!?"
	fi
	
	# The logic:
	#  First, do a dotnet restore.
	#  Then, build and test the 'Debug' configuration, or the 'Optimized' configuration if one has been defined.
	#  Then, if this is a library, or an exe packaged as tool, build and publish the 'Develop' and 'Release'
	#  configurations, each if defined.

	do_restore

	if [[ "$configurations" == *Optimized* ]]; then
		do_build Optimized
		do_test Optimized
	elif [[ "$configurations" == *Debug* ]]; then
		do_build Debug
		do_test Debug
	fi

	if [[ "$output_type" == "library" || "$output_type" == "exe" && "$pack_as_tool" == "true" ]]; then

		if [[ "$configurations" == *Develop* ]]; then
			do_build Develop
			do_publish "$command" Develop "$project_name" "$github_packages_nuget_api_key" "$nuget_org_nuget_api_key"
		fi

		if [[ "$configurations" == *Release* ]]; then
			do_build Release
			do_publish "$command" Release "$project_name" "$github_packages_nuget_api_key" "$nuget_org_nuget_api_key"
		fi

	fi
}

function get_output_type
{
	declare -r project_file=$1

	# PEARL: In an MSBuild project file, a missing OutputType property defaults to 'Library'; however, a present but
	#    empty OutputType property seems to default to 'Exe'! (WTF?) Note: we are not accounting for a present but empty
	#    OutputType property here.
	declare -l output_type=$(get_xml_value "$project_file" OutputType)

	if [[ "$output_type" != "library" && "$output_type" != "exe" && "$output_type" != "" ]]; then
		error "Invalid output type: '%s'" "$output_type"
		exit 1
	fi

	if [ -z "$output_type" ]; then
		output_type="library"
	fi

	printf "%s" "$output_type"
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
		error "Invalid configuration: '%s'." "$t"
		exit 1
	fi

	printf "%s" "$configurations"
}

function get_pack_as_tool
{
	declare -r project_file=$1

	declare -l pack_as_tool=$(get_xml_value "$project_file" PackAsTool)

	if [[ "$pack_as_tool" != "" && "$pack_as_tool" != "true" && "$pack_as_tool" != "false" ]]; then
		error "Invalid 'PackAsTool' value: '%s'" "$pack_as_tool"
		exit 1
	fi

	if [ -z "$pack_as_tool" ]; then
		pack_as_tool="false"
	fi

	printf "%s" "$pack_as_tool"
}

run $@
