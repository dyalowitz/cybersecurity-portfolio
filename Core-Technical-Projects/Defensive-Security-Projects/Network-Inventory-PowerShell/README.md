# Network Inventory (PowerShell)

## Overview

`Collect-NetworkInventory.ps1` resolves inventory targets from one or more sources:

- `-ComputerName` for direct host entries.
- `-ComputerListPath` for a text file of hostnames or IPs (one per line).
- `-UseActiveDirectory` to pull computer names from Active Directory.
- `-NetworkCIDR` to scan a CIDR range, probe reachability, and attempt reverse DNS lookup.

When `-NetworkCIDR` is provided, the script writes discovered targets to a timestamped file named
`targets-<timestamp>.txt` in the output directory. Each line contains the resolved hostname (if
available) or the IP address.

## Usage

```powershell
.\Collect-NetworkInventory.ps1 -NetworkCIDR "192.168.99.0/24" -OutputDirectory "C:\Inventory"
```

## Output

- `targets-<timestamp>.txt` in the specified output directory.
