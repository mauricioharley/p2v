# Script para realizar copias dos arquivos (unidade D:)
#
$ErrorActionPreference = "Stop"

$Domain = "dominio.Cliente"
$FilePerfis = "D:\MIGRA\Perfis.csv"
$FileCSV = "C:\MIGRA\Planilha_Migracao.csv"
$CodAgencia = $((Import-Csv $FileCSV -Delimiter ";").CODIGO)
$NomeAgencia = $((Import-Csv $FileCSV -Delimiter ";").UNIDADE)
$PrefixoServidor = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL).Substring(0,5)
$Destino1 = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM1)
$Destino2 = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM2)
$HostNovo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAME)
$FileRelatD = "D:\migra\LogsD\RelatD_"+$CodAgencia+".txt"
$FileRelatE = "D:\migra\logsE\RelatE_"+$CodAgencia+".txt"
$FileComparacao = "D:\migra\Comparacoes_Copias_"+$CodAgencia+".txt"
$Robocopy = "C:\ROBOCOPY.EXE"
$ArqControle = "D:\migra\Controle_Copias.txt"
$TempoChecagem = 15

$FileCliente = "C:\MIGRA\SecureCliente.txt"
$UserCliente = "dominio\usuario"
$PassCliente = Cat $FileCliente | ConvertTo-SecureString

# Obtencao das Credenciais do Cliente
$CredCliente = New-Object -TypeName System.Management.Automation.PSCredential `
            -ArgumentList $UserCliente, $PassCliente

# Verificando se a VM1 continua com o nome inicial (terminando com "_NEW") ou se ja foi renomeada
Write-Host; Write-Host -ForegroundColor Yellow "A VM1 (de negocios) ainda esta com hostname terminando em _NEW?"
Do
{
 Write-Host -ForegroundColor Yellow "Sim ou Nao?  Digite apenas S ou N e pressione ENTER: " -NoNewline
 $New = Read-Host
 $New = $New.ToUpper()
}
While ($New -ne "S" -and $New -ne "N")
if ($New -eq "S") {
    $ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL)
    $Destino1 = $Destino1 + "_NEW"
}
else {
    $ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL) + "_OLD"
}
$Todos = $Destino1,$Destino2

# Verificando se a copia estah sendo executada na PRE-migracao ou na MIGRACAO
Write-Host; Write-Host -ForegroundColor Yellow "Esta copia sera de (P)re-migracao ou de (M)igracao?"
Do
{
 Write-Host -ForegroundColor Yellow "Digite apenas P ou M e pressione ENTER: " -NoNewline
 $Fase = Read-Host
 $Fase = $Fase.ToUpper()
}
While ($Fase -ne "P" -and $Fase -ne "M")
if ($Fase -eq "P") {
    $SufixoLog = "_INI"
}
else {
    Write-Host; Write-Host -ForegroundColor Yellow "Serao realizadas copias diferenciais!"
    Write-Host -ForegroundColor Yellow "Pressione ENTER para continuar."
    Pause
    $SufixoLog = "_DIF"
}

# Pastas, destinos e arquivos de log
$Pastas = "AREAS","ARQUIVOS","GERIC","INSTALL","MAINFTP","OCTOPUS","PERFIS", `
          "PROGRAMS","PUBLICO","SCANNER","SYSOUT","SISTEMAS","SQLBACKUPS","SQLDEVICES","UTILS"

