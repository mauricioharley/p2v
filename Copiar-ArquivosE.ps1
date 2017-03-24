# Script para realizar copias dos arquivos (unidade secundaria)
#
param([parameter(Mandatory=$true)][String]$Nova,[String]$Fase,[String]$Secundario)
$ErrorActionPreference = "Stop"

$Domain = "dominio.Cliente"
$FilePerfis = "D:\MIGRA\Perfis.csv"
$FileCSV = "C:\MIGRA\Planilha_Migracao.csv"
$CodAgencia = $((Import-Csv $FileCSV -Delimiter ";").CODIGO)
$PrefixoServidor = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL).Substring(0,5)
$Destino1 = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM1)
$Destino2 = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM2)
$HostNovo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAME)
$Robocopy = "C:\ROBOCOPY.EXE"
$ArqControle = "D:\migra\Controle_Copias.txt"

$FileCliente = "C:\MIGRA\SecureCliente.txt"
$UserCliente = "dominio\usuario"
$PassCliente = Cat $FileCliente | ConvertTo-SecureString

# Obtencao das Credenciais do Cliente
$CredCliente = New-Object -TypeName System.Management.Automation.PSCredential `
            -ArgumentList $UserCliente, $PassCliente

# Verificando se a VM1 continua com o nome inicial (terminando com "_NEW") ou se ja foi renomeada
if ($Nova -eq "S") {
    $ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL)
    $Destino1 = $Destino1 + "_NEW"
}
else {
    $ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL) + "_OLD"
}
$Todos = $Destino1,$Destino2

# Verificando se a copia estah sendo executada na PRE-migracao ou na MIGRACAO
if ($Fase -eq "P") {
    $SufixoLog = "_INI"
}
else {
    Write-Host; Write-Host -ForegroundColor Yellow "Serao realizadas copias diferenciais!"
    Write-Host -ForegroundColor Yellow "Pressione ENTER para continuar."
    $SufixoLog = "_DIF"
}

# Pastas, destinos e arquivos de log
$Pastas = "AREAS","ARQUIVOS","GERIC","INSTALL","MAINFTP","OCTOPUS","PERFIS", `
          "PROGRAMS","PUBLICO","SCANNER","SYSOUT","SISTEMAS","SQLBACKUPS","SQLDEVICES","UTILS"

