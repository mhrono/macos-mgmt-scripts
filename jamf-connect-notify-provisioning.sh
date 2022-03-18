#!/bin/zsh

####
## Copyright 2022 Buoy Health, Inc.

## Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0.

## Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
####

## Author: Matt Hrono
## MacAdmins: @matt_h

## Provisioning script to direct Jamf Connect Notify

## There are numerous org-specific references made in this script
## If you want to use this in your environment, be sure to address them
## You'll also notice I install my own icon package and use those throughout
## How you address this is up to you

## Set some vars
logFile="/var/log/provisioning.log"
controlFile="/var/tmp/depnotify.log"
jamf="/usr/local/bin/jamf"
coreAppList=(
	"1Password"
	"Slack"
	"zoom.us"
	"Google Chrome"
)

## Logging
function logAction {
	logTime=$(date "+%Y-%m-%d - %H:%M:%S:")
	echo "$logTime" "$1" | tee -a $logFile
}

## Current epoch time
function currentTime {
	echo $(date -j -f "%a %b %d %T %Z %Y" "$(date)" "+%s")
}

## Time to sleep calculation
function sleepTime {
	now=$(currentTime)
	difference=$(($now - $1))
	if (( $difference > 20 )); then
		echo "0"
	else
		echo "$((20 - $difference))"
	fi
}

logAction "Provisioning started"

## Keep the session alive during provisioning
## Record the PID for caffeinate so it can be killed later
logAction "Getting some coffee..."
caffeinate -dis &
caffeinatePID=$!
logAction "Thanks to barista $caffeinatePID"

## Flush the policy history in case this is a re-enrollment
$jamf flushPolicyHistory

echo "STARTING RUN" >> $controlFile

userRealName=$(dscl . -read /Users/$(dscl . -list /Users UniqueID | grep 503 | awk '{print $1;}') RealName | tail -n 1 | sed 's/ //')

userFirstName=$(echo $userRealName | awk '{print $1}')

logAction "Current user is $userRealName"

## Steps for notify progress bar
echo "Command: Determinate: 20" >> $controlFile

## Greet the user
## While they're reading, install the shell library and check-in watcher
echo "Command: Image: "/opt/buoy/images/buoy_logo.png"" >> $controlFile
echo "Command: MainTitle: Hey $userFirstName, welcome to Buoy!" >> $controlFile
echo "Command: MainText: Your Mac is now enrolled into management and will be automatically configured.\r\rThis should take 10-15 minutes, depending on your Internet connection speed." >> $controlFile
echo "Status: Making system ready for provisioning..." >> $controlFile
logAction "Installing shell library..."
startTime=$(currentTime)
$jamf policy -event install-shellLibrary -forceNoRecon
sleep $(sleepTime $startTime)
logAction "Installing check-in watcher..."
startTime=$(currentTime)
$jamf policy -event install-checkinWatcher -forceNoRecon
sleep $(sleepTime $startTime)

## Install the Jamf Connect LaunchAgent
echo "Command: Image: "/opt/buoy/images/keychainaccess.icns"" >> $controlFile
echo "Command: MainTitle: Tired of remembering passwords?" >> $controlFile
echo "Command: MainText: We use Okta single sign-on to help you sign in to each of our corporate services.\r\rUse your email address and Okta password to sign in to your apps." >> $controlFile
echo  "Status: Setting the password for your Mac to sync with your Okta password..." >> $controlFile
logAction "Installing Jamf Connect LaunchAgent..."
startTime=$(currentTime)
$jamf policy -event install-jcla -forceNoRecon
sleep $(sleepTime $startTime)

## Set hostname
echo "Command: Image: "/opt/buoy/images/darkmodeicon.png"" >> $controlFile
echo "Command: MainTitle: Prefer to live on the dark side?" >> $controlFile
echo "Command: MainText: Dark mode can be enabled from System Preferences > General." >> $controlFile
echo "Status: Configuring network services..." >> $controlFile
logAction "Setting hostname..."
startTime=$(currentTime)
$jamf policy -event setHostname -forceNoRecon
sleep 5
logAction "Hostname set to $(scutil --get ComputerName)"
sleep $(sleepTime $startTime)

## Enable firewall
echo "Command: Image: "/opt/buoy/images/touchid.png"" >> $controlFile
echo "Command: MainTitle: Unlock with a tap!" >> $controlFile
echo "Command: MainText: Touch ID can be enabled from System Preferences > Touch ID." >> $controlFile
echo "Status: Activating security framework..." >> $controlFile
logAction "Enabling firewall..."
startTime=$(currentTime)
$jamf policy -event setFirewall -forceNoRecon
sleep $(sleepTime $startTime)

## Enable NTP
echo "Command: Image: "/opt/buoy/images/clock.icns"" >> $controlFile
echo "Command: MainTitle: Time check!" >> $controlFile
echo "Command: MainText: macOS may default to the Pacific Time Zone. To change this, go to System Preferences > Date & Time > Time Zone.\r\rClick the lock in the bottom left corner and enter your password to edit. Then, click on the map close to your location." >> $controlFile
echo "Status: Activating security framework..." >> $controlFile
logAction "Enabling network time sync..."
startTime=$(currentTime)
systemsetup -setusingnetworktime On -setnetworktimeserver time.apple.com 2>&1 >/dev/null
sleep $(sleepTime $startTime)

