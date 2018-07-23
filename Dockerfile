#https://github.com/StefanScherer/dockerfiles-windows/blob/master/node/8/Dockerfile
#https://github.com/NuGardt/docker-msbuild/blob/master/msbuild.15.5.Dockerfile
#https://hub.docker.com/r/microsoft/dotnet-framework/

ARG core=microsoft/windowsservercore:10.0.14393.2007
ARG target=microsoft/dotnet-framework:4.7.2-runtime-windowsservercore-ltsc2016

FROM $core as download

#NodeJS
SHELL ["powershell.exe", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; $VerbosePreference = 'Continue';"]
ENV NODE_VERSION 9.4.0
ENV GPG_VERSION 2.3.4

RUN Invoke-WebRequest $('https://files.gpg4win.org/gpg4win-vanilla-{0}.exe' -f $env:GPG_VERSION) -OutFile 'gpg4win.exe' -UseBasicParsing ; \
    Start-Process .\gpg4win.exe -ArgumentList '/S' -NoNewWindow -Wait

RUN @( \
    '94AE36675C464D64BAFA68DD7434390BDBE9B9C5', \
    'FD3A5288F042B6850C66B31F09FE44734EB7990E', \
    '71DCFD284A79C3B38668286BC97EC7A07EDE3FC1', \
    'DD8F2338BAE7501E3DD5AC78C273792F7D83545D', \
    'C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8', \
    'B9AE9905FFD7803F25714661B63B535A4C206CA9', \
    '56730D5401028683275BD23C23EFEFE93C4CFFFE', \
    '77984A986EBC2AA786BC0F66B01FBB92821C587A', \
    '8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600' \
    ) | foreach { \
      gpg --keyserver ha.pool.sks-keyservers.net --recv-keys $_ ; \
    }

RUN Invoke-WebRequest $('https://nodejs.org/dist/v{0}/SHASUMS256.txt.asc' -f $env:NODE_VERSION) -OutFile 'SHASUMS256.txt.asc' -UseBasicParsing ; \
    gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc

RUN Invoke-WebRequest $('https://nodejs.org/dist/v{0}/node-v{0}-win-x64.zip' -f $env:NODE_VERSION) -OutFile 'node.zip' -UseBasicParsing ; \
    $sum = $(cat SHASUMS256.txt.asc | sls $('  node-v{0}-win-x64.zip' -f $env:NODE_VERSION)) -Split ' ' ; \
    if ((Get-FileHash node.zip -Algorithm sha256).Hash -ne $sum[0]) { Write-Error 'SHA256 mismatch' } ; \
    Expand-Archive node.zip -DestinationPath C:\ ; \
    Rename-Item -Path $('C:\node-v{0}-win-x64' -f $env:NODE_VERSION) -NewName 'C:\nodejs' 
	
FROM $target

LABEL description "Microsoft .NET Build Tools 2017 (v15.5) with NuGet v4.5.0, Web Deploy v3.5, Developer Packs v4.5.2, 4.6.2 and .Net Core v1.1.7 and v2.1.4 SDK, NodeJS 8.11.3."; \

ENV NPM_CONFIG_LOGLEVEL info

COPY --from=download /nodejs /nodejs
RUN	c:\nodejs\npm i -g concurrently rimraf webpack webpack-command cross-env npm-run-all lerna 

# MSBuild
# Download log collection utility
SHELL ["powershell", "-ExecutionPolicy", "Bypass", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; $VerbosePreference = 'Continue';"]
RUN Invoke-WebRequest -Uri https://aka.ms/vscollect.exe -OutFile C:\collect.exe


# Download NuGardt v4.5.0
RUN New-Item -Path C:\nuget -Type Directory | Out-Null; \
	[System.Environment]::SetEnvironmentVariable('PATH', "\"${env:PATH};C:\nuget\"", 'Machine'); \
	Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/v4.5.0/nuget.exe" -OutFile C:\nuget\nuget.exe; 

# Download and install Microsoft Build Tools 15 (latest)
RUN Invoke-WebRequest -Uri "https://aka.ms/vs/15/release/vs_buildtools.exe" -OutFile $env:TEMP\vs_buildtools.exe; \
	$p = Start-Process -Wait -PassThru -FilePath $env:TEMP\vs_buildtools.exe -ArgumentList '--add Microsoft.VisualStudio.Workload.MSBuildTools --add Microsoft.VisualStudio.Workload.NetCoreBuildTools --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Workload.WebBuildTools --quiet --nocache --wait --installPath C:\BuildTools'; \
	if ($ret = $p.ExitCode) { c:\collect.exe; throw ('Install failed with exit code 0x{0:x}' -f $ret) }; \
	rm "$env:TEMP\vs_buildtools.exe"

# Install Targeting Packs
RUN @('4.0', '4.5.2', '4.6.2', '4.7.2') \
    | %{ \
        Invoke-WebRequest -UseBasicParsing https://dotnetbinaries.blob.core.windows.net/referenceassemblies/v${_}.zip -OutFile referenceassemblies.zip; \
        Expand-Archive -Force referenceassemblies.zip -DestinationPath \"${Env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\"; \
        Remove-Item -Force referenceassemblies.zip; \
    }

# Download and install .Net Core v2.1.4 SDK
RUN Invoke-WebRequest "https://download.microsoft.com/download/1/1/5/115B762D-2B41-4AF3-9A63-92D9680B9409/dotnet-sdk-2.1.4-win-x64.exe" -OutFile "$env:TEMP\dotnet-sdk-2.1.4-win-x64.exe" -UseBasicParsing; \
	$p = Start-Process -Wait -PassThru -FilePath "$env:TEMP\dotnet-sdk-2.1.4-win-x64.exe" -ArgumentList "/install","/quiet"; \
	if ($ret = $p.ExitCode) { c:\collect.exe; throw ('Install failed with exit code 0x{0:x}' -f $ret) }; \
	rm "$env:TEMP\dotnet-sdk-2.1.4-win-x64.exe"

# Use shell form to start developer command prompt and any other commands specified

SHELL ["cmd.exe", "/s", "/c"]
RUN	setx PATH "%PATH%;C:\nodejs" -m
ENTRYPOINT C:\BuildTools\Common7\Tools\VsDevCmd.bat &&

CMD ["powershell.exe", "-nologo"]


