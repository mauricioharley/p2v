# Script para migrar filas de impressoras. Adicionalmente, como este eh o ultimo script
# da fase de migracao, eh necessario ainda configurar os servicos do SQL Server para serem
# ativados automaticamente.
#
$ErrorActionPreference = "Stop"
$FileCSV = "C:\MIGRA\Planilha_Migracao.csv"
$ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL) + "_OLD"
$Destino = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM2)

$FilePRT = "C:\MIGRA\backup.impressoras"
$FileCliente = "C:\MIGRA\SecureCliente.txt"
$PrintBRM = "C:\WINDOWS\SYSTEM32\SPOOL\TOOLS\printbrm.exe"
$PSExec = "C:\MIGRA\PSTOOLS\PsExec.exe"

$UserCliente = "dominio\usuario"
$PassCliente = Cat $FileCliente | ConvertTo-SecureString
$CredCliente = New-Object -TypeName System.Management.Automation.PSCredential `
            -ArgumentList $UserCliente, $PassCliente
$SenhaCliente = $CredCliente.GetNetworkCredential().Password

Write-Host "Checando se arquivo de backup ja existe..."
Try {
    Invoke-Command -ComputerName $Destino -Credential $CredCliente -ScriptBlock {
        If (Test-Path $using:FilePRT) {
            Write-Host "Arquivo ja existe.  Apagando..."
            Remove-Item $using:FilePRT -Force
        }
        else {
            Write-Host "Arquivo nao existe.  Procedendo com migracao..."
        }
    }
}
Catch {
    Write-Host -ForegroundColor Red "Falha ao executar comando de verificacao do arquivo de backup!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}

Write-Host "Gerando backup das impressoras..."
Invoke-Command -ComputerName $Destino -Credential $CredCliente -ScriptBlock {
    & $using:PrintBRM -B -S \\$using:ServidorAntigo -F $using:FilePRT 
}
if ($? -eq $true) {
    Write-Host
    Write-Host -ForegroundColor Yellow "Verifique se o backup acima realmente foi concluido com sucesso."
    Write-Host -ForegroundColor Yellow "Caso nao tenha sido concluido, faca o seguinte:"
    Write-Host -ForegroundColor Yellow "1. Abra a console da VM $Destino;"
    Write-Host -ForegroundColor Yellow "2. De dentro da console, abra uma janela do PowerShell como ADMINISTRATOR;"
    Write-Host -ForegroundColor Yellow "3. Digite o comando 'cd c:\windows\system32\spool\tools';"
    Write-Host -ForegroundColor Yellow "4. Digite o comando '.\printbrm.exe -B -S \\$ServidorAntigo -F $FilePRT';"
    Write-Host -ForegroundColor Yellow "5. Observe a finalizacao do comando e a geracao do arquivo de backup."
    Write-Host
    Write-Host -ForegroundColor Yellow "Quando estiver pronto, pressione ENTER aqui para continuar."
    Pause
    Write-Host "Backup concluido com sucesso.  Verificar arquivo"
    Write-Host "correspondente $FilePRT na VM $Destino."
    Write-Host "Importando impressoras..."
    
    Invoke-Command -ComputerName $Destino -Credential $CredCliente -ScriptBlock {
        & $using:PrintBRM -R -F $using:FilePRT
    }
    if ($? -eq $true) {
        Write-Host
        Write-Host "Impressoras importadas e filas criadas."
        Write-Host "Verificar na VM $Destino se todas as filas estao"
        Write-Host "de acordo com o esperado."
    }
    else {
        Write-Host -ForegroundColor Red "Ocorreram erros na importacao.  Verificar mensagens"
        Write-Host -ForegroundColor Red "informadas pelo comando PRINTBRM logo acima."
    }
}
else {
    Write-Host
    Write-Host -ForegroundColor Red "Ocorreram erros no backup.  Verificar mensagens"
    Write-Host -ForegroundColor Red "informadas pelo comando PRINTBRM logo acima."
}
Write-Host
