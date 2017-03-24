# Script para migrar a base de dados do DHCP
# Este script deve ser executado DENTRO DA VM correspondente.
#

$ErrorActionPreference = "Stop"
$Domain = "dominio..Cliente"
$FileCSV = "C:\MIGRA\Planilha_Migracao.csv"

$FileLocal = "C:\MIGRA\SecureLocal.txt"
$UserLocal = "administrator"
$PassLocal = Cat $FileLocal | ConvertTo-SecureString

$FileCliente = "C:\MIGRA\SecureCliente.txt"
$UserCliente = "dominio\usuario"
$PassCliente = Cat $FileCliente | ConvertTo-SecureString

# Obtencao das Credenciais locais e do Cliente
$CredLocal = New-Object -TypeName System.Management.Automation.PSCredential `
                -ArgumentList $UserLocal, $PassLocal
$CredCliente = New-Object -TypeName System.Management.Automation.PSCredential `
            -ArgumentList $UserCliente, $PassCliente

$ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL) + "." + $Domain
$VM2 = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM2) + "." + $Domain

Write-Host "Servidor Antigo: " $ServidorAntigo
Write-Host "Novo Servidor:   " $VM2

Write-Host; Write-Host "Exportando base de dados com o servico ainda no ar..."
Try {
    Invoke-Command -ComputerName $ServidorAntigo -Credential $CredCliente -ScriptBlock {
        netsh.exe dhcp server export C:\DHCPexport all
    }
}
Catch {
    Write-Host -ForegroundColor Red "Problemas ao exportar os dados do DHCP atual."
    Write-Host -ForegroundColor Red "Verifique se o servico DHCP esta iniciado no servidor atual."
    Write-Host -ForegroundColor Red "Saindo do Script de Migracao!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}

Write-Host; Write-Host "Encerrando o Servico DHCP no servidor atual da agencia..."
Try {
    Get-Service -ComputerName $ServidorAntigo -Name "DHCP Server" | Stop-Service -Force
}
Catch {
    Write-Host -ForegroundColor Red "Problemas ao parar servidor DHCP atual."
    Write-Host -ForegroundColor Red "Verifique diretamente no servidor. Saindo do Script de Migracao!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}

Write-Host; Write-Host "Copiando base de dados..."
Try {
    Invoke-Command -ComputerName $VM2 -Credential $CredCliente -ScriptBlock {
        copy \\$using:ServidorAntigo\c$\DHCPexport C:\migra\
        Stop-Service -Name "DHCP Server"
        if ($? -ne $true) {
            Write-Host -ForegroundColor Red "Problemas ao parar servico DHCP da VM."
            Write-Host -ForegroundColor Red "Verifique diretamente na VM. Saindo do Script de Migracao!"
            Exit
        }
    }
}
Catch {
    Write-Host -ForegroundColor Red "Falha ao copiar base de dados!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}

Write-Host; Write-Host "Iniciando servico DHCP no servidor novo..."
Try {
    Invoke-Command -ComputerName $VM2 -Credential $CredCliente -ScriptBlock {
        ren $env:windir\System32\dhcp\dhcp.mdb $env:windir\System32\dhcp\dhcpold.mdb
        Start-Service -Name "DHCP Server"
        if ($? -ne $true) {
            Write-Host -ForegroundColor Red "Problemas ao iniciar servico DHCP da VM."
            Write-Host -ForegroundColor Red "Verifique diretamente na VM. Saindo do Script de Migracao!"
            Exit
        }
    }
}
Catch {
    Write-Host -ForegroundColor Red "Falha ao iniciar servico DHCP no servidor novo!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}

Write-Host; Write-Host "Importando base de dados do DHCP..."
Try {
    Invoke-Command -ComputerName $VM2 -Credential $CredCliente -ScriptBlock {
        netsh dhcp server import c:\migra\dhcpexport
        Restart-Service -Name "DHCP Server"
        if ($? -ne $true) {
            Write-Host -ForegroundColor Red "Problemas ao reiniciar servico DHCP da VM."
            Write-Host -ForegroundColor Red "Verifique diretamente na VM. Saindo do Script de Migracao!"
            Exit
        }
    }
}
Catch {
    Write-Host -ForegroundColor Red "Falha ao importar base de dados do DHCP no servidor novo!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}

Write-Host; Write-Host "Autorizando DHCP no dominio (Active Directory)..."
Try {
    Invoke-Command -ComputerName $VM2 -Credential $CredCliente -ScriptBlock {
        Add-DhcpServerInDC
        if ($? -ne $true) {
            Write-Host -ForegroundColor Red "Problemas ao autorizar DHCP no Active Directory."
            Write-Host -ForegroundColor Red "Realize a autorizacao manualmente no servidor seguindo este fluxo:"
            Write-Host -ForegroundColor Red "A partir da console da $using:VM2, carregue o Server Manager.  Em seguida,"
            Write-Host -ForegroundColor Red "clique no item Tools e escolha 'DHCP'. Dentro desta ferramenta, localize"
            Write-Host -ForegroundColor Red "no lado esquerdo o nome do servidor ($using:VM2), clique com o botao direito"
            Write-Host -ForegroundColor Red "sobre ele e escolha 'Authorize'."
        }
    }
}
Catch {
    Write-Host -ForegroundColor Red "Falha ao autorizar servico DHCP no servidor novo!"
    Write-Host -ForegroundColor Red "Tente autoriza-lo manualmente no AD."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Exit
}

Write-Host; Write-Host "Alterando configuracao de DNS e WINS no escopo DHCP..."
$DNSWINS1 = $((Import-CSV $FileCSV -Delimiter ";").DNS1VM2)
$DNSWINS2 = $((Import-CSV $FileCSV -Delimiter ";").DNS2VM2)
$DNSWINS3 = $((Import-CSV $FileCSV -Delimiter ";").DNS3VM2)
$DNSWINS4 = $((Import-CSV $FileCSV -Delimiter ";").DNS4VM2)
$DNSWINS5 = $((Import-CSV $FileCSV -Delimiter ";").DNS5VM2)
Try {
    Invoke-Command -ComputerName $VM2 -Credential $CredCliente -ScriptBlock {
        $Escopo = Get-DhcpServerv4Scope
        $EscopoString = $Escopo.ScopeID.ToString()
        Set-DhcpServerv4OptionValue -ScopeID $EscopoString -DnsServer `
            $using:DNSWINS1,$using:DNSWINS2,$using:DNSWINS3,$using:DNSWINS4,$using:DNSWINS5 `
            -WinsServer $using:DNSWINS1,$using:DNSWINS2,$using:DNSWINS3,$using:DNSWINS4,$using:DNSWINS5 -Force
    }
}
Catch {
    Write-Host -ForegroundColor Red "Falha ao configurar DNS e WINS no escopo DHCP do $VM2!"
    Write-Host -ForegroundColor Red "Tente configurar tais parametros manualmente."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}

Write-Host; Write-Host "Desabilitando servico DHCP no servidor atual..."
Try {
    Get-Service -ComputerName $ServidorAntigo -Name "DHCP Server" | Set-Service -StartupType Disabled
}
Catch {
    Write-Host -ForegroundColor Red "Problemas ao alterar StartupType do DHCP no servidor atual."
    Write-Host -ForegroundColor Red "Verifique diretamente no servidor."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Write-Host
    Exit
}
Finally {
    Write-Host "Migracao concluida com sucesso!"
    Write-Host "Script finalizado"
    Write-Host
}
