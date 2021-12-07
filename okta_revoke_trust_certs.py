#!/usr/bin/python3

"""
Copyright 2021 Buoy Health, Inc.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0.

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
"""

## Source: #okta on the MacAdmins Slack with minor changes by Matt @ Buoy
## https://macadmins.slack.com/archives/C0LFP9CP6/p1590563733203800

import argparse
import json
import objc
import os
import subprocess
import sys
from SystemConfiguration import SCDynamicStoreCopyConsoleUser
from Foundation import NSBundle

## Configure arguments for interactive use
parser = argparse.ArgumentParser(description='Revoke Okta Device Trust certificates issued to a device by UDID.')
group = parser.add_argument_group('required arguments')
group.add_argument('-s', '--server', required=True, help='Okta tenant URL (ex: "https://example.okta.com")')
group.add_argument('-t', '--token', required=True, help='Okta SSWS API token--the "SSWS" tag MUST be prepended (ex: "SSWS [token hash]"')
parser.add_argument('-u', '--udid', help='Optional: Device UDID to have certificates revoked--uses this device by default.')

def runCommand(cmd):
    output = subprocess.run(cmd, shell=True, check=False, capture_output=True)
    
    if output.returncode != 0:
        print(f'Error running command: {output.args}')
        print(f'Command return code: {output.returncode}, Message: {output.stderr}')
        
    return output.stdout.decode('utf8'), output.stderr.decode('utf8')

## Check if script is running via jamf and parse arguments accordingly
## If running from jamf, the script will be running from the path shown below
if 'Library/Application Support/JAMF/tmp' in os.path.abspath(__file__):
    SERVER = sys.argv[4]
    ORG_API_TOKEN = sys.argv[5]
    MAC_UDID = None
else:
    args = parser.parse_args()
    SERVER = args.server
    ORG_API_TOKEN = args.token
    MAC_UDID = args.udid

## Code to get the hardware UDID used for searching the Okta API
## Source: https://gist.github.com/erikng/46646ff81e55b42e5cfc
def get_hardware_uuid():
    
    cmd = "/usr/sbin/system_profiler SPHardwareDataType | grep 'Hardware UUID' | awk '{print $3}'"
    
    stdout, _ = runCommand(cmd)
    
    uuid = stdout.strip()
    
    return uuid

if not MAC_UDID:
    MAC_UDID = get_hardware_uuid()

def get_and_revoke_certs():
    url = '%s/api/v1/internal/devices/%s/credentials/keys' % (SERVER, MAC_UDID)
    print('Getting certs for device: ' + MAC_UDID)
    
    cmd = f"/usr/bin/curl -sS -X GET -H 'Authorization: {ORG_API_TOKEN}' {url}"
    
    stdout, _ = runCommand(cmd)

    print(f'Response: {stdout.strip()}')
    
    try:
        data = json.loads(stdout)
    except:
        print(f'Could not process output JSON, exiting')
        exit(1)
        
    if not data:
        print('No certs found')
        exit(0)
    for key in data:
        revoke_cert(key['kid'])
    print('Finished')

def revoke_cert(kid):
    url = '%s/api/v1/internal/devices/%s/keys/%s/lifecycle/revoke' % (SERVER, MAC_UDID, kid)
    print("Revoking certificate: " + kid)
    
    cmd = f"/usr/bin/curl -sS -X POST -H 'Authorization: {ORG_API_TOKEN}' {url}"
    
    stdout, _ = runCommand(cmd)
        
    print(f'Response: {stdout.strip()}')
    
def remove_keychain():
    """
    The device trust registration script will not issue a new certificate if one already exists
    Any existing keychains must be removed before the registration script runs again
    """
    username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in ["loginwindow", None, ""]]
    keychain = "/Users/{}/Library/Keychains/okta.keychain-db".format(username)
    if os.path.exists(keychain):
        print("Removing keychain {}...".format(keychain))
        os.remove(keychain)

## Remove keychains and revoke certs
remove_keychain()
get_and_revoke_certs()