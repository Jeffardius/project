# Remove any existing lease for 192.168.99.82
Remove-DhcpServerv4Lease -ScopeId 192.168.99.80 -IPAddress 192.168.99.82 -Confirm:$false -ErrorAction SilentlyContinue
# Restart DHCP server
Restart-Service DHCPServer
