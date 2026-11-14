param(
  [Parameter(Mandatory = $true)]
  [string]$Path
)

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $Path))
if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
  throw "$Path is not a valid PE executable (missing MZ header)."
}
$peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
if ($bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45) {
  throw "$Path has invalid PE signature."
}
$machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
$arch = switch ($machine) {
  0xAA64 { "ARM64" }
  0x8664 { "x64" }
  0x014C { "x86" }
  default { ("UNKNOWN(0x{0:X4})" -f $machine) }
}
[PSCustomObject]@{
  File    = $Path
  Machine = ("0x{0:X4}" -f $machine)
  Arch    = $arch
}
