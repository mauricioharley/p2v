<#
Script para parar e desativar servicos a serem migrados
a partir do servidor antigo.
Servicos considerados:
    IIS/FTP
    WINS
    MSSQLSERVER
    SQLSERVERAGENT
    UN2
    MngAgent
    SnaRpcService
    SnaBase
    SnaREM1
    SnaServr
    S580REPL
    SEAP-TRANSFER
    SrvRepEnvia
    SrvRepRecebe
    InterdominioRV
    TranslogSRV
    mapcrzd
    mapextr
    mplua
    octagrmip
    pr
#>
$ErrorActionPreference = "Stop"
$Domain = "dominio.Cliente"
$FileCSV = "C:\MIGRA\Planilha_Migracao.csv"

$ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL) + "." + $Domain

[String[]]$Servicos = "MSSQLSERVER","SQLSERVERAGENT","UN2","MngAgent","SnaRpcService", `
                      "SnaBase","SnaREM1","SnaServr","S580REPL","SEAP-TRANSFER", `
                      "SrvRepEnvia","SrvRepRecebe","InterdominioRV","TranslogSRV", `
                      "mapcrzd","mapextr","mplua","octagrmip","pr","WINS","W3SVC","MSFTPSVC"

Write-Host "Parando servicos..."
Write-Host

ForEach ($Serv in $Servicos) {
    Write-Host; Write-Host "Parando servico " $Serv "... " -NoNewline
    Try {
        Get-Service -ComputerName $ServidorAntigo -Name $Serv | Stop-Service -Force | Out-Null
    }
    Catch {
        Write-Host
        Write-Host -ForegroundColor Red "Problemas ao parar servico " $Serv "!  Verifique diretamente no servidor."
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.Item
    }
    Write-Host "feito."
    Write-Host "Desativando servico " $Serv "... " -NoNewline
    Try {
        Get-Service -ComputerName $ServidorAntigo -Name $Serv | Set-Service -StartupType Disabled | Out-Null
    }
    Catch {
        Write-Host
        Write-Host -ForegroundColor Red "Problemas ao desativar servico " $Serv "!  Verifique diretamente no servidor."
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.Item
    }
    Write-Host "feito."
}

Write-Host
Write-Host "Script finalizado."
Write-Host
