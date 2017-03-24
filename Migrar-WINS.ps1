# Script para migrar as configuracoes do WINS
#
$ErrorActionPreference = "Stop"
$Domain = "dominio.Cliente"
$FileCSV = "C:\MIGRA\Planilha_Migracao.csv"

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

$ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL) + "." +$Domain
$ServidorNovo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM2) + "." +$Domain
$WINS1 = "ag001_ger01"
$WINS2 = "ag001_ger02"
$WINS3 = "ag001_ger03"
$WINS4 = "ag001_ger04"
$WINS5 = "ag001_ger05"

# Configurando primeiro parceiro
Try {
    Invoke-Command -ComputerName $ServidorNovo -Credential $CredCliente -ScriptBlock {
        netsh.exe wins server add partner server=$using:WINS1 type=1
    }
}
Catch {
    Write-Host -ForegroundColor Red "Problemas ao configurar servico WINS. Verifique log de sistema."
    Write-Host -ForegroundColor Red "Saindo do Script de Migracao..."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}
Finally {
    Write-Host; Write-Host "Primeiro replication partner" $WINS1 "configurado."
}

# Configurando segundo parceiro
Try {
    Invoke-Command -ComputerName $ServidorNovo -Credential $CredCliente -ScriptBlock {
        netsh.exe wins server add partner server=$using:WINS2 type=1
    }
}
Catch {
    Write-Host -ForegroundColor Red "Problemas ao configurar servico WINS. Verifique log de sistema."
    Write-Host -ForegroundColor Red "Saindo do Script de Migracao..."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}
Finally {
    Write-Host; Write-Host "Segundo replication partner" $WINS2 "configurado."
}

# Configurando terceiro parceiro
Try {
    Invoke-Command -ComputerName $ServidorNovo -Credential $CredCliente -ScriptBlock {
        netsh.exe wins server add partner server=$using:WINS3 type=1
    }
}
Catch {
    Write-Host -ForegroundColor Red "Problemas ao configurar servico WINS. Verifique log de sistema."
    Write-Host -ForegroundColor Red "Saindo do Script de Migracao..."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}
Finally {
    Write-Host; Write-Host "Terceiro replication partner" $WINS3 "configurado."
}

# Configurando quatro parceiro
Try {
    Invoke-Command -ComputerName $ServidorNovo -Credential $CredCliente -ScriptBlock {
        netsh.exe wins server add partner server=$using:WINS4 type=1
    }
}
Catch {
    Write-Host -ForegroundColor Red "Problemas ao configurar servico WINS. Verifique log de sistema."
    Write-Host -ForegroundColor Red "Saindo do Script de Migracao..."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}
Finally {
    Write-Host; Write-Host "Quarto replication partner" $WINS4 "configurado."
}

# Configurando quinto parceiro
Try {
    Invoke-Command -ComputerName $ServidorNovo -Credential $CredCliente -ScriptBlock {
        netsh.exe wins server add partner server=$using:WINS5 type=1
    }
}
Catch {
    Write-Host -ForegroundColor Red "Problemas ao configurar servico WINS. Verifique log de sistema."
    Write-Host -ForegroundColor Red "Saindo do Script de Migracao..."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}
Finally {
    Write-Host; Write-Host "Quinto replication partner" $WINS5 "configurado."
}
Write-Host "Script finalizado."
Write-Host
