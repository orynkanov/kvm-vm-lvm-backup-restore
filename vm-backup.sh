#!/bin/bash

BACKUPDIR=/mnt/backup
DATE=$(date +%Y%m%d_%H%M)
DDCMD=dcfldd
DDOPT="conv=notrunc,noerror"
LVSNAPSIZE=10G

if [ $# -eq 0 ]; then
    echo "VM not defined"
    exit 1
fi

_vmexist(){
    LANG=C virsh dominfo "$1" 2>/dev/null | grep -c UUID
}

_vmisrun(){
    LANG=C virsh domstate "$1" | grep -c run
}

_vmisshut(){
    LANG=C virsh domstate "$1" | grep -c shut
}

_syncfs(){
	virsh send-key "$1" KEY_LEFTALT KEY_SYSRQ KEY_S 1>/dev/null
	sleep 10
}

_vmsave(){
    virsh save "$1" "$2" --running 1>/dev/null
}

_vmrestore(){
    virsh restore "$1" 1>/dev/null
}

_vmgetdisks(){
    virsh domblklist "$1" --details | awk '/disk/ { print $4}'
}


_lvsnap(){
    LVBASENAME=$(basename "$1")
    SNAPNAME="$LVBASENAME"_backup
    lvcreate --snapshot "$1" -n "$SNAPNAME" --size $LVSNAPSIZE -p r 1>/dev/null
}

_lvsnapdel(){
    SNAPNAME="$1"_backup
    lvremove -f "$SNAPNAME" 1>/dev/null
}

_lvbackup(){
    LVBASENAME=$(basename "$1")
    SNAPNAME="$1"_backup
    $DDCMD if="$SNAPNAME" $DDOPT | gzip -c > "$2"/"$LVBASENAME".img.gz
}

_vmdumpxml(){
    virsh dumpxml "$1" --migratable > "$2"
}

for VM in "$@"; do
    VMEXIST=$(_vmexist "$VM")
    if [ "$VMEXIST" -eq 1 ]; then
        echo "Start backup $VM"
        mkdir -p $BACKUPDIR/"$VM"/"$DATE"
        VMISRUN=$(_vmisrun "$VM")
        VMISSHUT=$(_vmisshut "$VM")

        if [ "$VMISRUN" -eq 1 ]; then
            echo "VM $VM is run"
            echo "Sync FS for $VM"
            _syncfs "$VM"
            echo "Save VM state for $VM"
            _vmsave "$VM" $BACKUPDIR/"$VM"/"$DATE"/"$VM".state
            for DISK in $(_vmgetdisks "$VM"); do
                echo "Create LV snapshot for $DISK"
                _lvsnap "$DISK"
            done
            echo "Restore VM state for $VM"
            _vmrestore $BACKUPDIR/"$VM"/"$DATE"/"$VM".state
            for DISK in $(_vmgetdisks "$VM"); do
                echo "Backup LV snapshot for $DISK"
                _lvbackup "$DISK" $BACKUPDIR/"$VM"/"$DATE"
                echo "Delete LV snapshot for $DISK"
                _lvsnapdel "$DISK"
            done
            echo "Save VM dump xml for $VM"
            _vmdumpxml "$VM" $BACKUPDIR/"$VM"/"$DATE"/"$VM".xml
        elif [ "$VMISSHUT" -eq 1 ]; then
            echo "VM $VM is shut"
            for DISK in $(_vmgetdisks "$VM"); do
                echo "Create LV snapshot for $DISK"
                _lvsnap "$DISK"
            done
            for DISK in $(_vmgetdisks "$VM"); do
                echo "Backup LV snapshot for $DISK"
                _lvbackup "$DISK" $BACKUPDIR/"$VM"/"$DATE"
                echo "Delete LV snapshot for $DISK"
                _lvsnapdel "$DISK"
            done
            echo "Save VM dump xml for $VM"
            _vmdumpxml "$VM" $BACKUPDIR/"$VM"/"$DATE"/"$VM".xml
        fi
    else
        echo "VM $VM not exist"
    fi
    echo
done
echo "Complete VM backup"
