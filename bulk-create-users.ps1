# Create AD Users in bulk

$UserCount = 100

$Surname = "TEST"
$Domain = "dummy.local"
$Path = "OU=Dummy Users,DC=thalesdemo,DC=local"

1..$UserCount | % {

    $id = '{0:d3}' -f $_
    $userName = "user$id"
    New-ADUser -Name $userName -Surname $Surname -GivenName $userName -EmailAddress "$username@$domain" -DisplayName $userName -Path $Path
}
