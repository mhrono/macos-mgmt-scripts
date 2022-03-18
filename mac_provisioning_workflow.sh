#!/bin/zsh

####
## Copyright 2022 Buoy Health, Inc.

## Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0.

## Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
####

## Author: Matt Hrono
## MacAdmins: @matt_h

## NOTE - 3/18/2022: This script has been deprecated in favor of using Jamf Connect Notify for device provisioning. I will not be making updates to this script.
## There are some org-specific references buried in the depths of this script you'll need to change if you want to use this yourself.

#### Set some vars
encryptPolicyID="362"
wifiPort=$(networksetup -listallhardwareports | awk -F':' '{print $2}' | grep -A1 Wi-Fi | tail -n 1 | cut -c 2-)
currentSSID=$(networksetup -getairportnetwork $wifiPort | awk -F':' '{print $2}' | cut -c 2-)
if [[ $(sw_vers -productName) == "macOS" ]]; then
	macOSVersion="10.16"
else
	macOSVersion=$(sw_vers -productVersion | cut -d. -f1-2)
fi

## Write timestamped activities to a log for diagnostic purposes
## Usage: logAction "Information to be put into the log. $Variables can also be included."
function logAction {
	logTime=$(date "+%Y-%m-%d - %H:%M:%S:")
	echo "$logTime" "$1" | tee -a /var/log/provisioning.log
}

function waitForUser {
	## Get current user and UID
	loggedInUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
	logAction "Checking to make sure system is ready for provisioning. Current user is $loggedInUser"
	currentUID=$(dscl . -list /Users UniqueID | grep $loggedInUser 2>/dev/null | awk '{print $2;}')
	logAction "$loggedInUser UID is $currentUID"
	
	## Wait until desired user is logged in
	while [[ ! $currentUID -gt 500 ]]; do
		logAction "Currently logged in user is NOT the end user. Waiting."
		sleep 2
		loggedInUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
		currentUID=$(dscl . -list /Users UniqueID | grep $loggedInUser 2>/dev/null | awk '{print $2;}')
		logAction "Current user is $loggedInUser with UID $currentUID"
	done

	## Wait for the desktop to be available before continuing
	dockStatus=$(pgrep -x Dock)
	logAction "Desired user is logged in. Waiting for Desktop..."
	while [[ "$dockStatus" == "" ]]; do
		logAction "Desktop is not loaded. Waiting."
		sleep 2
		dockStatus=$(pgrep -x Dock)
	done

	## All good!
	logAction "Desired user logged in and system is ready. Continuing with provisioning..."
}

#### Array of policy IDs and labels for installation loop
## Format is policyID,label. Spaces must be substituted for underscores, and will be reformatted with spaces before being displayed to the user
## In order to have an icon displayed, the label must begin with "Configuring", "Installing", or "Updating"

Policies=(
	
	'buoyB,Configuring_Support_Resources'
	'elasticUtils,Updating_Inventory_Data'
	'setHostname,Configuring_Computer_Name'
	'setFirewall,Configuring_Firewall'
	'crowdstrike,Installing_AntiMalware_Agent'
	'install-Zscaler,Installing_Web_Security_Agent'
	'autoupdate-1Password,Installing_1Password'
	'autoupdate-Slack,Installing_Slack'
	'autoupdate-zoom.us,Installing_Zoom'
	'autoupdate-Google_Chrome,Installing_Google_Chrome'
#	'installSync,Installing_Password_Sync_Client'
	'dockConfig,Configuring_Dock'
	'install-managedPython,Installing_IT_Toolkit'
	
)

