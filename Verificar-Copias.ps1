# Script para Verificar as copias realizadas e apresentar resultados consolidados
# O parametro "Drive" indica se sera verificado o drive D: ou ele e o secundario.
# O Parametro "Nova" indica se a VM1 ainda estah com o sufixo _NEW no nome.
#
param([parameter(Mandatory=$true)][string]$Drive,[string]$Nova,[string]$Secundario)
$ErrorActionPreference = "Stop"
$FilePerfis = "D:\MIGRA\Perfis.csv"
$FileCSV = "C:\MIGRA\Planilha_Migracao.csv"
$Notepad = "NOTEPAD.EXE"
$PrefixoServidor = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL).Substring(0,5)

# Funcao que retorna tamanho recursivo da pasta informada.
# Parametros:
# $Pasta:        informa a pasta da qual se quer obter o tamanho
# $ChecarPerfil: informa se esta pasta se trata da pasta PERFIS
# $PastaExcluir: caso a $Pasta seja PERFIS, excluir estas pastas da verificacao
function PegarTamanho {
    Param([string]$Param1,[string]$Param3)
    $item = $Param1
    $params = New-Object System.Collections.Arraylist
    # Checando se a pasta a ser comparada eh a pasta de PERFIS
    if ($item.Substring($item.Length-6,6) -eq "PERFIS") {
        $params.AddRange(@("/L","/S","/NJH","/FP","/NC","/NDL","/TS","/XJ","/R:0","/W:0","/XD",$Param3))
    }
    else {
        $params.AddRange(@("/L","/S","/NJH","/FP","/NC","/NDL","/TS","/XJ","/R:0","/W:0"))
    }
    $countPattern = "^\s{4}Files\s:\s+(?<Count>\d+).*"
    $sizePattern = "^\s{4}Bytes\s:\s+(?<Size>\d+(?:\.?\d+)).*"
    $return = c:\robocopy.exe $item NULL $params
    If ($return[-5] -match $countPattern) {
        $Count = $matches.Count
    }
    $UniMedicao = "X"
    If ($Count -gt 0) {
        If ($return[-4] -match $sizePattern) {
            $Size = $matches.Size
            $Letras = "k","m","g"
            ForEach ($Letra in $Letras) {
                if ($return[-4].IndexOf($Letra) -ne -1) {
                    $UniMedicao = $Letra.ToUpper()
                }
            }
        }
    } Else {
        $Size = 0
    }
    $object = New-Object PSObject -Property @{
        FullName = $item
        Unit = $UniMedicao
        Count = [int]$Count
        Size = ([math]::Round($Size,2))
    }
    $object.pstypenames.insert(0,'IO.Folder.Foldersize')
    Write-Output $object
    $Size=$Null
}

$Destino1 = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM1); $VM1 = $Destino1
$Destino2 = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEVM2); $VM2 = $Destino2
$VMs = $VM1,$VM2

# Verificando se a VM1 continua com o nome inicial (terminando com "_NEW") ou se ja foi renomeada
# Isso eh passado como parametro para o script
if ($Nova -eq "S") {
    $ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL)
    $Destino1 = $Destino1 + "_NEW"
}
else {
    $ServidorAntigo = $((Import-Csv $FileCSV -Delimiter ";").HOSTNAMEATUAL) + "_OLD"
}
$Todos = $Destino1,$Destino2

# Verificando se existe arquivo de perfis criados e se o tamanho dele eh maior que zero.
# Caso exista e possua conteudo, usar variaveis especificas para obter pastas de perfis
# do mesmo e perfis que foram excluidos da copia.
$TemPerfil = $false
if ((Test-Path $FilePerfis) -and ((Get-Item $FilePerfis).Length -gt 0)) {
    $TemPerfil = $true
    # Perfis copiados para a pasta de destino
    Try { $PerfisCopiar = $((Import-Csv $FilePerfis).SamAccountName) }
    Catch { $PerfisCopiar = "" }
    # Perfis copiados para a pasta temporarios (excluidos)
    Try { $PerfisExcluir = (Get-ChildItem "\\$ServidorAntigo\D$\PERFIS" -Exclude $PerfisCopiar | Select-Object -ExpandProperty Name) }
    Catch { $PerfisExcluir = "" }
}

# Obtendo codigo e nome da filial
$FileCSV = "C:\Migra\Planilha_Migracao.csv"
Try{
    $CodFilial = $((Import-Csv $FileCSV -Delimiter ";").CODIGO)
    $NomeFilial = $((Import-Csv $FileCSV -Delimiter ";").UNIDADE)
}
Catch{
    $CodFilial = "000"
    $NomeFilial = "FIIALL NAO ENCONTRADA"
}

