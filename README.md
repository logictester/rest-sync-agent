# rest-sync-agent
 Synchronize via REST API Active Directory Users to SafeNet Trusted Access 

## author
 Cina Shaykhian <cina.shaykhian@thalesgroup.com>

## version
 Build 0.13 (testing only) - 2021.03.21

## Table of contents
* [Overview](#overview)
* [Requirements](#requirements)
* [Setup](#setup)

## Overview
This project is simple Lorem ipsum dolor generator.
	
## Requirements
Project is created with:
* PowerShell: 3.0 and above
* Windows Server (if necessary `Import-Module ActiveDirectory`)
	
## Setup
First configure `config\agent.config`:

```
# REST API key (find in STA console)
API_key=YOUR_SECRET_REST_API_KEY_HERE

# REST API endpoint (find in STA console)
API_endpoint=https://api.<ZONE>.safenetid.com/api/v1/tenants/<STA_TENANT_ID>/users

# Comma separated AD groups to sync
Groups=Dummy Group 1, Dummy Group 2, ...
```

Then use `.\rest-sync-agent.ps1` to run.
