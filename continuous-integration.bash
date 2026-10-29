#!/bin/bash

if ! source definitions.bash > /dev/null; then exit 1; fi

function do_build()
{
	declare -r configuration=$1
	info "Build '$1' configuration"
	if $dry_run; then return; fi
	# [Claude] Restore again for each configuration, because the assets file in 'obj' is shared by all configurations.
	#    Package references depend on the configuration (e.g. 'MikeNakis.Kit-$(PackagesConfiguration)'), so a 'Release'
	#    build that would reuse a 'Debug' restore would compile against, and its package would depend on, the 'Develop'
	#    packages.
	dotnet restore -check --verbosity minimal --property:Configuration="$configuration"
	dotnet build -check --verbosity minimal --configuration "$configuration" --no-restore
}

function do_test()
{
	declare -r configuration=$1
	info "Test '$1' configuration"
	if $dry_run; then return; fi
	dotnet test -check --verbosity normal --configuration "$configuration" --no-build
}

function do_pack()
{
	declare -r configuration=$1
	shift

	info "Pack '$configuration' configuration"
	if $dry_run; then return; fi

	# PEARL: dotnet nuget push gives the developer the convenience of specifying the package to push using a wildcard,
	#    but if the wildcard matches more than one file, then it will sabotage the developer by failing with a
	#    misleading error message that says "File does not exist" instead of "More than one file exists".  For this
	#    reason, we have to remove all files matching the wildcard before creating the package.
	declare project_name
	for project_name in "$@"; do
		remove_if_exists "$project_name/bin/$configuration/*.nupkg"
	done
	# Pack all packable projects of the solution at once. (`dotnet pack` without a project packs them all.)
	dotnet pack -check --verbosity normal --configuration "$configuration" --no-build
}

function do_push()
{
	declare -r configuration=$1
	declare -r project_name=$2
	declare -r destination=$3

	declare -r package_pathname=$project_name/bin/$configuration/*.nupkg

	info "Publish '$configuration' configuration to '$destination' (project '$project_name')"
	if $dry_run; then return; fi

	case "$destination" in
		"github-packages")
			dotnet nuget push "$package_pathname" --source https://nuget.pkg.github.com/MikeNakis/index.json --api-key "$github_packages_nuget_api_key"
			;;
		"nuget-org")
			# NuGet "Trusted Publishing"; see the "NuGet login" step in continuous-integration.yml.
			if [ -z "$nuget_org_nuget_api_key" ]; then
				error "Missing argument: '--nuget-org-nuget-api-key'"
				exit 1
			fi
			dotnet nuget push "$package_pathname" --source https://api.nuget.org/v3/index.json --api-key "$nuget_org_nuget_api_key"
			;;
		*)
			error "Invalid publish destination: '$destination'"
			exit 1
	esac
}

function run()
{
	run_this_script_in_its_directory "$@"

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
		project_name=$(basename $PWD)
	fi

	if [ -z "$github_packages_nuget_api_key" ]; then
		error "Missing argument: '--github-packages-nuget-api-key'"
		exit 1
	fi

	if [ ! -f *.sln? ]; then
		error "Current directory is not a solution directory."
		exit 1
	fi

	declare -r project_file=$project_name/$project_name.csproj
	if [ ! -f "$project_file" ]; then
		error "Project file not found: '$project_file'"
		exit 1
	fi

	declare -l output_type
	output_type=$(get_output_type "$project_file")
	declare -r output_type
	info "Output Type: $output_type"

	declare -l pack_as_tool
	pack_as_tool=$(get_pack_as_tool "$project_file")
	declare -r pack_as_tool
	info "Pack as tool: $pack_as_tool"

	declare -A configurations=()
	get_configurations "$project_file" configurations
	declare -r configurations
	info "Configurations: ${!configurations[*]}"

	declare -a project_names=()
	get_project_names "$project_name" project_names
	declare -r project_names
	info "Projects to publish: ${project_names[*]}"

	declare publishing_destination
	publishing_destination=$(get_publishing_destination)
	declare -r publishing_destination
	info "Publishing destination: $publishing_destination"

	if [[ "$output_type" == "exe" && -v configurations[Develop] ]]; then
		warn "This project builds an executable but has a 'Develop' configuration!?"
	fi

	# The logic:
	#   Build and test the 'Debug' configuration, or the 'Optimized' configuration if one has been defined.
	#   If we are publishing, then:
	#     If this is a library, or an exe packaged as tool, then:
	#       Build and publish the 'Develop' configuration, if defined.
	#       Build and publish the 'Release' configuration, if defined.
	#   Restore before building each configuration, since restore results depend on the configuration.
	#   The projects to publish are the project named after the repository, plus every '<project-name>.*'
	#   project that is publishable and has a 'Develop' or a 'Release' configuration; each of them is published
	#   in those of the two configurations that it defines.

	if [[ -v configurations[Optimized] ]]; then

		do_build Optimized
		do_test Optimized

	elif [[ -v configurations[Debug] ]]; then

		do_build Debug
		do_test Debug

	fi

	if [[ "$publishing_destination" != "none" ]]; then

		declare name
		for name in "${project_names[@]}"; do
			declare publishable
			publishable=$(is_publishable "$name/$name.csproj")
			if ! $publishable; then
				error "Project '$name' cannot be published"
				exit 1
			fi
		done

		declare configuration
		for configuration in Develop Release; do

			declare -a names_to_publish=()
			for name in "${project_names[@]}"; do
				declare -A project_configurations=()
				get_configurations "$name/$name.csproj" project_configurations
				if [[ -v project_configurations[$configuration] ]]; then
					names_to_publish+=( "$name" )
				fi
			done

			if (( ${#names_to_publish[@]} == 0 )); then
				continue
			fi

			do_build "$configuration"
			do_pack "$configuration" "${names_to_publish[@]}"
			for name in "${names_to_publish[@]}"; do
				do_push "$configuration" "$name" "$publishing_destination"
			done

		done

	fi
}

# Fills the array named by the second argument with the names of the projects to publish.
function get_project_names
{
	declare -r main_project_name=$1
	declare -n project_names_result=$2

	project_names_result+=( "$main_project_name" )

	declare directory
	for directory in "$main_project_name".*/; do
		declare name=${directory%/}
		declare project_file=$name/$name.csproj
		if [[ ! -f "$project_file" ]]; then
			continue
		fi
		declare -A project_configurations=()
		get_configurations "$project_file" project_configurations
		if [[ ! -v project_configurations[Develop] && ! -v project_configurations[Release] ]]; then
			continue
		fi
		# [Claude] Skip a project that cannot be published, such as an executable that exercises the library, because only
		#    the project named after the repository is required to be publishable.
		declare publishable
		publishable=$(is_publishable "$project_file")
		if ! $publishable; then
			continue
		fi
		project_names_result+=( "$name" )
	done
}

