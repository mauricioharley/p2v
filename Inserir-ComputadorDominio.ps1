# Script para Inserir Computador no Domínio
# Aplica-se tanto as maquinas virtuais quanto ao host em si
#
param([parameter(Mandatory=$true)][int]$Computador)
$ErrorActionPreference = "Stop"

# Verificacao do parametro de entrada
if ($Computador -lt 0 -or $Computador -gt 3) {
    Write-Host "***"
    Write-Host "Erro de parametro!  Eh preciso especificar o parametro -Computador."
    Write-Host "Uso:"
    Write-Host "     .\Inserir-ComputadorDominio.ps1 -Computador {0 | 1 | 2 | 3}"
    Write-Host "     Valores para o parametro -Computador:"
    Write-Host "     0 = Host atual (computador onde o script estah rodando)"
    Write-Host "     1 = Maquina virtual 1"
    Write-Host "     2 = Maquina virtual 2"
    Write-Host "     3 = Maquina virtual 3"
    Write-Host
}
else {
    # Area de Definicao de Variaveis
    $Domain = "dominio.Cliente"
    $FileCSV = "C:\MIGRA\Planilha_Migracao.csv"
    $PSExec = "C:\MIGRA\PSTOOLS\PsExec.exe"

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
    $SenhaLocal = $CredLocal.GetNetworkCredential().Password
    $SenhaCliente = $CredCliente.GetNetworkCredential().Password
    
    # Obtencao dos parametros da linha do arquivo CSV correspondente a $Computador 
    Switch ($Computador)
        {
        0 { $EnderecoIP = $((Import-Csv $FileCSV -Delimiter ";").IP);    $Hostname = $((Import-Csv $FileCSV -Delimiter ";").Hostname) }
        1 { $EnderecoIP = $((Import-Csv $FileCSV -Delimiter ";").IPVM1); $Hostname = $((Import-Csv $FileCSV -Delimiter ";").HostnameVM1) }
        2 { $EnderecoIP = $((Import-Csv $FileCSV -Delimiter ";").IPVM2); $Hostname = $((Import-Csv $FileCSV -Delimiter ";").HostnameVM2) }
        3 { $EnderecoIP = $((Import-Csv $FileCSV -Delimiter ";").IPVM3); $Hostname = $((Import-Csv $FileCSV -Delimiter ";").HostnameVM3) }
        }
    $VM = $Hostname

    # Caso a VM1 ainda esteja com o nome terminando com "_NEW", o endereco IP eh dinamico
    if ($Computador -eq 1) {
        Write-Host; Write-Host -ForegroundColor Yellow "A VM1 (de negocios) ainda esta com hostname terminando em _NEW?"
        Do
        {
         Write-Host -ForegroundColor Yellow "Sim ou Nao?  Digite apenas S ou N e pressione ENTER: " -NoNewline
         $Opcao = Read-Host
         $Opcao = $Opcao.ToUpper()
        }
        While ($Opcao -ne "S" -and $Opcao -ne "N")
        if ($Opcao -eq "S") {
            $VM1 = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM1)
            $Nada = Get-VM $VM1 | Select-Object -ExpandProperty NetworkAdapters | Select-Object IPAddresses
            $EnderecoIP = $Nada.IPAddresses
            $Hostname = $Hostname + "_NEW"
        }
    }
    
    # Se o computador eh o host, verificar se este script estah rodando pela segunda vez para apenas 
    # adicionar os grupos do DOMGV no grupo local "Administrators" no host.
    if ($Computador -eq "0") {
        # Esta condicao em verdadeiro indica que o host ja foi adicionado ao dominio.
        if ((gwmi win32_computersystem).partofdomain -eq $true) {
            Write-Host;
            Write-Host "Host $Hostname ja foi inserido no dominio!"
            Write-Host "Adicionando grupos 'Domain Admins' e 'UDOMADMINS01' ao grupo 'Administrators' em $Hostname..."
            Try {
                & net localgroup administrators /add "DOMGV\Domain Admins"
                & net localgroup administrators /add "DOMGV\UDOMADMINS01"
            }
            Catch {
                Write-Host -ForegroundColor Red "Impossivel adicionar grupos em $Hostname! Execute tarefa manualmente!"
                Write-Host -ForegroundColor Red "Clique com o botao direito do mouse sobre o icone do Windows no canto inferior esquerdo e escolha 'Computer Manager'."
                Write-Host -ForegroundColor Red "Em seguida, localize e EXPANDA o item 'Local Users and Groups'. Dentro dele, selecione 'Groups'."
                Write-Host -ForegroundColor Red "A partir dai, localize do lado direito o grupo 'Administrators'. Clique duas vezes sobre o mesmo."
                Write-Host -ForegroundColor Red "Clique no botao 'Add...' e digite DOMGV\Domain Admins;DOMGV\UDOMADMINS01."
                Write-Host -ForegroundColor Red "Finalize clicando 'OK' e 'OK' e encerrando a janela do 'Computer Manager'."
                Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
                Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
            }
            Finally {
                Write-Host; Write-Host "Script finalizado."; Write-Host
                Exit # Se for o host, sair do script dando certo ou nao a inclusao dos grupos do DOMGV em "Administrators".
            }
        }
    }

    # Inserindo efetivamente o computador no dominio
    Try {
        Add-Computer -DomainName $Domain -ComputerName $EnderecoIP -LocalCredential $CredLocal -Credential $CredCliente -Restart -Force
    }
    Catch {
        Write-Host
        Write-Host -ForegroundColor Red "Computador $Hostname nao pode ser adicionado ou reiniciado."
        Write-Host -ForegroundColor Red "REINICIE-O manualmente AGORA e verifique se ele foi adicionado ao dominio!"
        Write-Host -ForegroundColor Red "Em seguida, pressione ENTER aqui para continuar o script."
        Write-Host -ForegroundColor Red "Caso tenha havido erro na insercao no dominio, sera preciso executar novamente o"
        Write-Host -ForegroundColor Red "script ou inserir manualmente.  Neste caso, pressione CTRL+C para encerrar agora o script."
        Write-Host; Write-Host
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
        Pause
    }

    # Aguardando carga do PowerShell para inserir os grupos administrativos do DOMGV
    if ($Computador -ne "0") {
        Do {
            $Ficar = $false
            Write-Host "Aguardando ativacao de $Hostname..."
            $Estado = Get-VMIntegrationService -VMName $VM -Name Heartbeat
            if ($Estado.PrimaryStatusDescription -ne "OK") {
                $Ficar = $true
                Write-Host -ForegroundColor Yellow "VM $Hostname parece estar desligada! Inicie-a manualmente via Hyper-V Manager"
                Write-Host -ForegroundColor Yellow "e pressione ENTER para fazer nova verificacao."
                Pause
            }
        } While ($Ficar)
        Write-Host; Write-Host -ForegroundColor Yellow "Verifique se $Hostname ja foi reiniciada e pressione ENTER para continuar!"
        Pause
        Write-Host "Adicionando grupos 'Domain Admins' e 'UDOMADMINS01' ao grupo 'Administrators' em $Hostname..."
        Try {
            Invoke-Command -ComputerName $Hostname -Credential $CredCliente -ScriptBlock {
                & net localgroup administrators /add "DOMGV\Domain Admins"
                & net localgroup administrators /add "DOMGV\UDOMADMINS01"
            }
        }
        Catch {
            Write-Host -ForegroundColor Red "Impossivel adicionar grupos em $VM! Execute tarefa manualmente!"
            Write-Host -ForegroundColor Red "Clique com o botao direito do mouse sobre o icone 'My Computer' e escolha 'Manage'."
            Write-Host -ForegroundColor Red "Em seguida, localize e EXPANDA o item 'Local Users and Groups'. Dentro dele, selecione 'Groups'."
            Write-Host -ForegroundColor Red "A partir dai, localize do lado direito o grupo 'Administrators'. Clique duas vezes sobre o mesmo."
            Write-Host -ForegroundColor Red "Clique no botao 'Add...' e digite DOMGV\Domain Admins;DOMGV\UDOMADMINS01."
            Write-Host -ForegroundColor Red "Finalize clicando 'OK' e 'OK' e encerrando a janela do 'Computer Manager'."
            Write-Host; Write-Host
            Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
            Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
        }

        # Se o computador a ser adicionado for a VM2, eh preciso ainda adicionar permissoes ao compartilhamento Content-Share
        if ($Computador -eq "2") {
            Write-Host "Adicionando grupos 'Domain Admins' e 'UDOMADMINS01' ao compartilhamento CONTENT em $VM..."
            Try {
                Invoke-Command -ComputerName $VM -Credential $CredCliente -ScriptBlock {
                    $Pasta = "E:\AppV\Content"
                    $ACL = Get-ACL $Pasta
                    $Regra = New-Object System.Security.AccessControl.FileSystemAccessRule("DOMGV\Domain Admins","Fullcontrol","ContainerInherit,ObjectInherit","None","Allow")
                    $ACL.AddAccessRule($Regra)
                    $Regra = New-Object System.Security.AccessControl.FileSystemAccessRule("DOMGV\UDOMAdmins01","Fullcontrol","ContainerInherit,ObjectInherit","None","Allow")
                    $ACL.AddAccessRule($Regra)
                    Set-Acl $Pasta $ACL | Out-Null
                }
            }
            Catch {
                Write-Host -ForegroundColor Red "Impossivel adicionar grupos ao compartilhamento CONTENT em $VM! Execute tarefa manualmente!"
                Write-Host -ForegroundColor Red "Abra o 'Meu Computador' e entre no drive E:. Em seguida, abra a pasta 'AppV' e dentro dela,"
                Write-Host -ForegroundColor Red "selecione a pasta 'Content'. Clique com o botao direito do mouse sobre a mesma e escolha 'Properties'."
                Write-Host -ForegroundColor Red "Em seguida, va para a guia 'Security', clique no botao 'Edit...' e depois no botao 'Add...'."
                Write-Host -ForegroundColor Red "Na caixa de texto (parte de baixo da janela), digite DOMGV\Domain Admins;DOMGV\UDOMADMINS01."
                Write-Host -ForegroundColor Red "Clique 'OK'.  De volta a janela anterior, selecione primeiro o 'DOMGV\Domain Admins' e na parte"
                Write-Host -ForegroundColor Red "de baixo, clique no quadrado 'Full Control' na coluna 'Allow'. Repita o procedimento para o grupo"
                Write-Host -ForegroundColor Red "'DOMGV\UDOMADMINS01'. Clique 'OK' e 'OK' mais uma vez para encerrar a janela."
                Write-Host; Write-Host
                Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
                Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
            }
            Finally {
                Write-Host; Write-Host "Script finalizado."; Write-Host
            }
        }
    }
}
