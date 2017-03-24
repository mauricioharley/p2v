# Script para alterar a configuracao IP (endereco, gateway, DNS e WINS) da VM1
$ErrorActionPreference = "Stop"

# Verificando se a VM1 ainda nao foi renomeada para o valor final
Write-Host; Write-Host -ForegroundColor Yellow "A VM1 (de negocios) ainda esta com hostname terminando em _NEW?"
Do
{
 Write-Host -ForegroundColor Yellow "Sim ou Nao?  Digite apenas S ou N e pressione ENTER: " -NoNewline
 $Opcao = Read-Host
 $Opcao = $Opcao.ToUpper()
}
While ($Opcao -ne "S" -and $Opcao -ne "N")

if ($Opcao -eq "N") {
    $PSExec = "C:\MIGRA\PSTOOLS\PsExec.exe"
    $Domain = “dominio.Cliente"
    $FileCSV = "C:\MIGRA\Planilha_Migracao.csv"

    $FileLocal = "C:\MIGRA\SecureLocal.txt"
    $UserLocal = "administrator"
    $PassLocal = Cat $FileLocal | ConvertTo-SecureString

    $FileCliente = "C:\MIGRA\SecureCliente.txt"
    $UserCliente = “dominio\user"
    $PassCliente = Cat $FileCliente | ConvertTo-SecureString

    # Obtencao das credenciais locais e do Cliente
    $CredLocal = New-Object -TypeName System.Management.Automation.PSCredential `
                -ArgumentList $UserLocal, $PassLocal
    $CredCliente = New-Object -TypeName System.Management.Automation.PSCredential `
                -ArgumentList $UserCliente, $PassCliente
    $SenhaLocal = $CredLocal.GetNetworkCredential().Password
    $SenhaCliente = $CredCliente.GetNetworkCredential().Password

    # Obtendo parametros para configuracao
    $VM1 = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM1)
    $Endereco = $((Import-Csv $FileCSV -Delimiter ";").IPVM1)
    $Mascara = $((Import-Csv $FileCSV -Delimiter ";").MASCARAVM1)
    $Gateway = $((Import-Csv $FileCSV -Delimiter ";").GATEWAYVM1)
    $DNS1 = $((Import-Csv $FileCSV -Delimiter ";").DNS1VM1); $WINS1 = $DNS1
    $DNS2 = $((Import-Csv $FileCSV -Delimiter ";").DNS2VM1); $WINS2 = $DNS2
    $DNS3 = $((Import-Csv $FileCSV -Delimiter ";").DNS3VM1); $WINS3 = $DNS3
    $DNS4 = $((Import-Csv $FileCSV -Delimiter ";").DNS4VM1); $WINS4 = $DNS4
    $DNS5 = $((Import-Csv $FileCSV -Delimiter ";").DNS5VM1); $WINS5 = $DNS5
    [String[]]$DNS = $DNS1,$DNS2,$DNS3,$DNS4,$DNS5

    # Limpando cache do resolver (DNS) do host antes de se conectar a VM1
    & ipconfig /flushdns

    Write-Host; Write-Host "Alterando configuracoes de DNS em $VM1..." -NoNewline
    Try {
        Invoke-Command -ComputerName $VM1 -Credential $CredCliente -ScriptBlock {
            $wmi = Get-WmiObject win32_networkadapterconfiguration -filter "ipenabled = 'true'"
            $wmi.SetDNSServerSearchOrder($using:DNS) | Out-Null
        }
    }
    Catch {
        Write-Host -ForegroundColor Red "Impossível alterar DNS de $VM1!"
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
        Exit
    }
    Finally {
        Write-Host "feito."
    }
    
    $NIC = "Local Area Connection"
    Write-Host; Write-Host "Alterando configuracoes de WINS em $VM1..." -NoNewline
    Try {
        Invoke-Command -ComputerName $VM1 -Credential $CredCliente -ScriptBlock {
            netsh interface ip add wins "$using:NIC" $using:WINS1 index=1
            netsh interface ip add wins "$using:NIC" $using:WINS2 index=2
            netsh interface ip add wins "$using:NIC" $using:WINS3 index=3
            netsh interface ip add wins "$using:NIC" $using:WINS4 index=4
            netsh interface ip add wins "$using:NIC" $using:WINS5 index=5
        }
    }
    Catch {
        Write-Host -ForegroundColor Red "Impossível alterar WINS de $VM1!"
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
        Exit
    }
    Finally {
        Write-Host "feito."
    }

    Write-Host; Write-Host -ForegroundColor Yellow "Alterando endereco IP de $VM1. A conexao com $VM1 sera perdida!" -NoNewline
    Try {
        Invoke-Command -ComputerName $VM1 -Credential $CredCliente -ScriptBlock {
            $wmi = Get-WmiObject win32_networkadapterconfiguration -filter "ipenabled = 'true'"
            $wmi.SetGateways($using:Gateway)
            $wmi.EnableStatic($using:Endereco, $using:Mascara) 
        }
    }
    Catch {
        Write-Host -ForegroundColor Red "Impossível alterar endereco IP de $VM1!"
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
        Exit
    }
    Finally {
        Write-Host "feito."
        Write-Host; Write-Host "Script finalizado."
    }
}
else {
    Write-Host
    Write-Host -ForegroundColor Red "VM1 ainda estah com nome terminando em _NEW!"
    Write-Host -ForegroundColor Red "Saindo do Script!"
}
