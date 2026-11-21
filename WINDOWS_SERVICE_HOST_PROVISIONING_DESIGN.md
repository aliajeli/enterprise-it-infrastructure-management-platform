## Implementation status — v0.1.79

The API Windows Service Host runtime milestone has passed exact-head Windows CI acceptance on v0.1.78. Push run 44906623563 and PR run 44906628820 both completed successfully.

The Windows SCM smoke passed service creation under the hosted runner's LocalService identity, SERVICE_SID_TYPE_UNRESTRICTED, parent and child service-SID token validation, loopback readiness, graceful SCM stop, child reaping, and failed-readiness startup cleanup. The same job passed all 17 service-host lifecycle tests, DPAPI helper checks, keyring helper fail-closed checks, read-only installer preflight tests, Windows API typecheck/tests and API build.

The hosted runner returned Win32 1057 for NT SERVICE virtual-account assignment, so the SCM smoke uses LocalService only as its CI test logon identity. This is not the production account choice. The installer must configure NT SERVICE\EnterpriseITApi and prove that identity, child SID inheritance, and final ACLs on a clean supported Windows Server VM.

Scope boundary: the API Service Host runtime is complete. The installer and permanent service provisioning are not. Remaining work includes immutable Program Files ACLs, protected ProgramData/configuration, SCM recovery policy, clean Windows Server matrix testing, the remaining four independent services, Credential Vault storage approval, offline runtime/database packaging, installer creation, and install/upgrade/repair/uninstall plus backup/restore/rollback acceptance. The host does not register itself, create final ACLs, configure firewall rules, or change RouterOS/network settings.

