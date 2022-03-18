#!/usr/bin/env python3

####
## Copyright 2022 Buoy Health, Inc.

## Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0.

## Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
####

## Author: Matt Hrono
## MacAdmins: @matt_h

import subprocess
import sys
from time import sleep
from docklib import Dock

def wait_for_dock(max_time=300):
	"""Wait for Dock to launch. Bail out if we reach max_time seconds."""
	
	count = 0
	check_cmd = ["/usr/bin/pgrep", "-qx", "Dock"]
	
	# Check every 1 second for the Dock process
	while subprocess.run(check_cmd).returncode != 0:
		if count >= max_time:
			# We reached our max_time
			sys.exit(1)
			
		# Increment count and wait one second before looping
		count += 1
		sleep(1)
		
		
def main():
	"""Main process."""
	
	# Wait maximum 300 seconds for Dock to start
	wait_for_dock(300)
	
	# Load current Dock
	dock = Dock()
	
	# Define list of apps, from left to right
	desired_apps = [
		"/Applications/Google Chrome.app",
		"/Applications/Slack.app",
		"/Applications/zoom.us.app",
		"/Applications/1Password 7.app",
		"/Applications/Self Service.app",
		"/System/Applications/System Preferences.app",
	]
	
	# Set persistent-apps as desired
	p_apps = []
	for app in desired_apps:
		p_apps.append(dock.makeDockAppEntry(app))
	dock.items["persistent-apps"] = p_apps

	# Save changes and relaunch Dock
	dock.save()
	
	
if __name__ == "__main__":
	main()
EOF