$DirLogsD = "D:\migra\LogsD"
$FileRelatD = "D:\migra\LogsD\RelatD_"+$CodAgencia+".txt"
$DirLogsE = "D:\migra\LogsE"
$FileRelatE = "D:\migra\logsE\RelatE_"+$CodAgencia+".txt"
$FileComparacao = "D:\migra\Comparacoes_Copias_"+$CodAgencia+".txt"

# Definindo variaveis de diretorios e arquivos de relatorio baseado na escolha da opcao acima
Switch ($Drive) {
    "D" {$DirLogs = $DirLogsD; $FileRelats = $FileRelatD}
    "E" {$DirLogs = $DirLogsE; $FileRelats = $FileRelatE}
    "A" {$Dirlogs = $DirLogsD,$DirLogsE; $FileRelats = $FileRelatD,$FileRelatE}
}

$i = 0
Foreach ($Log in $DirLogs) {
    $LogsINI = $Log + "\*_INI.log"
    $LogsDIF = $Log + "\*_DIF.log"
    if ($Drive -eq "A") {
        Write-Host "Gerando relatorio em $FileRelats[$i]..."
        $ArqRelat = $FileRelats[$i]
    }
    else {
        Write-Host "Gerando relatorio em $FileRelats..."
        $ArqRelat = $FileRelats
    }
    # Se nao existir qualquer arquivo de log, sinalizar com erro
    if ((-not (Test-Path $LogsINI)) -and (-not (Test-Path $LogsDIF))) {
        Write-Host -ForegroundColor Red "Nao existem quaisquer arquivos de log em $Log!"
        Write-Host
    }
    else {
        Try {
            $DataAtual = (Get-Date -UFormat "%d/%m/%Y as %R h")
            "***********************************************************" | Out-File $ArqRelat 
            "   Projeto Migracao Cliente - Relatorio de Copias Realizadas   " | Out-File $ArqRelat -Append
            "   Agencia:  " + $CodAgencia + "  Nome:  " + $NomeAgencia    | Out-File $ArqRelat -Append
            "   Relatorio gerado em " + $DataAtual                        | Out-File $ArqRelat -Append 
            "***********************************************************" | Out-File $ArqRelat -Append
            "`r`n" | Out-File $ArqRelat -Append
        }
        Catch {
            Write-Host -ForegroundColor Red "Impossivel criar arquivo de relatorio $ArqRelat!"
            Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
            Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
            Exit
        }
        if (Test-Path $LogsINI) { # Logs de copias INICIAIS
            $Funcionou = $true
            Try {
                $Arquivos = Get-ChildItem $LogsINI
            }
            Catch {
                $Funcionou = $false
                Write-Host -ForegroundColor Red "Impossivel encontrar arquivos de log em $LogsINI!"
                Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
                Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
            }
            if ($Funcionou) {
                "*** Inicio de Relatorios de copias INICIAIS ***`r`n" | Out-File $ArqRelat -Append
                # Varrendo os logs na pasta $LogsINI
                Foreach ($Arquivo in $Arquivos) {
                    # O padrao "0x" indica um codigo de erro em hexadecimal do ROBOCOPY
                    $Cadeia = Select-String $Arquivo -Pattern "0x0000" -SimpleMatch -Context 0,1 
                    $CadAUX = [string]$Cadeia # Convertendo para string para usar os metodos de comparacao mais abaixo
                    "Arquivo: $Arquivo" | Out-File $ArqRelat -Append
                    if ($Cadeia.Count -eq 0) {
                        "Nenhum erro encontrado.`r`n-------------`r`n" | Out-File $ArqRelat -Append
                    }
                    else {
                        $TemResumo = 0
                        $TemResumo = (Select-String -Pattern "Ended : " -InputObject (Get-Content $Arquivo) -AllMatches).Matches.Count
                        if ($TemResumo -gt 0) {
                            "Resumo:" | Out-File $ArqRelat -Append
                            # Os arquivos de LOG com resumo nao sao padronizados (podem ou nao ter a parte "Speed")
                            $TemSpeed = (Select-String -Pattern "Speed" -InputObject (Get-Content $Arquivo) -AllMatches).Matches.Count
                            if ($TemSpeed -gt 0) {
                                (Get-Content $Arquivo)[-10..-6] | Out-File $ArqRelat -Append
                            }
                            else {
                                (Get-Content $Arquivo)[-7..-3] | Out-File $ArqRelat -Append
                            }
                        }
                        "`r`nErros reportados:" | Out-File $ArqRelat -Append
                        $CadAUX + "`r`n-------------`r`n" | Out-File $ArqRelat -Append
                    }

                }
                "*** Fim de relatorios de copias INICIAIS ***`r`n`r`n" | Out-File $ArqRelat -Append
            }
        }
        else {
            Write-Host -ForegroundColor Red "Nao foi encontrado nenhum arquivo de log INICIAL!"; Write-Host
        }
        if (Test-Path $LogsDIF) { # Logs de copias DIFERENCIAIS
            $Funcionou = $true
            Try {
                $Arquivos = Get-ChildItem $LogsDIF
            }
            Catch {
                $Funcionou = $false
                Write-Host -ForegroundColor Red "Impossivel encontrar arquivos de log em $LogsDIF!"
                Write-Host -ForegroundColor Red "Mensagem de Erro: " $_.Exception.Message
                Write-Host -ForegroundColor Red "Item: " $_.Exception.ItemName
            }
            if ($Funcionou) {
                "*** Inicio de Relatorios de copias DIFERENCIAIS ***`r`n" | Out-File $ArqRelat -Append
                # Varrendo logs na pasta $LogsDIF
                Foreach ($Arquivo in $Arquivos) {
                    # O padrao "0x" indica um codigo de erro em hexadecimal do ROBOCOPY
                    $Cadeia = Select-String $Arquivo -Pattern "0x0000" -SimpleMatch -Context 0,1 
                    $CadAUX = [string]$Cadeia # Convertendo para string para usar os metodos de comparacao mais abaixo
                    "Arquivo: $Arquivo" | Out-File $ArqRelat -Append
                    if ($Cadeia.Count -eq 0) {
                        "Nenhum erro encontrado.`r`n-------------`r`n" | Out-File $ArqRelat -Append
                    }
                    else {
                        $TemResumo = 0
                        $TemResumo = (Select-String -Pattern "Ended : " -InputObject (Get-Content $Arquivo) -AllMatches).Matches.Count
                        if ($TemResumo -gt 0) {
                            "Resumo:" | Out-File $ArqRelat -Append
                            # Os arquivos de LOG com resumo nao sao padronizados (podem ou nao ter a parte "Speed")
                            $TemSpeed = (Select-String -Pattern "Speed" -InputObject (Get-Content $Arquivo) -AllMatches).Matches.Count
                            if ($TemSpeed -gt 0) {
                                (Get-Content $Arquivo)[-10..-6] | Out-File $ArqRelat -Append
                            }
                            else {
                                (Get-Content $Arquivo)[-7..-3] | Out-File $ArqRelat -Append
                            }
                        }
                        "`r`nErros reportados:" | Out-File $ArqRelat -Append
                        $CadAUX + "`r`n-------------`r`n" | Out-File $ArqRelat -Append
                    }
                }
                "*** Fim de relatorios de copias DIFERENCIAIS ***`r`n`r`n" | Out-File $ArqRelat -Append
            }
        }
        else {
            Write-Host "Nao foi encontrado nenhum arquivo de log DIFERENCIAL!"; Write-Host
        }
    }
    $i++
}

