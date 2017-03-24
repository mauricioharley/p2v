# Script para gerar as credenciais locais e do dominio e grava-las em arquivos texto para uso posterior
$ErrorActionPreference = "Stop"
$FileLocal = "C:\MIGRA\SecureLocal.txt"
$FileCliente = "C:\MIGRA\SecureCliente.txt"

Write-Host -ForegroundColor Yellow "ATENCAO: Execute este script apenas no HOST!"
Write-Host; Write-Host "Digite a senha correspondente a credencial local (usuario administrator): " -NoNewline
$SenhaLocal = Read-Host -AsSecureString | ConvertFrom-SecureString
Try {
    Echo $SenhaLocal > $FileLocal
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel criar arquivo de credenciais locais!  Execute o script novamente"
    Write-Host -ForegroundColor Red "ou tente gerar a senha manualmente"
    Write-Host -ForegroundColor Red "Mensagem de Erro:  " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item:  " $_.Exception.ItemName
}

Write-Host; Write-Host "Digite a senha correspondente a credencial do dominio (usuario): " -NoNewline
$SenhaCliente = Read-Host -AsSecureString | ConvertFrom-SecureString
Try {
    Echo $SenhaCliente > $FileCliente
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel criar arquivo de credenciais do dominio!  Execute o script novamente"
    Write-Host -ForegroundColor Red "ou tente gerar a senha manualmente"
    Write-Host -ForegroundColor Red "Mensagem de Erro:  " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item:  " $_.Exception.ItemName
}

Write-Host; Write-Host "Script finalizado."; Write-Host
