# http.net-API-bulk-changes
Scripts to bulk change some values (TTL only for now) for http.net clients. Useful for Server / IP-Change.
Available as PowerShell script (Windows) and Bash script (Linux / macOS / WSL).

For a server switch with DNS-Zones hosted at https://http.net I needed to bulk change the TTL of all A-records.
The frontend at https://partner.http.net/dns/ allows bulk content change via https://partner.http.net/dns/zones/content-change
but lowering the TTL for all domains is only possible via the http.net API. 

@see: https://www.http.net/docs/api/

# Preparation (both scripts)
1. get an API-key at: https://partner.http.net/profile (at the bottom)
2. grant rights to: "DNS-Service" read for all, edit for "Zonen"

# HowTo: PowerShell (Windows) – `update-ttl.ps1`
1. adjust variables at lines 1 - 4
  - $apiKey = "your-api-key" 
  - $targetIp = "server-ip"
  - $newTtl = 300 # 5 minutes or whatever is needed
  - $testDomain = "test-domain" # add one test domain to try.
2. run the script in Windows PowerShell or PowerShell 7. It will only change TTL for the testDomain.
3. Uncomment the final block at the bottom of the script to iterate over all domains in your account pointing to <server-ip>.

# HowTo: Bash (Linux / macOS / WSL) – `update-ttl.sh`
Requirements: `bash`, `curl`, `jq` (e.g. `sudo apt install curl jq`)

Instead of editing the script, all values can be passed as options or environment variables
(editing the defaults at the top of the script works as well).

| Option            | Environment variable | Meaning                                   |
|-------------------|----------------------|-------------------------------------------|
| `-k, --api-key`   | `HTTPNET_API_KEY`    | http.net API key                          |
| `-i, --ip`        | `TARGET_IP`          | only A records pointing to this IP        |
| `-t, --ttl`       | `NEW_TTL`            | new TTL in seconds (default: 300)         |
| `-d, --domain`    | `TEST_DOMAIN`        | test domain (step 1)                      |
| `-a, --all`       |                      | process ALL zones of the account (step 2) |
| `-n, --dry-run`   |                      | only show what would change, no update    |
| `-h, --help`      |                      | show help                                 |

```bash
chmod +x update-ttl.sh

# keep the API key out of your shell history / the repo
read -rsp "API key: " HTTPNET_API_KEY && export HTTPNET_API_KEY

# Step 1: test with one domain – first dry-run, then for real
./update-ttl.sh -i 203.0.113.10 -d example.com --dry-run
./update-ttl.sh -i 203.0.113.10 -d example.com

# Step 2: all domains pointing to the IP – first dry-run, then for real
./update-ttl.sh -i 203.0.113.10 --all --dry-run
./update-ttl.sh -i 203.0.113.10 --all
```

Differences to the PowerShell version:
- step 2 (all domains) is enabled with `--all` instead of uncommenting code
- `--dry-run` only reads from the API and lists the records that would be changed – safe to run anytime
- records that already have the desired TTL are skipped
- results are paginated, so accounts with more than 100 zones / records per zone are handled completely

Note (both scripts): the test domain is matched as wildcard `*domain*`, so `-d example.com` also
matches e.g. `myexample.com`. Check the output (or use `--dry-run`) before running for real.

# Example output
- --- Step 1: Testing with "test-domain ---
- DEBUG: Found 1 zone configurations.
- DEBUG: Fetching records for zone: test-domain (ID: XXXXXXXXXXXXXXXXX)
- DEBUG: Found 14 records in zone test-domain.
- Found 4 A records for test-domain pointing to server-ip.
- Updating records for zone: test-domain
- DEBUG: First record properties: accountId, addDate, comments, content, id, lastChangeDate, name, priority, recordTemplateId, ttl, type, zoneConfigId, zoneName
-   Successfully updated 4 records in test-domain (Status: pending).

Info: Status: pending is ok. check domains at https://partner.http.net/ after a few seconds, the changes should be registered.

done, enjoy!

# License and Copyright
This is free software.
