# Script para despromover o Domain Controller atual da filial
#
$ErrorActionPreference = "Stop"

# Area de Definicao de Variaveis
$Domain = ".dominio.Cliente"

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

# Obtencao dos parametros da linha do arquivo CSV correspondente a esta agencia 
$ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HostnameATUAL) + $Domain
$EnderecoIP = $((Import-Csv $FileCSV -Delimiter ";").IPVM1)
$DNS1 = $((Import-Csv $FileCSV -Delimiter ";").IPVM2)
$DNS2 = "130.1.1.1"
[String[]]$DNS = $DNS1,$DNS2

# Alterando configuracao de DNS do servidor antigo
Write-Host; Write-Host "Alterando DNS do servidor antigo para apontar para a VM2..."
Try {
    Invoke-Command -ComputerName $ServidorAntigo -Credential $CredCliente -ScriptBlock {
        $wmi = Get-WmiObject win32_networkadapterconfiguration -filter "ipenabled = 'true'"
        $wmi.SetDNSServerSearchOrder($using:DNS) | Out-Null
    }
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel alterar configuracao DNS de $ServidorAntigo!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}

# Executando despromocao do servidor antigo
Write-Host; Write-Host "Copiando arquivo de desinstalacao automatica para o servidor..."
Try {
    copy C:\migra\dcpromodown.txt \\$ServidorAntigo\c$
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel copiar arquivo de respostas para $ServidorAntigo!"
    Write-Host "Verifique se por acaso o compartilhamento C$ foi removido de $ServidorAntigo e recrie-o."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}

Write-Host "Parando servico NETLOGON no servidor antigo..."
Try {
    Get-Service -ComputerName $ServidorAntigo -Name "Net Logon" | Stop-Service -Force
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel parar servico NETLOGON em $ServidorAntigo!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}
Finally {
    Write-Host -ForegroundColor Yellow "Pausa.  Verifique o NETLOGON do servidor antigo e pressione ENTER."
    Pause
}

Write-Host "Despromovendo DC..."
Try {
    Invoke-Command -ComputerName $ServidorAntigo -Credential $CredCliente -ScriptBlock {
        cmd.exe /c dcpromo.exe /adv /answer:c:\dcpromodown.txt
    }
}
Catch {
    Write-Host -ForegroundColor Red "Possivel erro ao despromover $ServidorAntigo!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}
Finally {
    Write-Host
    Write-Host -ForegroundColor Yellow "Verifique se o computador foi despromovido de Domain Controller e reiniciado."
    Write-Host
}

Write-Host -ForegroundColor Yellow "Confirme que $ServidorAntigo foi despromovido e ja voltou a funcionar."
Write-Host -ForegroundColor Yellow "De preferencia, tente acessar o $ServidorAntigo atraves de conexao RDP (TS)."
Write-Host -ForegroundColor Yellow "Em seguida, pressione ENTER para continuar o script e inserir grupos"
Write-Host -ForegroundColor Yellow "especificos em 'Administrators'."
Pause
# Adicionando grupos do DOMGV ao grupo local "administrators" no Servidor Antigo e na VM1
# (solicitacao do Cliente em 29/11/2014)
Do 
{
    Write-Host "Testando conexao com $ServidorAntigo..."
    $Conexao = (Test-Connection $ServidorAntigo -Quiet)
    Sleep 2
} While (-not $Conexao)

Write-Host; Write-Host "Adicionando grupos 'Domain Admins' e 'UDOMADMINS01' ao grupo 'Administrators' em $ServidorAntigo..."
Try {
    Invoke-Command -ComputerName $ServidorAntigo -Credential $CredCliente -ScriptBlock {
        & net localgroup administrators /add "DOMGV\Domain Admins"
        & net localgroup administrators /add "DOMGV\UDOMADMINS01"
    }
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel adicionar grupos em $ServidorAntigo! Execute tarefa manualmente!"
    Write-Host -ForegroundColor Red "Clique com o botao direito do mouse sobre o icone 'My Computer' e escolha 'Manage'."
    Write-Host -ForegroundColor Red "Em seguida, localize e EXPANDA o item 'Local Users and Groups'. Dentro dele, selecione 'Groups'."
    Write-Host -ForegroundColor Red "A partir dai, localize do lado direito o grupo 'Administrators'. Clique duas vezes sobre o mesmo."
    Write-Host -ForegroundColor Red "Clique no botao 'Add...' e digite DOMGV\Domain Admins;DOMGV\UDOMADMINS01."
    Write-Host -ForegroundColor Red "Finalize clicando 'OK' e 'OK' e encerrando a janela do 'Computer Manager'."
    Write-Host
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}
Finally {
    Write-Host; Write-Host "Script finalizado."; Write-Host
}
