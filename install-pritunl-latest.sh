#!/bin/zsh

####
## Copyright 2022 Buoy Health, Inc.

## Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0.

## Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
####

## Author: Matt Hrono
## MacAdmins: @matt_h

#### Install Pritunl
#### This script will:
###### Parse the latest Pritunl client version from GitHub
###### Download the package
###### Validate the checksum
###### If validated, install the package
###### Submit Jamf inventory and clean up

## Set some vars

hashFile="https://raw.githubusercontent.com/pritunl/pritunl-client-electron/master/SHA256"
packageName="Pritunl.pkg"

#### Some assumptions are made below based on current known behavior
#### Always test and verify before implementing in production

## Pritunl publishes SHA256 hashes for each version of their Windows and macOS installers at the above URL
## The latest version is at the top with the version number on the first line
## Following the version number, the Windows checksum is listed first, followed by the macOS checksum
## Get latest version number and checksum from the hash file

pritunlVersion=$(curl -fsSL $hashFile | cat | head -n 1 | awk -F' ' '{print $3}' | cut -c 2-)
echo "Latest Pritunl version is $pritunlVersion"

pritunlChecksum=$(curl -fsSL $hashFile | cat | head -n 3 | tail -n 1 | awk -F' ' '{print $1}')

## Download the latest package
echo "Downloading Pritunl..."
mkdir -p /tmp/pritunl
curl -fsSL -o /tmp/pritunl/$packageName.zip https://github.com/pritunl/pritunl-client-electron/releases/download/$pritunlVersion/$packageName.zip

## Validate checksum and install
if [[ $(shasum -a 256 /tmp/pritunl/$packageName.zip | awk '{print $1}') == "$pritunlChecksum" ]]; then
	echo "Pritunl checksum validated, proceeding with installation..."
	if [[ /Applications/Pritunl.app/Contents/Resources/pritunl-client ]]; then rm -rf /Applications/Pritunl.app; fi
	tar -zxf /tmp/pritunl/$packageName.zip -C /tmp/pritunl
	installer -pkg /tmp/pritunl/$packageName -target /
else
	echo "Pritunl checksum validation failed, skipping install..."
	exit 1
fi

## Submit inventory and clean up
jamf recon
rm -rf /tmp/pritunl