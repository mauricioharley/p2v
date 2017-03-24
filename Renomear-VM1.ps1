# Script para renomear a VM1 removendo o sufixo "_NEW"
$ErrorActionPreference = "Stop"

# Verificando se a VM1 ainda nao foi renomeada para o valor final
Write-Host; Write-Host -ForegroundColor Yellow "Confirma que a VM1 (de negocios) ainda esta com hostname terminando em _NEW?"
Do
{
 Write-Host -ForegroundColor Yellow "Sim ou Nao?  Digite apenas S ou N e pressione ENTER: " -NoNewline
 $Opcao = Read-Host
 $Opcao = $Opcao.ToUpper()
}
While ($Opcao -ne "S" -and $Opcao -ne "N")

if ($Opcao -eq "S") {
    $PSExec = "C:\MIGRA\PSTOOLS\PsExec.exe"
    $Domain = "dominio.Cliente"
    $FileCSV = "C:\MIGRA\Planilha_Migracao.csv"
    $NovoNome = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM1)
    $NomeAntigo = $NovoNome + "_NEW"
    $Computador = $NomeAntigo

    $FileLocal = "C:\MIGRA\SecureLocal.txt"
    $UserLocal = "administrator"
    $PassLocal = Cat $FileLocal | ConvertTo-SecureString

    $FileCliente = "C:\MIGRA\SecureCliente.txt"
    $UserCliente = "dominio\usuario"
    $PassCliente = Cat $FileCliente | ConvertTo-SecureString

    # Obtencao das credenciais locais e do Cliente
    $CredLocal = New-Object -TypeName System.Management.Automation.PSCredential `
                -ArgumentList $UserLocal, $PassLocal
    $CredCliente = New-Object -TypeName System.Management.Automation.PSCredential `
                -ArgumentList $UserCliente, $PassCliente
    $SenhaLocal = $CredLocal.GetNetworkCredential().Password
    $SenhaCliente = $CredCliente.GetNetworkCredential().Password

    Write-Host; Write-Host "Renomeando" $NomeAntigo "para"$NovoNome"..." -NoNewline
    Try {
        & $PsExec \\$Computador -u $UserLocal -p $SenhaLocal "c:\Program Files\Support Tools\netdom.exe" renamecomputer $NomeAntigo /newname:$NovoNome /userd:$UserCliente /passwordd:$SenhaCliente /force /reboot:10
    }
    Catch {
        Write-Host -ForegroundColor Red "Impossível renomear computador!"
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
        Exit
    }
    Finally {
        Write-Host "feito."
        Write-Host; Write-Host "Script finalizado."; Write-Host
    }
}
