#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

repo_root=$(dirname "${BASH_SOURCE[0]}")/..
lts2019="2019-Datacenter-Core-with-Containers-smalldisk"
sac1903="Datacenter-Core-1903-with-Containers-smalldisk"
sac1909="Datacenter-Core-1909-with-Containers-smalldisk"
sac2004="Datacenter-Core-2004-with-Containers-smalldisk"

function setVersion() {
    local windowsSku=$1
    templateFiles=($(grep -rnwl "${repo_root}/job-templates" -e "$windowsSku"))
    version=$(az vm image show --urn MicrosoftWindowsServer:WindowsServer:$windowsSku:latest | jq -r .name)

    #can't do inline replacements with jq (https://github.com/stedolan/jq/issues/105)
    tmp=$(mktemp)
    for template in "${templateFiles[@]}"; do
        jq --arg version "$version" '.properties.windowsProfile.imageVersion = $version' $template > "$tmp" && mv "$tmp" $template
        echo "Updated file '$template' '$windowsSku' with '$version'"
    done
}

setVersion $lts2019
setVersion $sac1903
setVersion $sac1909
setVersion $sac2004
