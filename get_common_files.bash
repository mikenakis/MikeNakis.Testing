#!/bin/bash

set -o errexit -o nounset -o pipefail

bash ../MikeNakis.CommonFiles/copy_files.bash "$(dirname $0)" \
.editorconfig \
AllProjects.proj.xml \
AllCode.globalconfig \
ProductionCode.globalconfig \
BannedApiAnalyzers.proj.xml \
BannedSymbols.txt
