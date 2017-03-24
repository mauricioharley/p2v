# Script para migrar servico de FTP
# Maquina de destino:  VM1

$ErrorActionPreference = "Stop"
$FileCSV = "C:\MIGRA\Planilha_Migracao.csv"
$CodAgencia = $((Import-Csv $FileCSV -Delimiter ";").CODIGO)
$ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL) + "_OLD"

$Destino = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM1)
$PastaFTP = "C:\migra\ftp"
$ArquivoFTP = $PastaFTP+"\DefaultFTPSite.xml"
$OrigemFTP = "\\"+$ServidorAntigo+"\c$\migra\ftp\DefaultFTPSite.xml"
$DestinoFTP = "\\"+$Destino+"\c$\migra\ftp\DefaultFTPSite.xml"

$FileLocal = "C:\MIGRA\SecureLocal.txt"
$UserLocal = "administrator"
$PassLocal = Cat $FileLocal | ConvertTo-SecureString

$FileCliente = "C:\MIGRA\SecureCliente.txt"
$UserCliente = "dominio\usuario"
$PassCliente = Cat $FileCliente | ConvertTo-SecureString
#
# Obtencao das Credenciais locais e do Cliente
$CredLocal = New-Object -TypeName System.Management.Automation.PSCredential `
                -ArgumentList $UserLocal, $PassLocal
$CredCliente = New-Object -TypeName System.Management.Automation.PSCredential `
            -ArgumentList $UserCliente, $PassCliente

# Limpando cache do DNS
& ipconfig /flushdns

# Processo de exportacao na maquina de origem ($ServidorAntigo)
Try {
    Invoke-Command -ComputerName $ServidorAntigo -Credential $CredCliente -ScriptBlock {
        If (-not (Test-Path $using:PastaFTP)) {
            mkdir $using:PastaFTP
        }
        elseif (Test-Path $using:ArquivoFTP) {
            Remove-Item $using:ArquivoFTP
        }
        cmd.exe /c cscript %WINDIR%\system32\iiscnfg.vbs /export /f $using:ArquivoFTP /sp "/LM/MSFTPSVC/1" /inherited /children
        if (Test-Path $using:ArquivoFTP) {
            Write-Host; Write-Host "Arquivo gerado com sucesso."
        }
        else {
            Write-Host
            Write-Host -ForegroundColor Red "Erro ao gerar arquivo de migracao do FTP!"
            Write-Host -ForegroundColor Red "Verifique diretamente no servidor antigo:" $using:ServidorAntigo
            Write-Host
            Exit
        }
    }
}
Catch {
    Write-Host -ForegroundColor Red "Falha ao executar comando de geracao de arquivo de migracao!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}

# Copia do arquivo de exportacao da origem para o destino
Try {
    Invoke-Command -ComputerName $Destino -Credential $CredCliente -ScriptBlock {
        if (-not (Test-Path $using:PastaFTP)) {
            mkdir $using:PastaFTP
        }
    }
    Copy-Item $OrigemFTP $DestinoFTP
}
Catch {
    Write-Host -ForegroundColor Red "Falha ao criar diretorio de migracao ou ao copiar arquivo do FTP!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}

# Processo de importacao na maquina de destino ($Destino)
Try {
    Invoke-Command -ComputerName $Destino -Credential $CredCliente -ScriptBlock {
        cmd.exe /c cscript %WINDIR%\system32\iiscnfg.vbs /import /sp "/LM/MSFTPSVC/1" /dp "/LM/MSFTPSVC/1" /f $using:ArquivoFTP /inherited /children /merge
        if ($? -ne $true) {
            Write-Host
            Write-Host -ForegroundColor Red "Erro ao importar arquivo de migracao do FTP!"
            Write-Host -ForegroundColor Red "Verifique diretamente no servidor destino:" $using:Destino
            Write-Host
        }
        else {
            Write-Host; Write-Host "Migracao do FTP realizada com sucesso."; Write-Host
        }
    }
}
Catch {
    Write-Host -ForegroundColor Red "Falha ao executar comando de importacao do FTP!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}
