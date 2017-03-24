# Script para promover servidor a Domain Controller
#
$ErrorActionPreference = "Stop"

# Area de Definicao de Variaveis
$Domain = "dominio.Cliente"

$FileLocal = "C:\MIGRA\SecureLocal.txt"
$UserLocal = "administrator"
$PassLocal = Cat $FileLocal | ConvertTo-SecureString

$FileCliente = "C:\MIGRA\SecureCliente.txt"
$UserCliente = "dominio\usuario"
$PassCliente = Cat $FileCliente | ConvertTo-SecureString

# Obtencao da Credencial Local
$CredLocal = New-Object -TypeName System.Management.Automation.PSCredential `
           -ArgumentList $UserLocal, $PassLocal
# Obtencao da Credencial do Cliente
$CredCliente = New-Object -TypeName System.Management.Automation.PSCredential `
           -ArgumentList $UserCliente, $PassCliente

$FileCSV = "C:\MIGRA\Planilha_Migracao.csv"
$FolderIFMAD = "C:\MIGRA\IFMCliente"

# Obtencao dos parametros da linha do arquivo CSV correspondente a esta agencia 
$Hostname = $((Import-Csv $FileCSV -Delimiter ";").HostnameVM2)
$EnderecoIP = $((Import-Csv $FileCSV -Delimiter ";").IPVM2)
$ReplicationDC = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL) + "." + $Domain
$Computer = $Hostname
$CodAgencia = $((Import-Csv $FileCSV -Delimiter ";").CODIGO)

# Promovendo a DC e GC
Try {
    Invoke-Command -ComputerName $Computer -ScriptBlock {
        Import-Module ADDSDeployment;
        Install-ADDSDomainController `
        -NoGlobalCatalog:$false `
        -CriticalReplicationOnly:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -DomainName $using:Domain `
        -InstallationMediaPath $using:FolderIFMAD `
        -InstallDns:$true `
        -LogPath "C:\Windows\NTDS" `
        -NoRebootOnCompletion:$true `
        -SysvolPath "C:\Windows\SYSVOL" `
        -ReplicationSourceDC $ReplicationDC `
        -Force:$true `
        -Credential $using:CredCliente `
        -Confirm:$false `
        -SafeModeAdministratorPassword $using:PassLocal
    }
}
Catch {
    Write-Host -ForegroundColor Red "Falha ao executar comando para promover domain controller!"
    Write-Host -ForegroundColor Red "Tente novamente ou promova manualmente."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}
<#Write-Host
Write-Host -ForegroundColor Yellow "Verifique se o computador foi promovido a Domain Controller e retorne"
Write-Host -ForegroundColor Yellow "a este script. Caso tenha sido, pressione <ENTER> aqui para reinicia-lo."
Write-Host -ForegroundColor Yellow "Caso nao, pressione CTRL-C agora neste script!"
$Nada = Read-Host#>

# Inserindo chave especifica no Domain Controller
Write-Host "Inserindo chave especifica no registro do Domain Controller $Computer..."
Try {
    Invoke-Command -ComputerName $Computer -ScriptBlock {
        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\services\NTDS\Parameters" -Name "Strict Replication Consistency" -Value 1 -PropertyType "DWord" -Force
    }
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel inserir chave especifica no AD!"
    Write-Host -ForegroundColor Red "Insira manualmente a chave:"
    Write-Host -ForegroundColor Red "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NTDS\Parameters"
    Write-Host -ForegroundColor Red "O nome eh 'Strict Replication Consistency', o valor eh 1 e o tipo eh DWORD."
    Write-Host
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Write-Host
}

# Reiniciando Domain Controller
Write-Host -ForegroundColor Yellow "Reiniciando computador apos conclusao..."
Try {
    Restart-Computer $Computer -Wait -For PowerShell -Confirm:$false -Force
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel reiniciar o computador $Computer!  Tente faze-lo manualmente"
    Write-Host -ForegroundColor Red "Apos reinicia-lo e fazer o logon em $Computer, volte aqui e pressione ENTER para continuar"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Write-Host
    Pause
}

