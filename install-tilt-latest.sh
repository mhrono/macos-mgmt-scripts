#!/bin/zsh

####
## Copyright 2022 Buoy Health, Inc.

## Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0.

## Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
####

## Author: Matt Hrono
## MacAdmins: @matt_h

#### Install Tilt
#### This script will:
###### Parse the latest Tilt client version from GitHub
###### Download the package
###### Validate the checksum
###### If validated, unpack the binary and move to /usr/local/bin
###### Finally, set a preference to opt out of analytics collection

## Get current version and checksum
tiltVersion=$(curl -sS https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | sed -n 10p | awk -F'=' '{print $2}' | sed 's/"//g')
tiltHash=$(curl -fsSL https://github.com/tilt-dev/tilt/releases/download/v$tiltVersion/checksums.txt | grep mac.x86 | awk '{print $1}')

echo "Latest tilt version is $tiltVersion with checksum $tiltHash"

## Download latest version
packageName="tilt.$tiltVersion.mac.x86_64.tar.gz"
mkdir -p /tmp/tilt
curl -fsSL -o /tmp/tilt/$packageName https://github.com/tilt-dev/tilt/releases/download/v$tiltVersion/$packageName

## Validate checksum and install
if [[ $(shasum -a 256 /tmp/tilt/$packageName | awk '{print $1}') == "$tiltHash" ]]; then
	echo "Tilt checksum validated, proceeding with installation..."
	if [[ /usr/local/bin/tilt ]]; then rm -rf /usr/local/bin/tilt; fi
	tar -xvf /tmp/tilt/$packageName -C /tmp/tilt > /dev/null
	mv /tmp/tilt/tilt /usr/local/bin/
	
	## Set analytics to opt-out
	currentUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
		mkdir -p /Users/$currentUser/.tilt-dev/analytics/user
		chown -R $currentUser /Users/$currentUser/.tilt-dev
		echo "opt-out" > /Users/$currentUser/.tilt-dev/analytics/user/choice.txt
	else
		echo "Tilt checksum validation failed, skipping install..."
		exit 1
	fi
		
## Clean up
rm -rf /tmp/tilt