Param(
  [string]$FileName = $(throw "-FileName is required.")
 )


# read = read data | read attributes
$READ_PERMISSIONS = 0x0001 -bor 0x0080

# write = write data | append data | write attributes | write EA
$WRITE_PERMISSIONS = 0x0002 -bor 0x0004 -bor 0x0100 -bor  0x0010

# execute = read data | file execute
$EXECUTE_PERMISSIONS = 0x0001 -bor 0x0020


function GetFilePermissions($path) {
    $objPath = "Win32_LogicalFileSecuritySetting='$path'"
    $output = Invoke-WmiMethod -Namespace root/cimv2 -Path $objPath -Name GetSecurityDescriptor

    if ($output.ReturnValue -ne 0) {
        $retVal = $output.ReturnValue
        echo "GetSecurityDescriptor invocation failed with code: $retVal"
        exit $output.ReturnValue
    }

    $fileSD = $output.Descriptor
    $fileOwnerGroup = $fileSD.Group
    $fileOwner = $fileSD.Owner

    $userMask = 0
    $groupMask = 0
    $otherMask = 0

    foreach ($ace in $fileSD.DACL) {
        $mask = 0
        if ($ace.AceType -ne 0) {
            # not an Allow ACE, skip.
            continue
        }

        # convert mask.
        if ( ($ace.AccessMask -band $READ_PERMISSIONS) -eq $READ_PERMISSIONS ) {
            $mask = $mask -bor 4
        }
        if ( ($ace.AccessMask -band $WRITE_PERMISSIONS) -eq $WRITE_PERMISSIONS ) {
            $mask = $mask -bor 2
        }
        if ( ($ace.AccessMask -band $EXECUTE_PERMISSIONS) -eq $EXECUTE_PERMISSIONS ) {
            $mask = $mask -bor 1
        }

        # detect mask type.
        if ($ace.Trustee.Equals($fileOwner)) {
            $userMask = $mask
        } elseif ($ace.Trustee.Equals($fileOwnerGroup)) {
            $groupMask = $mask
        } elseif ($ace.Trustee.Name.ToLower() -eq "users") {
            $otherMask = $mask
        }
    }

    return "$userMask$groupMask$otherMask"
}

$mask = GetFilePermissions($FileName)

# print the permission mask Linux-style.
echo "0$mask"
