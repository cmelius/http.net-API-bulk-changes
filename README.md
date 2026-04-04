# http.net-API-bulk-changes
powershell script to bulk change some values (TTL only for now) for http.net clients. Useful for Server / IP-Change.

For a server switch with DNS-Zones hosted at https://http.net I needed to bulk change the TTL of all A-records.
The frontend at https://partner.http.net/dns/ allows bulk content change via https://partner.http.net/dns/zones/content-change
but lowering the TTL for all domains is only possible via the http.net API. 

@see: https://www.http.net/docs/api/

# HowTo
1. get an API-key at: https://partner.http.net/profile (at the bottom)
2. grant rights to: "DNS-Service" read for all, edit for "Zonen"
3. adjust variables at lines 1 - 4
  - $apiKey = "your-api-key" 
  - $targetIp = "server-ip"
  - $newTtl = 300 # 5 minutes or whatever is needed
  - $testDomain = "test-domain" # add one test domain to try.
5. run the script in Windows poershell or Powershell 7. It will only change TTL for the testDomain.
6. Uncomment the final block at the bottom of the script to iterate over all domains in your account pointing to <server-ip>.

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