Write-Host; Write-Host "Aguardando para que o Active Directory seja carregado em $Computer..."
For ($i = 1; $i -le 240; $i++) {
    $Percentual = $i/240*100
    $Percentual = "{0:N0}" -f $Percentual
    Write-Progress "Aguardando que o Active Directory seja carregado em $Computer..." -Status "$Percentual% concluidos" -PercentComplete ($i/240*100)
    Sleep 1
}

# Configurando parceiros de replicacao do AD (sentido agencia->DOMGV)
$Site = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL).Substring(0,$((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL).IndexOf("_"))
Write-Host; Write-Host "Configurando parceiros de replicacao do AD (sentido agencia->DOMGV)..."
Try {
    Invoke-Command -ComputerName $Computer -Credential $CredCliente -ScriptBlock {
        New-ADObject -Name 'AG001_GER01' -Type 'nTDSConnection' -OtherAttributes @{options="0";fromServer="CN=NTDS Settings,CN=AG001_GER01,CN=Servers,CN=DIRGE,CN=Sites,CN=Configuration,DC=intra,DC=Cliente";enabledConnection="TRUE"} -Path "CN=NTDS Settings,CN=$using:Hostname,CN=Servers,CN=$using:Site,CN=Sites,CN=Configuration,DC=intra,DC=Cliente"
        New-ADObject -Name 'AG001_GER02' -Type 'nTDSConnection' -OtherAttributes @{options="0";fromServer="CN=NTDS Settings,CN=AG001_GER02,CN=Servers,CN=DIRGE,CN=Sites,CN=Configuration,DC=intra,DC=Cliente";enabledConnection="TRUE"} -Path "CN=NTDS Settings,CN=$using:Hostname,CN=Servers,CN=$using:Site,CN=Sites,CN=Configuration,DC=intra,DC=Cliente"
        New-ADObject -Name 'AG001_GER03' -Type 'nTDSConnection' -OtherAttributes @{options="0";fromServer="CN=NTDS Settings,CN=AG001_GER03,CN=Servers,CN=DIRGE,CN=Sites,CN=Configuration,DC=intra,DC=Cliente";enabledConnection="TRUE"} -Path "CN=NTDS Settings,CN=$using:Hostname,CN=Servers,CN=$using:Site,CN=Sites,CN=Configuration,DC=intra,DC=Cliente"
        New-ADObject -Name 'AG001_GER04' -Type 'nTDSConnection' -OtherAttributes @{options="0";fromServer="CN=NTDS Settings,CN=AG001_GER04,CN=Servers,CN=DIRGE,CN=Sites,CN=Configuration,DC=intra,DC=Cliente";enabledConnection="TRUE"} -Path "CN=NTDS Settings,CN=$using:Hostname,CN=Servers,CN=$using:Site,CN=Sites,CN=Configuration,DC=intra,DC=Cliente"
        New-ADObject -Name 'AG001_GER05' -Type 'nTDSConnection' -OtherAttributes @{options="0";fromServer="CN=NTDS Settings,CN=AG001_GER05,CN=Servers,CN=DIRGE,CN=Sites,CN=Configuration,DC=intra,DC=Cliente";enabledConnection="TRUE"} -Path "CN=NTDS Settings,CN=$using:Hostname,CN=Servers,CN=$using:Site,CN=Sites,CN=Configuration,DC=intra,DC=Cliente"
    }
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel configurar parceiros de replicao no AD sentido agencia->DOMGV!"
    Write-Host -ForegroundColor Red "Realize esta configuracao manualmente."
    Write-Host
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}

# Configurando parceiros de replicacao do AD (sentido DOMGV->agencia)
Write-Host; Write-Host "Configurando parceiros de replicacao do AD (sentido DOMGV->agencia)..."
Try {
    Invoke-Command -ComputerName $Computer -Credential $CredCliente -ScriptBlock {
        New-ADObject -Name "$using:Hostname" -Type 'nTDSConnection' -OtherAttributes @{options="0";fromServer="CN=NTDS Settings,CN=$using:Hostname,CN=Servers,CN=$using:Site,CN=Sites,CN=Configuration,DC=intra,DC=Cliente";enabledConnection="TRUE"} -Path 'CN=NTDS Settings,CN=AG001_GER01,CN=Servers,CN=DIRGE,CN=Sites,CN=Configuration,DC=intra,DC=Cliente'
        New-ADObject -Name "$using:Hostname" -Type 'nTDSConnection' -OtherAttributes @{options="0";fromServer="CN=NTDS Settings,CN=$using:Hostname,CN=Servers,CN=$using:Site,CN=Sites,CN=Configuration,DC=intra,DC=Cliente";enabledConnection="TRUE"} -Path 'CN=NTDS Settings,CN=AG001_GER02,CN=Servers,CN=DIRGE,CN=Sites,CN=Configuration,DC=intra,DC=Cliente'
        New-ADObject -Name "$using:Hostname" -Type 'nTDSConnection' -OtherAttributes @{options="0";fromServer="CN=NTDS Settings,CN=$using:Hostname,CN=Servers,CN=$using:Site,CN=Sites,CN=Configuration,DC=intra,DC=Cliente";enabledConnection="TRUE"} -Path 'CN=NTDS Settings,CN=AG001_GER03,CN=Servers,CN=DIRGE,CN=Sites,CN=Configuration,DC=intra,DC=Cliente'
        New-ADObject -Name "$using:Hostname" -Type 'nTDSConnection' -OtherAttributes @{options="0";fromServer="CN=NTDS Settings,CN=$using:Hostname,CN=Servers,CN=$using:Site,CN=Sites,CN=Configuration,DC=intra,DC=Cliente";enabledConnection="TRUE"} -Path 'CN=NTDS Settings,CN=AG001_GER04,CN=Servers,CN=DIRGE,CN=Sites,CN=Configuration,DC=intra,DC=Cliente'
        New-ADObject -Name "$using:Hostname" -Type 'nTDSConnection' -OtherAttributes @{options="0";fromServer="CN=NTDS Settings,CN=$using:Hostname,CN=Servers,CN=$using:Site,CN=Sites,CN=Configuration,DC=intra,DC=Cliente";enabledConnection="TRUE"} -Path 'CN=NTDS Settings,CN=AG001_GER05,CN=Servers,CN=DIRGE,CN=Sites,CN=Configuration,DC=intra,DC=Cliente'
    }
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel configurar parceiros de replicao no AD sentido DOMGV->agencia!"
    Write-Host -ForegroundColor Red "Realize esta configuracao manualmente."
    Write-Host
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}

# Alterando configuracao de DNS da VM2 e do host para apontar para a VM2
$DNS1 = $((Import-Csv $FileCSV -Delimiter ";").DNS1HOST)
$DNS2 = $((Import-Csv $FileCSV -Delimiter ";").DNS2HOST)
$DNS3 = $((Import-Csv $FileCSV -Delimiter ";").DNS3HOST)
$DNS4 = $((Import-Csv $FileCSV -Delimiter ";").DNS4HOST)
$DNS5 = $((Import-Csv $FileCSV -Delimiter ";").DNS5HOST)
[String[]]$DNS = $DNS1,$DNS2,$DNS3,$DNS4,$DNS5

Write-Host; Write-Host "Alterando configuracoes de DNS em $Computer..." -NoNewline
Try {
    Invoke-Command -ComputerName $Computer -Credential $CredCliente -ScriptBlock {
        $wmi = Get-WmiObject win32_networkadapterconfiguration -filter "ipenabled = 'true'"
        $wmi.SetDNSServerSearchOrder($using:DNS) | Out-Null
    }
}
Catch {
    Write-Host -ForegroundColor Red "Impossível alterar DNS de $Computer!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}

Write-Host; Write-Host "Alterando configuracoes de DNS no host..." -NoNewline
Try {
    $wmi = Get-WmiObject win32_networkadapterconfiguration -filter "ipenabled = 'true'"
    $wmi.SetDNSServerSearchOrder($DNS) | Out-Null
}
Catch {
    Write-Host -ForegroundColor Red "Impossível alterar DNS do host!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}

Write-Host; Write-Host "Script finalizado."; Write-Host