## Install Rosetta 2 if running on Apple Silicon
echo "Command: Image: "/opt/buoy/images/selfservice.png"" >> $controlFile
echo "Command: MainTitle: Self Service makes apps easy!" >> $controlFile
echo "Command: MainText: Essential apps will be installed automatically. Self Service includes installers for other applications you might need." >> $controlFile
echo "Status: Installing Self Service..." >> $controlFile
startTime=$(currentTime)
if [[ $(/usr/bin/arch) == "arm64" ]]; then
	logAction "Installing Rosetta 2..."
	/usr/sbin/softwareupdate --install-rosetta --agree-to-license
fi
sleep $(sleepTime $startTime)

## Install managed python environment
echo "Command: Image: "/opt/buoy/images/controlcenter.icns"" >> $controlFile
echo "Command: MainTitle: Installing IT Toolkit" >> $controlFile
echo "Command: MainText: The fastest way to get IT help is by using the Service Desk.\r\rTo reach the portal, launch Self Service and click IT Help on the left hand side." >> $controlFile
echo "Status: Configuring support resources..." >> $controlFile
logAction "Installing managed Python3..."
startTime=$(currentTime)
$jamf policy -event install-managedPython -forceNoRecon
sleep $(sleepTime $startTime)

## Install CrowdStrike and Zscaler
echo "Command: Image: "/opt/buoy/images/security.icns"" >> $controlFile
echo "Command: MainTitle: Keeping Your Mac Secure" >> $controlFile
echo "Command: MainText: We're configuring some services to help keep you safe and secure while you work." >> $controlFile
echo "Status: Installing CrowdStrike AntiMalware..." >> $controlFile
logAction "Installing CrowdStrike..."
startTime=$(currentTime)
$jamf policy -event crowdstrike -forceNoRecon
sleep $(sleepTime $startTime)
echo "Status: Installing Zscaler Internet Security..." >> $controlFile
logAction "Installing Zscaler..."
startTime=$(currentTime)
$jamf policy -event install-Zscaler -forceNoRecon
sleep $(sleepTime $startTime)

## Install core apps
for app in "${coreAppList[@]}"; do
	echo "Command: Image: "/opt/buoy/images/$app.icns"" >> $controlFile
	echo "Command: MainTitle: Installing Core Buoy Apps" >> $controlFile
	echo "Command: MainText: These apps will be kept up to date automatically so you can spend less time updating and more time helping to change the world of healthcare!" >> $controlFile
	echo "Status: Installing $app..." >> $controlFile
	logAction "Installing $app..."
	startTime=$(currentTime)
	$jamf policy -event "autoupdate-$app" -forceNoRecon
	sleep $(sleepTime $startTime)
done

## Set the dock using a LaunchAgent so it runs in the correct user context
echo "Command: Image: "/opt/buoy/images/cert.icns"" >> $controlFile
echo "Command: MainTitle: Setting Up Your Dock" >> $controlFile
echo "Command: MainText: The apps we just installed are being placed on your Dock for easy access." >> $controlFile
echo "Status: Configuring Dock..." >> $controlFile
logAction "Setting default Dock..."
startTime=$(currentTime)
cat << EOF > /Library/LaunchAgents/com.buoy.setDock.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.buoy.setDock</string>
	<key>LaunchOnlyOnce</key>
	<true/>
	<key>ProgramArguments</key>
	<array>
		<string>/opt/buoy/bin/python3</string>
		<string>/opt/buoy/provisioning/setDock.py</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
chown root:wheel /Library/LaunchAgents/com.buoy.setDock.plist
chmod 644 /Library/LaunchAgents/com.buoy.setDock.plist
launchctl asuser 503 launchctl load /Library/LaunchAgents/com.buoy.setDock.plist
sleep $(sleepTime $startTime)

echo "Command: Image: "/opt/buoy/images/ticketviewer.icns"" >> $controlFile
echo "Command: MainTitle: Registering Your Mac With Okta" >> $controlFile
echo "Command: MainText: Okta is generating a certificate on your Mac to identify it as trusted.\r\rThis helps keep Buoy compliant with security policies and HITRUST requirements." >> $controlFile
echo "Status: Configuring Okta Device Trust..." >> $controlFile
sleep 10

echo "Command: Image: "/opt/buoy/images/zscaler.icns"" >> $controlFile
echo "Command: MainTitle: IMPORTANT! Sign In to Zscaler" >> $controlFile
echo "Command: MainText: In a few moments, you'll see the Zscaler sign-in window.\r\rPlease sign in using your Okta username and password to begin securing your Internet connection and unlock access to Buoy services." >> $controlFile
echo "Status: Zscaler runs transparently in the background once you're signed in." >> $controlFile
sleep 15

