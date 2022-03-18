#!/bin/zsh

####
## Copyright 2022 Buoy Health, Inc.

## Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0.

## Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
####

## Install macOS Command Line Developer Tools
## Using adapted portions of:
## https://github.com/rtrouton/rtrouton_scripts/blob/master/rtrouton_scripts/install_xcode_command_line_tools/install_xcode_command_line_tools.sh
## https://github.com/palantir/jamf-pro-scripts/blob/master/scripts/Install%20Xcode%20Command%20Line%20Tools.sh

## Author: Matt Hrono
## MacAdmins: @matt_h

## Check if the dev tools are already installed
function xcodeCheck {
	local xcodeSelectCheck=$(/usr/bin/xcode-select -p 2>/dev/null)
	if [[ $xcodeSelectCheck ]] && [[ -e $xcodeSelectCheck/usr/bin ]]; then
		xcodeCLI="installed"
	else
		xcodeCLI="missing"
	fi
}

function checkForTools {
	echo "Checking for developer tools..."
	xcodeCheck
	echo "Developer tools are $xcodeCLI"
}

## Download and install dev tools
function installTools {
	local macOSVers=$(sw_vers -productVersion | awk -F "." '{print $2}')
	local macOSName=$(sw_vers -productName)
	local cmdLineToolsTempFile="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"

	# Installing the latest Xcode command line tools on 10.9.x or higher
	if [[ "$macOSVers" -ge 9 ]] || [[ "$macOSName" == "macOS" ]]; then
		# Create the placeholder file which is checked by the softwareupdate tool 
		# before allowing the installation of the Xcode command line tools.
		touch "$cmdLineToolsTempFile"
		
		# Identify the correct update in the Software Update feed with "Command Line Tools" in the name for the OS version in question.
		if [[ "$macOSVers" -ge 15 ]] || [[ "$macOSName" == "macOS" ]]; then
			echo "Running macOS Catalina or higher"
			local cmdLineTools=$(softwareupdate -l | awk '/\*\ Label: Command Line Tools/ { $1=$1;print }' | sed 's/^[[ \t]]*//;s/[[ \t]]*$//;s/*//' | cut -c 9-)	
		elif [[ "$macOSVers" -gt 9 ]] && [[ "$macOSVers" -lt 15 ]]; then
			echo "Running macOS Mojave or lower"
			local cmdLineTools=$(softwareupdate -l | awk '/\*\ Command Line Tools/ { $1=$1;print }' | grep "$macOSVers" | sed 's/^[[ \t]]*//;s/[[ \t]]*$//;s/*//' | cut -c 2-)
		fi
		
		# Check to see if the softwareupdate tool has returned more than one Xcode
		# command line tool installation option. If it has, use the last one listed
		# as that should be the latest Xcode command line tool installer.
		if (( $(grep -c . <<<"$cmdLineTools") > 1 )); then
			local cmdLineToolsOutput="$cmdLineTools"
			local cmdLineTools=$(printf "$cmdLineToolsOutput" | tail -1)
		fi
		
		#Install the command line tools
		softwareupdate -i "$cmdLineTools" --verbose
		
		# Remove the temp file
		if [[ -f "$cmdLineToolsTempFile" ]]; then
			rm "$cmdLineToolsTempFile"
		fi
	elif [[ "$macOSVers" -lt 9 ]]; then
		echo "Installing developer tools on this macOS version is not supported with this tool"
	fi
}

## Main
checkForTools

if [[ $xcodeCLI == "missing" ]]; then
	echo "Attempting to install macOS Command Line Developer Tools..."
	for installAttempt in {1..6}; do
		if [[ $installAttempt == "6" ]]; then
			echo "Failed to install developer tools after 5 attempts, exiting..."
			exit 1
		fi
		echo "Installing developer tools (attempt $installAttempt of 5)..."
		installTools
		echo "Validating installation..."
		checkForTools
		if [[ $xcodeCLI == "installed" ]]; then
			echo "Developer tools installed, exiting with success!"
			softwareupdate --list --force
			break
		else
			echo "Developer tools not found, re-attempting installation..."
		fi
	done
else
	echo "Developer tools already installed, exiting"
	/usr/bin/xcode-select -r
	exit 0
fi