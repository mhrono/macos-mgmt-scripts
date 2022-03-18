#!/bin/zsh

####
## Copyright 2022 Buoy Health, Inc.

## Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0.

## Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
####

## Author: Matt Hrono
## MacAdmins: @matt_h

## Cleanly uninstall and reinstall Falcon

## Get the agentID
agentID=$(/Applications/Falcon.app/Contents/Resources/falconctl stats | awk '/agentID/{print $2}')

## Serial Number
serialNumber=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}')

## Date in ddmm format
date=$(date "+%d%m")

## Create a hash of the above to add some extra validation to the request
## The Okta Workflow will also calculate a hash and ensure they match, in addition to verifying the device is in the remediation smart group in Jamf
validation=$(echo "$agentID-$serialNumber-$date" | shasum -a 512 | awk '{print $1}')

data="{
	\"agentID\": \"$agentID\",
	\"serialNumber\": \"$serialNumber\",
	\"validation\": \"$validation\"
}"

## Add an Okta Workflow invoke URL to retrieve the device's maintenance token
## See the Okta Workflows repo for the associated flow
flowURL=""

## Invoke the flow
response=$(curl -sS --url "$flowURL" --header "Content-Type: application/json" --data "$data")

## Parse out the maintenance token from the response
token=$(echo $response | awk -F',' '{print $1}' | awk -F':' '{print $2}' | sed -e 's/\"//g')

## Uninstall Falcon
/Applications/Falcon.app/Contents/Resources/falconctl uninstall --maintenance-token <<< "$token"

## Call a policy to reinstall the sensor
/usr/local/bin/jamf policy -event crowdstrike