#
# Parte do script para comparar tamanhos das pastas
#
Write-Host; Write-Host "Relatorios gerados e finalizados.  Iniciando comparacao das pastas."

# Pastas, destinos e arquivos de log
$Pastas = "AREAS","ARQUIVOS","GERIC","INSTALL","MAINFTP","OCTOPUS","PERFIS", `
          "PROGRAMS","PUBLICO","SCANNER","SYSOUT","SISTEMAS","SQLBACKUPS","SQLDEVICES","UTILS"

$Destinos = $Destino2,$Destino2,$Destino2,$Destino2,$Destino1,"*",$Destino2, `
            $Destino2,$Destino2,$Destino2,"*",$Destino1,$Destino1,$Destino1,$Destino2

Write-Host
# Verificando se a VM1 e a VM2 estao ligadas
Do {
    $Ficar = $false
    Foreach ($VM in $VMs) {
        Write-Host "Checando estado da VM"$VM"..."
        $Estado = Get-VMIntegrationService -VMName $VM -Name Heartbeat
        if ($Estado.PrimaryStatusDescription -ne "OK") {
            $Ficar = $true
            Write-Host -ForegroundColor Yellow "VM $VM parece estar desligada! Inicie-a manualmente via Hyper-V Manager"
            Write-Host -ForegroundColor Yellow "e pressione ENTER para fazer nova verificacao."
            Pause
        }
    }
} While ($Ficar)

# Checando conexao com o servidor antigo
Do {
    Write-Host "Checando estado do servidor"$ServidorAntigo"..."
    $Sair = (Test-Connection -ComputerName $ServidorAntigo -Quiet)
    if (-not $Sair) {
        Write-Host -ForegroundColor Yellow "Impossivel enviar e receber PING do $ServidorAntigo! Verifique se o mesmo"
        Write-Host -ForegroundColor Yellow "encontra-se ligado e com permissao no firewall do Windows para enviar PING."
        Write-Host -ForegroundColor Yellow "Pressione ENTER para fazer nova verificacao."
        Pause
    }
} While (-not $Sair)