## Validate everything installed properly
echo "Command: Image: "/opt/buoy/images/activitymonitor.icns"" >> $controlFile
echo "Command: MainTitle: Validating Setup" >> $controlFile
echo "Command: MainText: We're running some quick checks to make sure everything's in order." >> $controlFile
echo "Status: Just a moment!" >> $controlFile
logAction "Running app installation checks..."
for app in "${coreAppList[@]}"; do
	if [[ ! $(ls /Applications | grep $app) ]]; then
		logAction "Missing $app, calling installer again..."
		$jamf policy -event "autoupdate-$app"
	else
		logAction "Found $app"
		sleep 2
	fi
done

## Set a var if any of these checks fail
logAction "Running full provisioning validation..."
appListFull=(
	"1Password"
	"Falcon"
	"Google Chrome"
	"Jamf Connect"
	"Slack"
	"zoom.us"
	"Zscaler"
)
for app in "${appListFull[@]}"; do
	if [[ ! $(ls /Applications | grep $app) ]]; then
		logAction "Missing $app, logging failure..."
		defaults write /opt/buoy/provisioning/com.buoy.provisioning.failure.plist $app -bool TRUE
	else
		logAction "Found $app"
		sleep 1
	fi
done

if [[ $(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | awk '{print $3}' | sed 's/\.$//') != "enabled" ]]; then
	logAction "Firewall not enabled, logging failure..."
	defaults write /opt/buoy/provisioning/com.buoy.provisioning.failure.plist firewall -bool TRUE
fi

if [[ ! -f /opt/buoy/shell/jamf.sh ]]; then
	logAction "Shell library not found, logging failure..."
	defaults write /opt/buoy/provisioning/com.buoy.provisioning.failure.plist shellLibrary -bool TRUE
fi

if [[ ! -e /opt/buoy/bin/python3 ]]; then
	logAction "Managed Python not found, logging failure..."
	defaults write /opt/buoy/provisioning/com.buoy.provisioning.failure.plist managedPython -bool TRUE
fi

## Tell the user if something failed
if [[ -e /opt/buoy/provisioning/com.buoy.provisioning.failure.plist ]]; then
	echo "Command: Image: "/opt/buoy/images/problem.icns"" >> $controlFile
	echo "Command: MainTitle: Something's Not Quite Right" >> $controlFile
	echo "Command: MainText: Part of the provisioning process wasn't successfully validated, but not to worry!\rIT has been notified and will follow up if needed.\r\rProvisioning will continue." >> $controlFile
	sleep 15
fi

## Populate user information in the device's jamf record
echo "Command: Image: "/opt/buoy/images/finder.icns"" >> $controlFile
echo "Command: MainTitle: Wrapping Up" >> $controlFile
echo "Command: MainText: Just a few cleanup tasks to complete, and you'll be all set!" >> $controlFile
echo "Status: Assigning this Mac to you..." >> $controlFile
logAction "Setting device affinity..."
startTime=$(currentTime)
$jamf recon -endUsername "$userRealName"
$jamf recon -email "$(dscl . -list /Users UniqueID | grep 503 | awk '{print $1;}')@buoyhealth.com"
sleep $(sleepTime $startTime)

## Remove the buoyadmin account created during PreStage Enrollment
echo "Status: Removing temporary setup resources..." >> $controlFile
if [[ $(dscl . -search /Users name buoyadmin) ]]; then
	logAction "Removing buoyadmin account..."
	dscl . -delete /Users/buoyadmin
	rm -r /Users/buoyadmin
fi
sleep 5

## Wrapping up
echo "Command: MainTitle: Enjoy your new Mac!" >> $controlFile
echo "Command: MainText: We hope your onboarding has gone smoothly.\rIf you have any feedback about your technology setup experience, please reach out to IT. This screen will be dismissed shortly.\r\rThank you!" >> $controlFile
echo "Status: All done!" >> $controlFile
mkdir -p "/Library/Buoy/Receipts/"
logAction "Writing provisioning complete receipt..."
startTime=$(currentTime)
touch "/Library/Buoy/Receipts/.provisioningComplete"
logAction "Updating inventory..."
$jamf recon
sleep $(sleepTime $startTime)

## Bye
echo "Command: Quit" >> $controlFile
sleep 1
rm -rf $controlFile
logAction "Sending barista $caffeinatePID home..."
kill "${caffeinatePID}"
logAction "Provisioning complete, resetting authchanger..."
/usr/local/bin/authchanger -reset ## Disable Jamf Connect Login and reset the loginwindow back to macOS native

## Recon a few times to ensure the FileVault Recovery Key is fully escrowed to jamf
sleep 15
$jamf recon
sleep 15
$jamf recon

## Unload and delete the LaunchAgent and resources for setting the Dock
sleep 60
launchctl asuser 503 launchctl unload /Library/LaunchAgents/com.buoy.setDock.plist
rm /Library/LaunchAgents/com.buoy.setDock.plist
rm /opt/buoy/provisioning/setDock.py

## Run a final check to make sure FileVault is enabled, and log the error if not
if [[ $(fdesetup status | awk '{print $NF}') != "On." ]]; then
	logAction "FileVault not enabled, logging failure..."
	defaults write /opt/buoy/provisioning/com.buoy.provisioning.failure.plist filevault -bool TRUE
	$jamf recon
fi