#
# Copyright 2016 Cloudbase Solutions Srl
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#
$ErrorActionPreference = "Stop"

Import-Module JujuLogging

function ip_in_subnet { 
    param ( 
        [parameter(Mandatory=$true)]
        [Net.IPAddress] 
        $ip, 

        [parameter(Mandatory=$true)] 
        $subnet
    ) 

    [Net.IPAddress]$ip2, $m = $subnet.split('/')

    Switch -RegEx ($m) {
        "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$" {
            $mask = [Net.IPAddress]$m
        }
        "^[\d]+$" {
            $tip=([Convert]::ToUInt32($(("1" * $m).PadRight(32, "0")), 2))
            $dotted = $( For ($i = 3; $i -gt -1; $i--) {
                $r = $tip % [Math]::Pow(256, $i)
                ($tip - $r) / [Math]::Pow(256, $i)
                $tip = $r
            } )
        
            $mask = [Net.IPAddress][String]::Join('.', $dotted)
        }
        default {
            Fail-Json $result "Invalid subnet specified: $subnet"
        }
    }

    if (($ip.address -band $mask.address) -eq ($ip2.address -band $mask.address)) {
        return $true
    } else {
        return $false
    } 
}

try {
    Import-Module JujuHooks
    Import-Module JujuUtils

    $cfg = Get-JujuCharmConfig

    if ($cfg["os-rdp-network"]) {
        $adapters = Get-NetIPAddress -addressfamily ipv4

        foreach ($adapter in $adapters) {
            if (ip_in_subnet -ip $adapter.ipaddress -subnet $cfg["os-rdp-network"]) {
                $ipAddress = $adapter.ipaddress
                break
            }
        }
    }

    # fallback
    if (!$ipAddress) {
        $ipAddress = Get-JujuUnitPrivateIP
    }

    $port = Get-JujuCharmConfig -Scope "http-port"

    $url = "http://{0}:{1}" -f @($ipAddress, $port)

    $settings = @{
        "enabled" = $true;
        "html5_proxy_base_url" = $url
    }

    $rids = Get-JujuRelationIds -Relation "free-rdp"
    foreach ($rid in $rids) {
        Set-JujuRelation -RelationId $rid -Settings $settings
    }
} catch {
    Write-HookTracebackToLog $_
    exit 1
}
