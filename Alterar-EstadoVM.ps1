# Script para ativar ou desativar maquina virtual
param([parameter(Mandatory=$true)][int]$Computador,[parameter(Mandatory=$true)][int]$Acao)
$ErrorActionPreference = "Stop"

$FileCSV = "C:\MIGRA\Planilha_Migracao.csv"
$PrefixoServidor = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL).Substring(0,2)

if (($Computador -ge 1 -and $Computador -le 3) -and ($Acao -eq 0 -or $Acao -eq 1)) {
    $FileCSV = "C:\MIGRA\Planilha_Migracao.csv"
    $CodFilial = $((Import-Csv $FileCSV -Delimiter ";").CODIGO)
    $Maquinas = ($PrefixoServidor + $CodFilial + "_GER01"),("S3DCAG"+ $CodFilial),("S3LSHP" + $CodFilial)
    $VM = $Maquinas[$Computador-1]
    Write-Host "VM:" $VM
    if ($Acao -eq 0) {
        Write-Host "Desligando VM $VM..."
        Try {
            Stop-VM -Name $VM -Force | Out-Null
        }
        Catch {
            Write-Host -ForegroundColor Red "Impossivel desligar VM $VM!"
            Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
            Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
            Exit
        }
        Finally {
            Write-Host "VM Desligada."
        }
    }
    else {
        Write-Host "Iniciando VM $VM..."
        Try {
            Start-VM -Name $VM | Out-Null
        }
        Catch {
            Write-Host -ForegroundColor Red "Impossivel ligar VM $VM!"
            Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
            Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
            Exit
        }
        Finally {
            Do
            {
             Write-Host "Aguardando ativaco da VM $VM..."
             $Estado = Get-VMIntegrationService -VMName $VM -Name Heartbeat
             Sleep 5
            }
            while ($Estado.PrimaryStatusDescription -ne "OK")
            Write-Host "VM Ligada."
        }
    }
    Write-Host "Script finalizado."
    Write-Host
}
else {
    Write-Host "***"
    Write-Host "Erro de parametro!  Eh preciso especificar o parametro -Computador."
    Write-Host "Uso:"
    Write-Host "     .\AlterarEstado-VM.ps1 -Computador {1 | 2 | 3} -Acao {0 | 1}"
    Write-Host "     Valores para o parametro -Computador:"
    Write-Host "     1 = Maquina virtual 1"
    Write-Host "     2 = Maquina virtual 2"
    Write-Host "     3 = Maquina virtual 3"
    Write-Host "***"
    Write-Host "     Valores para o parametro -Acao:"
    Write-Host "     0 = Desligar maquina virtual"
    Write-Host "     1 = Ligar maquina virtual"
    Write-Host
}
