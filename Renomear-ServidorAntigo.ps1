# Script para renomear servidor antigo colocando um sufixo _OLD
$ErrorActionPreference = "Stop"
$PSExec = "C:\MIGRA\PSTOOLS\PsExec.exe"
$Domain = "dominio.Cliente"
$FileCSV = "C:\MIGRA\Planilha_Migracao.csv"
$ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL)
$NovoNome = $ServidorAntigo + "_OLD"
$Computador = $ServidorAntigo + "." + $Domain
$IPManobra = $((Import-Csv $FileCSV -Delimiter ";").IPMANOBRA)
$TempoChecagem = 15 # Tempo que o script aguardara antes de fazer nova verificacao de conexao ao servidor antigo

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

Write-Host; Write-Host "Renomeando" $ServidorAntigo "para"$NovoNome"..." -NoNewline
Try {
    & $PsExec \\$Computador -accepteula -u $UserCliente -p $SenhaCliente "c:\Program Files\Support Tools\netdom.exe" renamecomputer $ServidorAntigo /newname:$NovoNome /userd:$UserCliente /passwordd:$SenhaCliente /force /reboot:10
}
Catch {
    Write-Host -ForegroundColor Red "Falha ao executar comando para renomear $ServidorAntigo!"
    Write-Host -ForegroundColor Red "Execute novamente o script ou renomeie o servidor manualmente, inserindo o sufixo _OLD."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}

# Limpando o cache do DNS
& ipconfig /flushdns

Write-Host "Aguardando que o servidor $NovoNome retorne.  Isto pode demorar varios minutos..." -NoNewline
$Sair = $false
$Caminho = "\\"+$NovoNome+"\C$"
Do {
    $Sair = Test-Path ($Caminho)
    Sleep $TempoChecagem
} While (!$Sair)
Write-Host "feito."

Write-Host "Alterando endereco IP de $NovoNome para o endereco de manobra $IPManobra. A conexao podera ser perdida..." 
$Mascara = $((Import-Csv $FileCSV -Delimiter ";").MASCARAVM1)
Try {
    Invoke-Command -ComputerName $NovoNome -Credential $CredCliente -ScriptBlock {
        $wmi = Get-WmiObject win32_networkadapterconfiguration -filter "ipenabled = 'true'"
        $wmi.EnableStatic($using:IPManobra, $using:Mascara) | Out-Null
        ipconfig /registerdns
    }
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel alterar configuracao IP em $NovoNome!"
    Write-Host -ForegroundColor Red "Conecte-se manualmente no servidor e altere para o endereco $IPManobra."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}
Finally {
    Write-Host; Write-Host "Script finalizado."; Write-Host
}
