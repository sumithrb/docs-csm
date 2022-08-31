# Determine if Pods are Hitting Resource Limits

Determine if a pod is being CPU throttled or hitting its memory limits \(OOMKilled\). Use the detect\_cpu\_throttling.sh script to determine if any pods are being CPU throttled, and check the Kubernetes events to see if any pods are hitting a memory limit.

**IMPORTANT:** The presence of CPU throttling does not always indicate a problem, but if a service is being slow or experiencing latency issues, this procedure can be used to evaluate if it is not performing well as a result of CPU throttling.

Identify pods that are hitting resource limits in order to increase the resource limits for those pods.

### Prerequisites

`kubectl` is installed.

### Procedure

1.  Use the detect\_cpu\_throttling.sh script to determine if any pods are being CP throttled.

    1.  Install the script.

        The script can be installed on `ncn-w001`, or any NCN that can SSH to worker nodes.

        ```bash
        cat detect_cpu_throttling.sh
        ```
        
        ```bash
        #!/bin/sh
        # Usage: detect_cpu_throttling.sh [pod_name_substr] (default evaluates all pods)

        str=$1
        : ${str:=.}

        while read ns pod node; do
          echo ""
          echo "Checking $pod"
          while read -r container; do
            uid=$(echo $container | awk 'BEGIN { FS = "/" } ; {print $NF}')
            ssh -T ${node} <<-EOF
                dir=$(find /sys/fs/cgroup/cpu,cpuacct/kubepods/burstable -name *${uid}* 2>/dev/null)
                [ "${dir}" = "" ] && { dir=$(find /sys/fs/cgroup/cpu,cpuacct/system.slice/containerd.service -name *${uid}* 2>/dev/null); }
                if [ "${dir}" != "" ]; then
                  num_periods=$(grep nr_throttled ${dir}/cpu.stat | awk '{print $NF}')
                  if [ ${num_periods} -gt 0 ]; then
                    echo "*** CPU throttling for containerid ${uid}: ***"
                    cat ${dir}/cpu.stat
                    echo ""
                  fi
                fi
        	EOF
          done <<< "`kubectl -n $ns get pod $pod -o yaml | grep ' - containerID'`"
        done <<<"$(kubectl get pods -A -o wide | grep $str | grep Running | awk '{print $1 " " $2 " " $8}')"
        ```

    2.  Determine if any pods are being CPU throttled.

        The script can be used in two different ways:

    -   Pass in a substring of the desired pod name\(s\).

        In the example below, the externaldns pods are being used.

        ```bash
        ./detect_cpu_throttling.sh externaldns
        ```

        Example output:

        ```
        Checking cray-externaldns-coredns-58b5f8494-c45kh

        Checking cray-externaldns-coredns-58b5f8494-pjvz6

        Checking cray-externaldns-etcd-2kn7w6gnsx

        Checking cray-externaldns-etcd-88x4drpv27

        Checking cray-externaldns-etcd-sbnbph52vh

        Checking cray-externaldns-external-dns-5bb8765896-w87wb
        *** CPU throttling: ***
        nr_periods 1127304
        nr_throttled 473554
        throttled_time 71962850825439
        ```

    -   Call the script without a parameter to evaluate all pods.

        It can take two minutes or more to run when evaluating all pods:

        ```bash
        ./detect_cpu_throttling.sh
        ```

        Example output:

        ```text
        Checking cray-ceph-csi-cephfs-nodeplugin-zqqvv

        Checking cray-ceph-csi-cephfs-provisioner-6458879894-cbhlx

        Checking cray-ceph-csi-cephfs-provisioner-6458879894-wlg86

        Checking cray-ceph-csi-cephfs-provisioner-6458879894-z85vj

        Checking cray-ceph-csi-rbd-nodeplugin-62478
        *** CPU throttling for containerid 0f52122395dcf209d851eed7a1125b5af8a7a6ea1d8500287cbddc0335e434a0: ***
        nr_periods 14338
        nr_throttled 2
        throttled_time 590491866

        [...]
        ```

2.  Check if a pod was killed/restarted because it reached its memory limit.

    1.  Look for a Kubernetes event associated with the pod being killed/restarted.

        ```bash
        kubectl get events -A | grep -C3 OOM
        ```

        Example output:

        ```
        default   54m    Warning   OOMKilling  node/ncn-w003  Memory cgroup out of memory: Kill process 1223856 (prometheus) score 1966 or sacrifice child
        default   44m    Warning   OOMKilling  node/ncn-w003  Memory cgroup out of memory: Kill process 1372634 (prometheus) score 1966 or sacrifice child
        ```

    2.  Determine which pod was killed using the output above.

        Use grep on the string returned in the previous step to find the pod name. In this example, prometheus is used.

        ```bash
        kubectl get pod -A | grep prometheus
        ```

Follow the procedure to increase the resource limits for the pods identified in this procedure. See [Increase Pod Resource Limits](Increase_Pod_Resource_Limits.md).

