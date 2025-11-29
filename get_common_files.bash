#!/bin/bash

set -o errexit -o nounset -o pipefail

function get()
{
	bash ../MikeNakis.CommonFiles/copy_file.bash "--source=$1" "--target=${2-}"
}

get .editorconfig 
get .gitignore
get .gitattributes
get AllCode.globalconfig 
get AllProjects.proj.xml 
get auto.yml .github/workflows/auto.yml 
get BannedApiAnalyzers.proj.xml 
get BannedSymbols.txt 
get build.bash 
get definitions.bash 
get get_version.bash 
get manual.yml .github/workflows/manual.yml 
get ProductionCode.globalconfig 
get release.bash