$Destinos = $Destino2,$Destino2,$Destino2,$Destino2,$Destino1,"*",$Destino2, `
            $Destino2,$Destino2,$Destino2,"*",$Destino1,$Destino1,$Destino1,$Destino2

$ArqLOG = "d:\migra\logsD\log"

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
    Try { $PerfisExcluir = (Get-ChildItem "\\$ServidorAntigo\D$\PERFIS" -Exclude $PerfisCopiar | Select-Object -ExpandProperty Name) }
    Catch { $PerfisExcluir = "" }
}

# Criando compartilhamento DISCOD$ no Servidor Antigo para o caso de nao existir
Try {
    Invoke-Command -ComputerName $ServidorAntigo -Credential $CredCliente -ScriptBlock {
        net.exe share "DISCOD$=D:\" "/grant:everyone,full"
    }
}
Catch {
    Write-Host -ForegroundColor Red "Impossivel gerar compartilhamento DISCOD$ ou ele ja existe!"
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
else {
    # Verificando se existe drive secundario no servidor de origem (DriveType = '3')
    $Funcionou = $true
    Try {
        $DrivesOrigem = (Get-WmiObject -ComputerName $ServidorAntigo -Query "Select * from Win32_LogicalDisk where DriveType='3'")
    }
    Catch {
        $Funcionou = $false
        Write-Host -ForegroundColor Red "Impossivel obter informacoes sobre unidades de disco em $ServidorAntigo!"
        Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
        Write-Host
        Write-Host -ForegroundColor Yellow "Verifique o $ServidorAntigo e informe se ele possui ou nao drive secundario."
        Do {
            Write-Host -ForegroundColor Yellow "Digite apenas S ou N: " -NoNewline
            $Opcao = Read-Host
            $Opcao = $Opcao.ToUpper()
        } While (($Opcao -ne "S") -and ($Opcao -ne "N"))        
        if ($Opcao -eq "N") {
            $TemSecundario = $false
            Write-Host -ForegroundColor Yellow "Servidor nao possui disco secundario.  Nao serao realizadas copias a partir do mesmo!"
            Pause
        }
        else {
            Write-Host -ForegroundColor Yellow "O disco D NAO EH considerado drive secundario! Informe a letra correspondente (maior ou igual a E)."
            $CadDrives = "EFGHIJKLMNOPQRSTUVWXYZ"
            # O laco abaixo servira para obter qual a letra correspondente ao drive secundario e sera executado enquanto for informada
            # uma string com comprimento maior que 1 e que nao esteja dentro da lista de drives especificados acima em $CadDrives.
            Do {
                Write-Host "Digite APENAS a letra correspondente ao disco secundario em ($ServidorAntigo):  " -NoNewline
                $Secundario = Read-Host
                $Secundario = $Secundario.ToUpper()
            } While (($Secundario.Length -ne 1) -or ($CadDrives.IndexOf($Secundario) -eq -1))
            
            # Checando se o drive informado realmente existe no servidor
            $Caminho = "\\"+$ServidorAntigo+"\"+$Secundario+"$"
            if (Test-Path $Caminho) {
                $TemSecundario = $true
            }
            else {
                Write-Host -ForegroundColor Red "Drive informado nao existe no servidor. Nao serao realizadas copias a partir do mesmo!"
                $TemSecundario = $false
                Pause
            }
        }
    }

    # So entrara neste primeiro IF se a instrucao WMI anterior for executada com sucesso
    if ($Funcionou) {
        if ($DrivesOrigem.Count -lt 3) {    # Se a quantidade for menor que 3, significa que existem apenas os drives C: e D:.
            Write-Host -ForegroundColor Yellow "Servidor $ServidorAntigo nao possui drive secundario! Nao serao realizadas copias a partir do mesmo!"; Write-Host
            $TemSecundario = $false
        }
        else {
            $TemSecundario = $true
            $Secundario = $DrivesOrigem[$DrivesOrigem.Count-1].DeviceID
            $Secundario = $Secundario.Substring(0,1)
        }
    }

    # Caso haja drive secundario, iniciar copias a partir do mesmo em janela a parte.
    if ($TemSecundario) {
        Try {
            Start-Process PowerShell -ArgumentList "& C:\MIGRA\Scripts\Copiar-ArquivosE.ps1 -Nova $New -Fase $Fase -Secundario $Secundario" -Verb RunAs
        }
        Catch {
            Write-Host -ForegroundColor Red "Impossivel iniciar copias de arquivos no drive secundario!"
            Write-Host
            Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
            Pause
        }
    }

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
    for ($i = 0; $i -lt $Pastas.Count; $i++) {
        # Se a pasta precisar ser copiada para mais de um destino, outro laco eh necessario!
        if ($Destinos[$i] -eq "*") {
            for ($j = 0; $j -lt $Todos.Count; $j++) {
                $A = "\\"+$ServidorAntigo+"\DISCOD$\"+$Pastas[$i]
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
                    $A = "\\"+$ServidorAntigo+"\DISCOD$\"+$Pastas[$i]
                }
                else {
                    $A = "\\"+$ServidorAntigo+"\DISCOD$\"+$PrefixoServidor+"\"+$Pastas[$i]
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
                $A = "\\"+$ServidorAntigo+"\DISCOD$\"+$Pastas[$i]
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
    $A = "\\"+$ServidorAntigo+"\DISCOD$\"
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
            $A = "\\"+$ServidorAntigo+"\DISCOD$\PERFIS"
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

    # Criando compartilhamentos finais (DISCOC$ e DISCOD$)
    Foreach ($Destino in $Todos) { 
        Try {
            Invoke-Command -ComputerName $Destino -Credential $CredCliente -ScriptBlock {
                net.exe share "DISCOC$=C:\" "/grant:everyone,full"
            }
        }
        Catch {
            Write-Host -ForegroundColor Red "Impossivel criar compartilhamento DISCOC$!"
            Write-Host -ForegroundColor Red "Mensagem de Erro:  " $_.Exception.Message
            Write-Host -ForegroundColor Red "Item:  " $_.Exception.ItemName
        }
        Try {
            Invoke-Command -ComputerName $Destino -Credential $CredCliente -ScriptBlock {
                net.exe share "DISCOD$=D:\" "/grant:everyone,full"
            }
        }
        Catch {
            Write-Host -ForegroundColor Red "Impossivel criar compartilhamento DISCOD$!"
            Write-Host -ForegroundColor Red "Mensagem de Erro:  " $_.Exception.Message
            Write-Host -ForegroundColor Red "Item:  " $_.Exception.ItemName
        }
    }
    
    # Pequena pausa antes de limpar a tela
    Sleep 5

    # Apresentando estados dos jobs.  So finalizara o script quando todos os jobs
    # forem concluidos (incluindo as copias das EXCLUSOES).
    $Tabela = @{E={$_.Name};L="Nome da Copia (Disco D:)";width=35}, `
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

    # Verificando se a copia do drive secundario (caso exista) foi finalizada.
    # Caso exista, aguardar por ela (sera sinalizada com um "1" em $ArqControle
    # Faz uma verificacao a cada periodo informado em $TempoChecagem (default: 15 segundos)
    $TerminouE = "0"
    if (Test-Path $ArqControle) {
        Write-Host "Aguardando termino da copia do drive ($Secundario):..." -NoNewline
        Do {
            Sleep $TempoChecagem
            Try {
                $TerminouE = (Get-Content $ArqControle)[0]
            }
            Catch {
                $TerminouE = "1"
            }
        } While ($TerminouE -eq "0")
        Write-Host "pronto!"; Write-Host
    }

    # Se $TerminouE for igual a 1, significa dizer que a copia do drive secundario foi concluida, pois isso eh
    # registrado pelo script correspondente.  Na sequencia, eh preciso obter datas de inicio e fim dessa
    # copia e apagar o arquivo para que ele nao possa ser novamente usado numa proxima iteracao.
    if ($TerminouE -eq "1") {
        Try {
            $DataInicioE = (Get-Content $ArqControle)[1]
            $DataFimE = (Get-Content $ArqControle)[2]
        }
        Catch {
            $DataInicioE = "FALHA AO OBTER DATA DE INICIO DO ($Secundario):"
            $DataFimE = "FALHA AO OBTER DATA DE FIM DO ($Secundario):"
        }
        Remove-Item $ArqControle -Force 
    }

    # Etapa de Geracao dos Relatorios. Caso a variavel $TerminouE seja 0 significa que nao existe
    # copia do drive secundario.  Caso seja 1, esta copia terminou, pois o controle eh feito pelo 
    # script Copiar-ArquivosE.ps1
    Write-Host "Executando comparacoes de copias e gerando relatorios..."
    if ($TerminouE -eq 0) {
        & c:\migra\scripts\Verificar-Copias.ps1 -Drive "D" -Nova $New -Secundario ""
    }
    else {
        & C:\migra\scripts\Verificar-Copias.ps1 -Drive "A" -Nova $New -Secundario $Secundario
    }

    # Enviando e-mail de relatorio
    $SMTP = "correio.intra.Cliente"
    $Remetente = "migracaoservidores@correio.intra.Cliente"
    $ListaDestinatario = "GrupoMigracaodeNovosServidores@correio.intra.Cliente"
    
    if ($Fase -eq "P") {
        $Assunto = "PRE-migracao - Copias Concluidas - Agencia " + $CodAgencia
        $INIDIF = "INICIAIS"
    }
    else {
        $Assunto = "Migracao - Copias Concluidas - Agencia " + $CodAgencia
        $INIDIF = "DIFERENCIAIS"
    }
    $Corpo  = "Concluidas as copias " + $INIDIF +" do drive D:.`r`n`r`n"
    $Corpo += "Iniciadas em " + $DataHoraInicio + ".`r`n"
    $Corpo += "Finalizadas em " + $DataHoraFim + ".`r`n`r`n"
    if ($TerminouE -eq "1") {
        $Corpo += "Concluidas as copias " + $INIDIF + " do drive ($Secundario):.`r`n`r`n"
        $Corpo += "Iniciadas em " + $DataInicioE + ".`r`n"
        $Corpo += "Finalizadas em " + $DataFimE + ".`r`n`r`n"
        $Anexos = $FileComparacao,$FileRelatD,$FileRelatE
    }
    else {
        $Corpo += "Nao foi encontrado outro drive secundario em $ServidorAntigo!`r`n`r`n"
        $Anexos = $FileComparacao,$FileRelatD
    }
    if ($Fase -eq "P") {
        $Corpo += "PRE-migracao Auriga CONCLUIDA!  Cliente pode dar inicio as suas etapas de PRE-migracao em '($CodAgencia) $NomeAgencia'."
    }

    Try {
        Send-MailMessage -From $Remetente -To $ListaDestinatario -Subject $Assunto -Body $Corpo -SmtpServer $SMTP -Attachments $Anexos
    }
    Catch {
        Write-Host -ForegroundColor Red "Impossivel enviar e-mail de relatorio!"
        Write-Host -ForegroundColor Red "Mensagem de Erro:  " $_.Exception.Message
        Write-Host -ForegroundColor Red "Item:  " $_.Exception.ItemName
    }
    Finally {
        Write-Host; Write-Host "Script de copias (Drive D:) finalizado e e-mail enviado."
    }
}