## Run through the array above
function runPolicies {
	## Determine if the user is in the Boston office based on their connected SSID
	## If so, add the printer policy to the array for automated installation
	if [[ $currentSSID =~ "Buoy" ]]; then
		logAction "User is in Boston, adding printer to policy array..."
		Policies=("${Policies[@]}" "bostonPrinter,Configuring_Boston_Printer")
	fi
	POLICYCOUNT=${#Policies[@]}
	COUNTER="1"
	for i in ${Policies[@]}; do
		POLICYEVENT=$(echo $i | cut -f1 -d,)
		POLICYEVENT=${POLICYEVENT//_/ }
		HEADER=$(echo $i | cut -f2 -d,)
		HEADER=${HEADER//_/ }
		ACTION=$(echo $HEADER | cut -c1-4 )
		ICON="/System/Library/CoreServices/Problem Reporter.app/Contents/Resources/ProblemReporter.icns"
		if [[ $macOSVersion == "10.16" ]]; then
			if [[ $ACTION == "Conf" ]]; then ICON="/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/AppIcon.icns"; fi
			if [[ $ACTION == "Inst" ]]; then ICON="/System/Library/CoreServices/Installer.app/Contents/Resources/AppIcon.icns"; fi
			if [[ $ACTION == "Upda" ]]; then ICON="/System/Library/PreferencePanes/SoftwareUpdate.prefPane/Contents/Resources/SoftwareUpdate.icns"; fi
		else
			if [[ $ACTION == "Conf" ]]; then ICON="/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/Assistant.icns"; fi
			if [[ $ACTION == "Inst" ]]; then ICON="/System/Library/CoreServices/Installer.app/Contents/Resources/Installer.icns"; fi
			if [[ $ACTION == "Upda" ]]; then ICON="/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns"; fi
		fi
		logAction "Running policy $COUNTER of $POLICYCOUNT - $HEADER..."
		killall jamfHelper
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -icon "$ICON" -heading "$HEADER" -description "Setup item $COUNTER of $POLICYCOUNT" &
		jamf policy -event $POLICYEVENT -forceNoRecon
		## Check the exit code of the jamf binary running the policy
		## If non-zero, try again once
		## If it fails twice, move on
		if [[ $? -eq 0 ]]; then logAction "Policy result: OK"; else logAction "Policy failed with exit code $?, trying again..."; jamf policy -event $POLICYEVENT -forceNoRecon; logAction "Second attempt exit code: $?"; fi
		(( COUNTER++ ))
	done
}

function authchangerReset {
	## Reset the login window back to default instead of the Jamf Connect branded one
	## The authchanger binary works by modifying the macOS authorizationdb
	logAction "Resetting authchanger..."
	authchanger -reset
	sleep 5
	## Remove Jamf Connect Login elements
	logAction "Removing Jamf Connect Login..."
	rm /usr/local/bin/authchanger
	rm /usr/local/lib/pam/pam_saml.so.2
	rm -rf /Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle
    ## Load Jamf Connect LaunchAgent
    logAction "Loading Jamf Connect LaunchAgent..."
    sudo -u $loggedInUser launchctl load -w /Library/LaunchAgents/com.jamf.connect.plist
}

## If updates are being installed during provisioning and require a restart, let the user know what's happening
function cleanUpWithUpdates {
	logAction "Cleaning up with updates..."
	## Update inventory
	logAction "Running recon..."
	jamf recon >/dev/null
	## Kill the caffeinate process
	logAction "Sending barista $caffeinatePID home..."
	kill "${caffeinatePID}" >/dev/null
	authchangerReset
	## In order for the policy to exit cleanly and submit logs to jamf while still restarting as intended, the final jamfHelper window must be broken out into its own process
	## The most reliable way I've found to do this is by making it a LaunchDaemon
	logAction "Building LaunchDaemon for final jamfHelper window..."
cat << EOF > /Library/LaunchDaemons/com.buoy.provisionWrapUp.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.buoy.provisionWrapUp</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper</string>
		<string>-windowType</string>
		<string>fs</string>
		<string>-icon</string>
		<string>/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns</string>
		<string>-heading</string>
		<string>Enjoy your new Mac!</string>
		<string>-description</string>
		<string>"We're wrapping up some updates, and your Mac will restart soon.\nPlease be patient as this may take up to 15 minutes.\n\nFor support, please contact the Help Desk by launching Self Service and clicking IT Help."</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
	logAction "Setting permissions on LaunchDaemon..."
	chown root:wheel /Library/LaunchDaemons/com.buoy.provisionWrapUp.plist
	chmod 644 /Library/LaunchDaemons/com.buoy.provisionWrapUp.plist
	logAction "Loading LaunchDaemon..."
	launchctl load -w /Library/LaunchDaemons/com.buoy.provisionWrapUp.plist
	
}

## If no updates needed or only non-restart updates installed, finish up and tell the user they're good to go
function cleanUpJCL {
	logAction "Cleaning up with no reboot..."
	killall jamfHelper
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -icon /System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns -heading "Enjoy your new Mac!" -description "We're wrapping up some final items and getting your Mac ready for use.
Once this screen is dismissed, you're all set!

For support, please contact the Help Desk by launching Buoy Self Service and clicking IT Help." &
	## Update inventory
	logAction "Running recon..."
	jamf recon >/dev/null
	## Kill the caffeinate process
	logAction "Sending barista $caffeinatePID home..."
	kill "${caffeinatePID}" >/dev/null
	authchangerReset
}

## If FileVault had to be called manually, a restart is needed
function cleanUpFileVault {
	logAction "Cleaning up with reboot for FileVault..."
	killall jamfHelper
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -icon /System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns -heading "Enjoy your new Mac!" -description "We're wrapping up some final items and getting your Mac ready for use.
Your Mac will restart in about one minute.

For support, please contact the Help Desk by launching Buoy Self Service and clicking IT Help." &
	## Update inventory
	logAction "Running recon..."
	jamf recon >/dev/null
	## Kill the caffeinate process
	logAction "Sending barista $caffeinatePID home..."
	kill "${caffeinatePID}" >/dev/null
	authchangerReset
	shutdown -r +1 &
}

function installUpdates {
	killall jamfHelper
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -icon "/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns" -heading "Installing Updates" -description "Checking for and installing pending macOS updates--this may take a few minutes..." &
	## Locate any available content caches
	logAction "Locating content caches..."
	AssetCacheLocatorUtil >/dev/null
	logAction "Checking for macOS Updates..."
	sleep 10
	restartCheck=$(softwareupdate --list 2>&1)

	## Depending on the value of $restartCheck, we can determine if updates are available and if they require a restart
	## If a pending update requires a restart, set $restartNeeded for later use
	## If pending updates do not require a restart, install them immediately
	## If no updates are available, no action is taken
	if [[ "$restartCheck" =~ "No new software available." ]]; then
		logAction "No updates pending."
	elif [[ "$restartCheck" =~ "restart" ]]; then
		logAction "Pending update requires a restart"
		restartNeeded="yes"
		softwareupdate --list 2>&1 | tee -a /var/log/provisioning.log
	else
		logAction "Updates pending, but no restart required. Installing now..."
		softwareupdate --install --all 2>&1 | tee -a /var/log/provisioning.log
	fi

}

########################################
############# Main Script ##############
########################################

## Start the log
logAction "===========Begin Provisioning Log==========="

## Install Rosetta 2 if on Apple Silicon
arch=$(/usr/bin/arch)

if [[ "$arch" == "arm64" ]]; then
	logAction "Installing Rosetta 2 for Apple Silicon..."
	/usr/sbin/softwareupdate --install-rosetta --agree-to-license
fi

## Wait for the user environment to be ready
waitForUser
mkdir -p "/Library/Buoy/Receipts/"

## Set the clock
systemsetup -setusingnetworktime On -setnetworktimeserver time.apple.com 2>&1 >/dev/null

## Keep the session active and grab the process ID to kill later
logAction "Getting some coffee..."
caffeinate -dis &
caffeinatePID=$!
logAction "Thanks to barista $caffeinatePID"

## Flush policy history in case the device has an existing inventory record
jamf flushPolicyHistory

## Run base configuration items
if [[  $(ps -ax | grep /Applications/Safari.app/Contents/MacOS/Safari | grep -v grep) ]]; then killall Safari; fi
runPolicies

## Set provisioning complete EA to true and update inventory
function finalRecon {
	killall jamfHelper
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -icon "/System/Library/CoreServices/Paired Devices.app/Contents/Resources/AppIcon.icns" -heading "Almost there!" -description "Submitting inventory data and assigning this computer to you..." &
	## Check to see if FileVault was already enabled by Jamf Connect Login
	## If not, call the FileVault enablement policy
	if [[ $(fdesetup status | head -n 1) == "FileVault is Off." ]]; then
		logAction "FileVault not yet enabled, calling policy..."
		jamf policy -id $encryptPolicyID
	fi
	logAction "Tagging provisioning complete..."
	touch "/Library/Buoy/Receipts/.provisioningComplete"
	logAction "Retrieving current user's display name for device affinity..."
	userRealName=$(dscl . -read /Users/$loggedInUser RealName)
	## In testing, macOS was exhibiting different behavior seemingly at random when grabbing the output of the above command
	## Sometimes it throws the RealName: label on a line above the actual value, and sometimes it's inline
	## A previous iteration used sed to remove the label, but that doesn't work reliably if it's on a different line
	## Because of that, we need some additional logic to filter it out
	if [[ $(echo $userRealName | wc -l) =~ "2" ]]; then
		## User's display name is on multiple lines, so tail the last line and remove the leading space
		userRealName=$(echo $userRealName | tail -n 1 | sed 's/ //')
	elif [[ $(echo $userRealName | wc -l) =~ "1" ]]; then
		## User's display name is on one line, so remove the RealName label
		userRealName=$(echo $userRealName | sed 's/RealName: //g')
	else
		## Something else happened--set a placeholder to fix later
		logAction "Error determining user's display name, setting to placeholder value for remediation..."
		userRealName="UNKNOWN"
	fi
	logAction "User's display name is $userRealName, assigning and running recon..."
	jamf recon -endUsername "$userRealName" >/dev/null
	logAction "Retrieving current user's email address for device affinity..."
	jamf recon -email $(defaults read com.jamf.connect.state DisplayName) >/dev/null
	## Call the policy to configure Okta Device Trust
	logAction "Configuring Okta Device Trust..."
	## Build LaunchDaemon to call policy
	## This is the only way found to successfully call this policy during provisioning
	## Likely because it's a python script being called from a binary called from a shell script called from a binary, aka a nightmare
	logAction "Building LaunchDaemon"
cat << EOF > /Library/LaunchDaemons/com.buoy.calloktatrust.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.buoy.calloktatrust</string>
	<key>LaunchOnlyOnce</key>
	<true/>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/local/bin/jamf</string>
		<string>policy</string>
		<string>-id</string>
		<string>9</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
	## Load the LaunchDaemon
	logAction "Setting permissions and loading LaunchDaemon"
	chown root:wheel /Library/LaunchDaemons/com.buoy.calloktatrust.plist
	chmod 644 /Library/LaunchDaemons/com.buoy.calloktatrust.plist
	launchctl load -w /Library/LaunchDaemons/com.buoy.calloktatrust.plist
	
	## Check the jamf log for a pid for the running policy
	## Once running, store the pid as $policyPid
	for policyCheck in {1..21}; do
		if [[ $policyCheck == "21" ]]; then
			logAction "Policy not detected running after 20 attempts, aborting..."
			break
		fi
		logAction "Waiting for Okta Device Trust policy to run (check $policyCheck of 20)..."
		policyPid=$(cat /var/log/jamf.log | awk '/Executing Policy Okta/ {print $6}' | sed 's/[^0-9]*//g')
		if [[ $policyPid != "" ]]; then
			logAction "Okta policy running (pid $policyPid), waiting for completion..."
			break
		else
			logAction "Okta policy not yet running, waiting..."
			sleep 2
		fi
	done
	
	## Wait for $policyPid to no longer be running, indicating the policy has finished
	until [[ $(ps -ax | grep $policyPid | sed -e '/grep/d') == "" ]]; do
		logAction "Policy still running, waiting..."
		sleep 2
	done
	
	## Check for presence of the Okta keychain
	logAction "Policy finished, checking for keychain..."
	if [[ -e /Users/$loggedInUser/Library/Keychains/okta.keychain-db ]]; then
		logAction "Okta keychain found"
	else
		logAction "Okta keychain not found"
	fi
	
	## Unload and remove the LaunchDaemon
	logAction "Unloading and removing LaunchDaemon..."
	launchctl unload /Library/LaunchDaemons/com.buoy.calloktatrust.plist 2>/dev/null
	rm /Library/LaunchDaemons/com.buoy.calloktatrust.plist 2>/dev/null
}

## Switch to the internal SSID if needed
if [[ $currentSSID == "Buoy Guest" ]]; then
	killall jamfHelper
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -icon "/System/Library/CoreServices/Applications/Network Utility.app/Contents/Resources/Network Utility.icns" -heading "Configuring Network Access" -description "Connecting you to Buoy Wi-Fi..." &
	## Update inventory with the provisioning complete extension attribute to trigger deployment of the Buoy SSID configuration profile
	finalRecon
	logAction "Waiting for Buoy SSID configuration profile..."
	sleep 10
	## Check up to 25 times for the presence of the profile
	## Ideally this should take no more than 1-2 re-checks
	for attempt in {1..26}; do
		## At 25 checks, give up and fail out
		## This isn't actually an unrecoverable error, but it's indicative of a larger problem that should get immediate support
		if [[ $attempt == "26" ]]; then
			logAction "Buoy profile not found after 26 attempts, notifying user..."
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -icon "/System/Library/CoreServices/Problem Reporter.app/Contents/Resources/ProblemReporter.icns" -heading "Provisioning Error" -description "An unrecoverable error has been encountered. Please contact IT for assistance. This message will be dismissed in 60 seconds." -timeout 60
			exit 1
		fi
		logAction "Waiting for Buoy SSID profile to be found (check $attempt of 50)..."
		## Check a list of installed configuration profiles for the UUID of the Buoy SSID payload
		## If found, break out of the loop
		## If not found, wait 10 seconds and check again
		if [[ $(profiles -L | grep "53A5425B-3EA2-45DC-A77C-D2C9EFAB6EE3") ]]; then
			logAction "Buoy profile found, continuing..."
			break
		else
			logAction "Buoy profile not found, checking again in 10 seconds..."
			sleep 10
		fi
	done

	## Remove Buoy Guest from the device's preferred networks list to keep it from reconnecting
	logAction "Removing Buoy Guest from preferred networks list..."
	networksetup -removepreferredwirelessnetwork $wifiPort "Buoy Guest"
	## Bounce the Wi-Fi hardware port to force reauthentication to Buoy
	logAction "Bringing $wifiPort down..."
	ifconfig $wifiPort down
	sleep 2
	logAction "Bringing $wifiPort back up..."
	ifconfig $wifiPort up
	## Allow some time for the device to authenticate, complete DHCP, etc.
	## Wait until a public IP is available
	logAction "Waiting for authentication to complete..."
	until [[ $(curl icanhazip.com 2>/dev/null) ]]; do
		logAction "No internet connectivity yet, waiting..."
		sleep 5
	done
fi

## Check for and install any pending updates
#installUpdates

## Clean up and reboot
logAction "All done, starting cleanup..."

## Launch Jamf Connect Sync
#logAction "Launching Jamf Connect Sync..."
#open jamfconnectsync://silentcheck-prompt

## Remove 'buoyadmin' account if present
if [[ $(dscl . -search /Users name buoyadmin) ]]; then
	logAction "Removing buoyadmin account..."
	dscl . -delete /Users/buoyadmin
	rm -r /Users/buoyadmin
fi

## If the cleanup recon hasn't run yet, run it now
if [[ ! -e /Library/Buoy/Receipts/.provisioningComplete ]]; then finalRecon; fi

## If updates are pending that need a reboot, run the appropriate function
## Otherwise, just clean up and exit
if [[ $restartNeeded ]]; then
	cleanUpWithUpdates
	logAction "Installing updates with restart..."
	softwareupdate --install --all --restart 2>&1
elif [[ $(fdesetup showdeferralinfo) == "Not found." ]]; then
	cleanUpJCL
else
	cleanUpFileVault
fi

logAction "===========End Provisioning Log==========="