# [Claude] Determines whether a project can be published as a package, that is, whether it is a library or an executable
#    packaged as a tool.
# [Claude] The result is printed as 'true' or 'false' instead of being returned as an exit status, because callers that
#    would test an exit status in an `if` condition would also disable `errexit` for everything this function runs,
#    swallowing its errors.
function is_publishable
{
	declare -r project_file=$1

	declare -l output_type
	output_type=$(get_output_type "$project_file")
	declare -l pack_as_tool
	pack_as_tool=$(get_pack_as_tool "$project_file")

	if [[ "$output_type" == "library" || "$output_type" == "exe" && "$pack_as_tool" == "true" ]]; then
		printf "true"
	else
		printf "false"
	fi
}

function get_output_type
{
	declare -r project_file=$1

	# PEARL: In an MSBuild project file, a missing OutputType property defaults to 'Library'; however, a present but
	#    empty OutputType property seems to default to 'Exe'! (WTF?) Note: we are not accounting for a present but empty
	#    OutputType property here.
	declare -l output_type
	output_type=$(get_xml_value "$project_file" "OutputType" "library")

	case "$output_type" in
		"library")
			;;
		"exe")
			;;
		*)
			error "Invalid output type: '$output_type'"
			exit 1
	esac

	printf "%s" "$output_type"
}

# [Claude] Fills the associative array named by the second argument with the configurations of the project, as keys.
function get_configurations
{
	declare -r project_file=$1
	declare -n configuration_set=$2

	declare -a configuration_names
	IFS=';' read -ra configuration_names <<< "$(get_xml_value "$project_file" "Configurations")"

	declare configuration_name
	for configuration_name in "${configuration_names[@]}"; do
		case "$configuration_name" in
			Debug|Optimized|Develop|Release)
				;;
			*)
				error "Invalid configuration: '$configuration_name' in '$project_file'."
				exit 1
		esac
		if [[ -v configuration_set[$configuration_name] ]]; then
			error "Duplicate configuration: '$configuration_name' in '$project_file'."
			exit 1
		fi
		configuration_set[$configuration_name]=1
	done
}

function get_pack_as_tool
{
	declare -r project_file=$1

	declare -l pack_as_tool
	pack_as_tool=$(get_xml_value "$project_file" "PackAsTool" "false")

	case "$pack_as_tool" in
		"true")
			;;
		"false")
			;;
		*)
			error "Invalid 'PackAsTool' value: '$pack_as_tool'"
			exit 1
	esac

	printf "%s" "$pack_as_tool"
}

function get_publishing_destination
{
	declare last_commit_message
	last_commit_message=$(git_get_last_commit_message)
	declare -r last_commit_message
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
