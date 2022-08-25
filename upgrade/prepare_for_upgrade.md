# Prepare for Upgrade

Before beginning an upgrade to a new version of CSM, there are a few things to do on the system first.

1. Understand that management service resiliency is reduced during the upgrade.

   **Warning:** Although it is expected that compute nodes and application nodes will continue to provide their services
   without interruption, it is important to be aware that the degree of management services resiliency is reduced during the
   upgrade. If, while one node is being upgraded, another node of the same type has an unplanned fault that removes it from service,
   there may be a degraded system. For example, if there are three Kubernetes master nodes and one is being upgraded, the quorum is
   maintained by the remaining two nodes. If one of those two nodes has a fault before the third node completes its upgrade,
   then quorum would be lost.

1. Check for BOS, CFS, CRUS, FAS, or NMD sessions.

    1. (`ncn-m001#`) Ensure that these services do not have any sessions in progress.

        > This SAT command has `shutdown` as one of the command line options, but it will not start a shutdown process on the system.

        ```bash
        sat bootsys shutdown --stage session-checks
        ```

        Example output:

        ```text
        Checking for active BOS sessions.
        Found no active BOS sessions.
        Checking for active CFS sessions.
        Found no active CFS sessions.
        Checking for active CRUS upgrades.
        Found no active CRUS upgrades.
        Checking for active FAS actions.
        Found no active FAS actions.
        Checking for active NMD dumps.
        Found no active NMD dumps.
        No active sessions exist. It is safe to proceed with the shutdown procedure.
        ```

        If active sessions are running, then either wait for them to complete or shut down, cancel, or delete them.

    1. Coordinate with the site to prevent new sessions from starting in these services.

        There is currently no method to prevent new sessions from being created as long as the service APIs are accessible on the API gateway.

1. Validate CSM Health

    Run the CSM health checks to ensure that everything is working properly before the upgrade starts.

    **`IMPORTANT`**: See the `CSM Install Validation and Health Checks` procedures in the documentation for the **`CURRENT`** CSM version on
    the system. The validation procedures in the CSM documentation are not all intended to work on previous versions of CSM.

1. Validate Lustre Health

   If a Lustre file system is being used, then see the ClusterStor documentation for details on how to check
   for Lustre health.

1. Configure CHN (optional)

    This release introduces the ability to route customer access traffic to the high-speed network instead of the management network.  This feature is called the Customer High-speed Network (CHN).  By default the customer access network (CAN) is routed over the management network.

    If the CHN is the desired network for customer access, the associated system configuration change should be made before starting the CSM upgrade.  sSe [Enable Customer High Speed Network Routing](../operations/network/management_network/bican_enable.md).

    This should be completed before the management nodes are upgraded so that the correct HSN IP addresses are allocated and applied during the upgrade.

1. Update the Management Network Switches

    Updating the management network switch configurations is necessary to deploy new security updates including ACL changes.

    A switch configuration update is also required if CHN has been enabled.  Specifically, the BGP configuration on the edge switch needs to be updated to match the system if it has changed between CAN and CHN for user access.  It is also necessary to change the VLAN tagging on the switch ports to properly separate user and admin traffic.

    The update of the management network switches is separate from the CSM upgrade and should be done before starting the CSM upgrade.  The specifics of the network upgrade can vary from site to site, so a networking subject matter expert is required.