$Destinos = $Destino2,$Destino2,$Destino2,$Destino2,$Destino1,"*",$Destino2, `
            $Destino2,$Destino2,$Destino2,"*",$Destino1,$Destino1,$Destino1,$Destino2

$ArqLOG = "d:\migra\logsE\log"
$TestarDrive = "\\"+$ServidorAntigo+"\DISCO"+$Secundario+"$" # Para verificar se existe DISCO<Secundario>$ no servidor antigo

# Gerando lista de pastas de perfis a serem copiados
Write-Host "Gerando lista de perfis com home directory no servidor..."
Try {
    Invoke-Command -ComputerName $Destino2 -Credential $CredCliente -ScriptBlock {
        Get-ADUser -LDAPFilter "(homeDirectory=*$using:ServidorAntigo*)" -Properties * -Server $using:Destino2 `
          | Select-Object SamAccountName `
          | Export-Csv \\$using:HostNovo\d$\migra\perfis.csv -Encoding ascii -NoTypeInformation
    }
}
Catch 
{
    Write-Host -ForegroundColor Red "Impossivel gerar lista de perfis atuais no servidor $ServidorAntigo!"
    Write-Host -ForegroundColor Red "Verifique a lista manualmente."
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    Pause
}

# Obtendo perfis a serem copiados e a serem excluidos. Considera como existente se
# o arquivo $FilePerfis estiver em D:\migra\perfis.csv e o tamanho for maior que ZERO
$TemPerfil = $false
if ((Test-Path $FilePerfis) -and ((Get-Item $FilePerfis).Length -gt 0)) {
    $TemPerfil = $true
    # Perfis a copiar para a pasta de destino
    Try { $PerfisCopiar = $((Import-Csv $FilePerfis).SamAccountName) }
    Catch { $PerfisCopiar = "" }
    # Perfis a copiar para a pasta temporarios (excluidos)
    Try { $Caminho = "\\"+$ServidorAntigo+"\"+$Secundario+"$\PERFIS"
          $PerfisExcluir = (Get-ChildItem $Caminho -Exclude $PerfisCopiar | Select-Object -ExpandProperty Name) }
    Catch { $PerfisExcluir = "" }
}

# Criando compartilhamento do disco secundario no Servidor Antigo para o caso de nao existir
Try {
    Invoke-Command -ComputerName $ServidorAntigo -Credential $CredCliente -ScriptBlock {
        $Cadeia = "DISCO"+$Secundario+"$="+$Secundario+":\"
        net.exe share $Cadeia "/grant:everyone,full"
    }
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel gerar compartilhamento DISCO$Secundario$ ou ele ja existe!"
    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
}

# Verificando se foram declaradas as mesmas quantidades acima para o array $Pastas
# e o array $Destinos.  Os numeros de itens precisam ser os mesmos.
if ($Pastas.Count -ne $Destinos.Count) {
    Write-Host
    Write-Host -ForegroundColor Red "Quantidades de pastas e de destinos sao diferentes!"
    Write-Host -ForegroundColor Red "Verifique, corrija o script e volte a executa-lo!"
    Write-Host -ForegroundColor Red "Pressione ENTER para continuar."
    Pause
}
elseif (-not (Test-Path $TestarDrive)) {
    Write-Host -ForegroundColor Red "Nao existe compartilhamento DISCO$Secundario$ (unidade $Secundario) em $ServidorAntigo!"
    Write-Host -ForegroundColor Red "Saindo do script!"
}
else {
    # Calculando data e hora de inicio das copias
    $DataHoraInicio = (Get-Date -UFormat "%d/%m/%Y as %R h")
    # Limpando estados dos jobs
    Try {
        Remove-Job * -Force
    }
    Catch {
        Write-Host -ForegroundColor Red "Impossivel limpar lista de jobs atuais!"
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    }
    # Definindo array de jobs para o ROBOCOPY
    $Jobs = @()
    # Realizando copias
    # Criando arquivo de controle de copias (usado para registrar termino da copia do drive secundario)
    Try {
        "0" | Out-File $ArqControle
    }
    Catch {
        Write-Host -ForegroundColor Red "Impossivel gerar arquivo de controle de copias $ArqControle!"
        Write-Host -ForegroundColor Red "Saindo do script!"
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
        Exit
    }
    for ($i = 0; $i -lt $Pastas.Count; $i++) {
        # Se a pasta precisar ser copiada para mais de um destino, outro laco eh necessario!
        if ($Destinos[$i] -eq "*") {
            for ($j = 0; $j -lt $Todos.Count; $j++) {
                $A = "\\"+$ServidorAntigo+"\DISCO$Secundario$\"+$Pastas[$i]
                $B = "\\"+$Todos[$j]+"\D$\"+$Pastas[$i]
                $Registro = $ArqLOG+$Pastas[$i]+$SufixoLog+".log"
                Write-Host; Write-Host "Copiando" $A "para" $B"..." 
                Try {
                    $NomeJob = "Copia_"+$Pastas[$i]+"_"+$Todos[$j]
                    $Jobs += Start-Job -Name $NomeJob -ScriptBlock {
                            param($Robocopy) & $Robocopy $using:A $using:B /s /e /w:1 /r:1 /sec /copyall /tee /log:$using:Registro
                    } -ArgumentList $Robocopy
                }
                Catch {
                    Write-Host -ForegroundColor Red "Impossivel copiar $A para $B!"
                    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
                    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
                }
                
                # Criando compartilhamento no destino.  Se a pasta for MAINFTP, deve ser 
                # sucedida por um "$"
                $Flag = ""
                if ($Pastas[$i] -eq "MAINFTP") {
                    $Flag = "$"
                }
                $Target = "\\"+$Todos[$j]+"\"+$Pastas[$i] + $Flag
                $Caminho = "D:\"+$Pastas[$i]
                $Compart = $Pastas[$i]+$Flag
                if (-not (Test-Path $Target)) {
                    Try {
                        Invoke-Command -ComputerName $Todos[$j] -Credential $CredCliente -ScriptBlock {
                            net.exe share "$using:Compart=$using:Caminho" "/grant:everyone,full"
                        }
                    }
                    Catch {
                        Write-Host -ForegroundColor Red "Impossivel gerar compartilhamento $Caminho!"
                        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
                        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
                    }
                }
            }
        }
        else {
            # Estas pastas especiais precisam de uma nova nomenclatura no destino
            if (($Pastas[$i] -eq "AREAS") -or ($Pastas[$i] -eq "PERFIS") -or ($Pastas[$i] -eq "PUBLICO")) {
                if ($Pastas[$i] -eq "PERFIS") {
                    $A = "\\"+$ServidorAntigo+"\DISCO$Secundario$\"+$Pastas[$i]
                }
                else {
                    $A = "\\"+$ServidorAntigo+"\DISCO$Secundario$\"+$PrefixoServidor+"\"+$Pastas[$i]
                }
                $B = "\\"+$Destinos[$i]+"\D$\"+$PrefixoServidor+"\"+$Pastas[$i]
                $Registro = $ArqLOG+$Pastas[$i]+$SufixoLog+".log"
                Write-Host; Write-Host "Copiando" $A "para" $B"..." 
                Try {
                    $NomeJob = "Copia_"+$Pastas[$i]+"_"+$Destinos[$i]
                    # Se houver perfis a copiar, tratar diferentemente
                    if (($TemPerfil) -and ($Pastas[$i] -eq "PERFIS")) {
                        $Jobs += Start-Job -Name $NomeJob -ScriptBlock {
                            param($Robocopy) & $Robocopy $using:A $using:B /s /e /w:1 /r:1 /sec /copyall /tee /xd $using:PerfisExcluir /log:$using:Registro
                        } -ArgumentList $Robocopy
                    }
                    else {
                        $Jobs += Start-Job -Name $NomeJob -ScriptBlock {
                            param($Robocopy) & $Robocopy $using:A $using:B /s /e /w:1 /r:1 /sec /copyall /tee /log:$using:Registro
                        } -ArgumentList $Robocopy
                    }
                }
                Catch {
                    Write-Host -ForegroundColor Red "Impossivel copiar $A para $B!"
                    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
                    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
                }
                
                # Criando compartilhamento no destino
                $Target = "\\"+$Destinos[$i]+"\"+$Pastas[$i]
                $Caminho = "D:\"+$PrefixoServidor+"\"+$Pastas[$i]
                $Compart = $Pastas[$i]
                if (-not (Test-Path $Target)) {
                    Try {
                        Invoke-Command -ComputerName $Destinos[$i] -Credential $CredCliente -ScriptBlock {
                            net.exe share "$using:Compart=$using:Caminho" "/grant:everyone,full"
                        }
                    }
                    Catch {
                        Write-Host -ForegroundColor Red "Impossivel gerar compartilhamento $Caminho!"
                        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
                        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
                    }
                }
                
            }
            else {
                $A = "\\"+$ServidorAntigo+"\DISCO$Secundario$\"+$Pastas[$i]
                $B = "\\"+$Destinos[$i]+"\D$\"+$Pastas[$i]
                $Registro = $ArqLOG+$Pastas[$i]+$SufixoLog+".log"
                Write-Host; Write-Host "Copiando" $A "para" $B"..."
                Try { 
                    $NomeJob = "Copia_"+$Pastas[$i]+"_"+$Destinos[$i]
                    $Jobs += Start-Job -Name $NomeJob -ScriptBlock {
                        param($Robocopy) & $Robocopy $using:A $using:B /s /e /w:1 /r:1 /sec /copyall /tee /log:$using:Registro
                    } -ArgumentList $Robocopy
                }
                Catch {
                    Write-Host -ForegroundColor Red "Impossivel copiar $A para $B!"
                    Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
                    Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
                }
                
                # Criando compartilhamento no destino.  Se a pasta for MAINFTP, deve ser 
                # sucedida por um "$"
                $Flag = ""
                if ($Pastas[$i] -eq "MAINFTP") {
                    $Flag = "$"
                }
                $Target = "\\"+$Destinos[$i]+"\"+$Pastas[$i]+$Flag
                $Caminho = "D:\"+$Pastas[$i]
                $Compart = $Pastas[$i]+$Flag
                if (-not (Test-Path $Target)) {
                    Try {
                        Invoke-Command -ComputerName $Destinos[$i] -Credential $CredCliente -ScriptBlock {
                            net.exe share "$using:Compart=$using:Caminho" "/grant:everyone,full"
                        }
                    }
                    Catch {
                        Write-Host -ForegroundColor Red "Impossivel gerar compartilhamento $Caminho!"
                        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
                        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
                    }
                }
            }
        }
    }
    
    # Copiando as exclusoes
    $A = "\\"+$ServidorAntigo+"\DISCO$Secundario$\"
    $B = "\\"+$Destino2+"\D$\TEMPORARIOS"
    $Registro = $ArqLOG+"EXCLUSOES"+$SufixoLog+".log"
    Write-Host; Write-Host "Copiando EXCLUSOES para" $Destino2"..."
    if (-not (Test-Path $B)) {
        Try {
            mkdir $B
        }
        Catch {
            Write-Host -ForegroundColor Red "Impossível criar pasta $B!"
            Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
            Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
        }
    }
    Try {
        attrib -s -h $B
    }
    Catch {
        Write-Host -ForegroundColor Red "Impossível alterar atributos de $B!"
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    }

    Try {
        $NomeJob = "Copia_EXCLUSOES_"+$Destino2
        $Jobs += Start-Job -Name $NomeJob -ScriptBlock {
            param($Robocopy) & $Robocopy $using:A $using:B /s /e /w:1 /r:1 /sec /copyall /tee /log:$using:Registro /XD $using:Pastas
        } -ArgumentList $Robocopy
    }
    Catch {
        Write-Host -ForegroundColor Red "Impossivel copiar exclusoes de pastas!"
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    }
    
    # Copiando perfis excluidos (que nao possuem usuarios correspondentes atrelados)
    if ($TemPerfil) {
        Try {
            $A = "\\"+$ServidorAntigo+"\DISCO$Secundario$\PERFIS"
            $B = "\\"+$Destino2+"\D$\TEMPORARIOS\PERFIS"
            $Registro = $ArqLOG+"EXCLUSOES_PERFIS"+$SufixoLog+".log"
            $NomeJob = "Copia_EXCLUSOES_PERFIS_"+$Destino2
            Write-Host; Write-Host "Copiando EXCLUSOES de PERFIS para" $Destino2"..."
            $Jobs += Start-Job -Name $NomeJob -ScriptBlock {
                param($Robocopy) & $Robocopy $using:A $using:B /s /e /w:1 /r:1 /sec /copyall /tee /XD $using:PerfisCopiar /log:$using:Registro
            } -ArgumentList $Robocopy
        }
        Catch {
            Write-Host -ForegroundColor Red "Impossivel copiar exclusoes de pastas!"
            Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
            Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
        }
    }

    # Criando compartilhamentos finais
    Foreach ($Destino in $Todos) { 
        Try {
            Invoke-Command -ComputerName $Destino -Credential $CredCliente -ScriptBlock {
                #$Cadeia = "DISCO"+$Secundario+"$="+$Secundario+":\"
                net.exe share "DISCOE$=E:\" "/grant:everyone,full"
            }
        }
        Catch {
            Write-Host -ForegroundColor Red "Impossivel criar compartilhamento DISCOE$ em $Destino!"
            Write-Host -ForegroundColor Red "Mensagem de Erro:  " $_.Exception.Message
            Write-Host -ForegroundColor Red "Item:  " $_.Exception.ItemName
        }
    }
    
    # Pequena pausa antes de limpar a tela
    Sleep 5

    # Apresentando estados dos jobs.  So finalizara o script quando todos os jobs
    # forem concluidos (incluindo as copias das EXCLUSOES).
    $Tabela = @{E={$_.Name};L="Nome da Copia (Disco $Secundario)";width=35}, `
              @{E={$_.State};L="Situacao";width=10}
    Do {
        Clear
        $Sair = $true
        for ($i = 0; $i -lt $Jobs.Count; $i++) {
            if ($Jobs[$i].State -eq "Running") {
                $Sair = $false
            }
        }
        $Jobs | Format-Table $Tabela
        Sleep 1
    } While (-not $Sair)

    # Calculando data e hora de termino das copias
    $DataHoraFim = (Get-Date -UFormat "%d/%m/%Y as %R h")

    # Criando pastas de perfis que ainda nao existem
    Write-Host; Write-Host "Criando pastas de perfis que ainda nao existem..."
    ForEach ($Perfil in $PerfisCopiar) {
        $PathPerfil = "\\"+$Destino2+"\DISCOD$\"+$PrefixoServidor+"\PERFIS\"+$Perfil
        if (-not (Test-Path $PathPerfil)) {
            mkdir $PathPerfil | Out-Null
        }
    }

    # Atualizando arquivo de controle de copia denotando final das operacoes no drive secundario
    Try {
        "1" | Out-File $ArqControle
        $DataHoraInicio | Out-File $ArqControle -Append
        $DataHoraFim | Out-File $ArqControle -Append
    }
    Catch {
        Write-Host -ForegroundColor Red "Impossivel atualizar arquivo de controle de copia $ArqControle!"
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
    }
    Finally {
         Write-Host; Write-Host "Script de copias (Drive $Secundario) finalizado."
         Pause
    }
}