# Apagando arquivo de comparacoes caso ja exista
Try {
    Remove-Item $FileComparacao -Force | Out-Null
}
Catch {
    # Houve falha na remocao ou o arquivo nao existe!  Se o arquivo nao existir, nao ha problema,
    # pois o script inicia a gravacao a partir do zero.
}

# Se forem especificados ambos os drives, precisara comparar pastas nos drives D: e Secundario.
# Do contrario, verificar apenas o drive D:.
if ($Drive -eq "A") {
    $Unidades = "D",$Secundario
}
else {
    $Unidades = "D"
}
$ArqRelat = $FileComparacao
Write-Host; Write-Host "Calculando itens e tamanhos. Isto pode demorar alguns minutos..."
for ($i = 0; $i -lt $Pastas.Count; $i++) {
    "Pasta: " + $Pastas[$i] | Out-File $ArqRelat -Append
    Foreach ($Unidade in $Unidades) {
        "Disco: " + $Unidade + ":" | Out-File $ArqRelat -Append
        if (($Pastas[$i] -eq "AREAS") -or ($Pastas[$i] -eq "PUBLICO")) {
            $A = "\\"+$ServidorAntigo+"\DISCO"+$Unidade+"$\"+$PrefixoServidor+"\"+$Pastas[$i]
        }
        else {
            $A = "\\"+$ServidorAntigo+"\DISCO"+$Unidade+"$\"+$Pastas[$i]
        }
        Try {
            if ($Pastas[$i] -eq "PERFIS") {
                $TamOrigem = PegarTamanho $A $PerfisExcluir
            }
            else {
                $TamOrigem = PegarTamanho $A ""
            }
            "Itens na Origem: " + $TamOrigem.Count + "         Tamanho na Origem: " + `
            $TamOrigem.Size + " " + $TamOrigem.Unit + "B`r`n" | Out-File $ArqRelat -Append
        }
        Catch {
            "Itens na Origem: FALHA         Tamanho na Origem: FALHA`r`n" | Out-File $ArqRelat -Append
        }
    }
    if ($Destinos[$i] -eq "*") {
        for ($j = 0; $j -lt $Todos.Count; $j++) {
            if (($Pastas[$i] -eq "AREAS") -or ($Pastas[$i] -eq "PERFIS") -or ($Pastas[$i] -eq "PUBLICO")) {
                $B = "\\"+$Todos[$j]+"\D$\"+$PrefixoServidor+"\"+$Pastas[$i]
            }
            else {
                $B = "\\"+$Todos[$j]+"\D$\"+$Pastas[$i]
            }
            Try {
                if ($Pastas[$i] -eq "PERFIS") {
                    $TamDestino = PegarTamanho $B $PerfisExcluir
                }
                else {
                    $TamDestino = PegarTamanho $B ""
                }
                "Destino:  " + $Todos[$j] | Out-File $ArqRelat -Append
                "Itens no Destino: " + $TamDestino.Count + "        Tamanho no Destino: " + `
                $TamDestino.Size + " " + $TamDestino.Unit + "B`r`n" | Out-File $ArqRelat -Append
            }
            Catch {
                "Destino:  "  + $Todos[$j] | Out-File $ArqRelat -Append
                "Itens no Destino: FALHA        Tamanho no Destino: FALHA`r`n" | Out-File $ArqRelat -Append
            }
        }
    }
    else {
        if (($Pastas[$i] -eq "AREAS") -or ($Pastas[$i] -eq "PERFIS") -or ($Pastas[$i] -eq "PUBLICO")) {
            $B = "\\"+$Destinos[$i]+"\D$\"+$PrefixoServidor+"\"+$Pastas[$i]
        }
        else {
            $B = "\\"+$Destinos[$i]+"\D$\"+$Pastas[$i]
        }
        Try {
            if ($Pastas[$i] -eq "PERFIS") {
                $TamDestino = PegarTamanho $B $PerfisExcluir
            }
            else {
                $TamDestino = PegarTamanho $B ""
            }
            "Destino:  " + $Destinos[$i] | Out-File $ArqRelat -Append
            "Itens no Destino: " + $TamDestino.Count + "        Tamanho no Destino: " + `
            $TamDestino.Size + " " + $TamDestino.Unit + "B" | Out-File $ArqRelat -Append
        }
        Catch {
            "Destino:  " + $Destinos[$i] | Out-File $ArqRelat -Append
            "Itens no Destino: FALHA        Tamanho no Destino: FALHA" | Out-File $ArqRelat -Append
        }
    }
    "------------------------------------------------------------------`r`n" | Out-File $ArqRelat -Append
}

"*** Fim de Relatorio ***" | Out-File $ArqRelat -Append
